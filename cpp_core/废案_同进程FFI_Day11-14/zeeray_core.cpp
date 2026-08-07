#include "../engine/serial_port.h"
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <thread>

#define ZEERAY_EXPORT __declspec(dllexport)

// 句柄归 DLL 静态数据段所有；调用方只拿成功/失败，不拿 HANDLE。
static HANDLE g_port = INVALID_HANDLE_VALUE;
// 线程归 DLL 管；Dart 只调 start/stop，不拿 thread 对象
static std::atomic<bool> g_running{false};
static std::thread g_worker;
static bool g_engine_running = false;

// 电源打开
static bool power_on(HANDLE h) {
  if (!send_one_frame(h, "set_power 1\r\n",
                      (DWORD)(strlen("set_power 1\r\n")))) {
    return false;
  }
  return read_response_ok(h, 500);
}

// 生产颜色帧
static void produce_colors(int frame_index, char *out_frame, size_t out_cap) {
  const unsigned frame_id = (unsigned)frame_index & 0xFFFFu;
  if (frame_index % 2 != 0) {
    snprintf(
        out_frame, out_cap,
        "set_rgb_pc %04x 00 63 ff0000 2 0000ff 2 ff0000 2 0000ff 2 ff0000 2 "
        "0000ff 2 ff0000 2 0000ff 2 ff0000 2 0000ff 2\r\n",
        frame_id);
  } else {
    snprintf(
        out_frame, out_cap,
        "set_rgb_pc %04x 00 63 00ff00 2 ff00ff 2 00ff00 2 ff00ff 2 00ff00 2 "
        "ff00ff 2 00ff00 2 ff00ff 2 00ff00 2 ff00ff 2\r\n",
        frame_id);
  }
}
// 消费颜色帧
static bool consumer_to_serial(HANDLE h, const char *frame, DWORD frame_len) {
  if (!send_one_frame(h, frame, frame_len))
    return false;
  Sleep(50);
  return true;
}
// 帧循环
static void frame_loop(HANDLE h) {
  int i = 0;
  while (g_running.load()) {
    char frame_buf[128];
    produce_colors(i, frame_buf, sizeof(frame_buf));
    if (!consumer_to_serial(h, frame_buf, (DWORD)strlen(frame_buf)))
      break;
    i++;
  }
}

// 电源关闭
static bool power_off(HANDLE h) {
  if (!send_one_frame(h, "set_power 0\r\n",
                      (DWORD)(strlen("set_power 0\r\n")))) {
    return false;
  }
  return read_response_ok(h, 500);
}

// 握手
static bool handshake(HANDLE h) {
  if (!send_one_frame(h, "set_pc_available 1\r\n", 20))
    return false;
  if (!read_response_ok(h, 500))
    return false;
  if (!send_one_frame(h, "set_usb_dim_time 20\r\n", 21))
    return false; // 注意这个可能是灯光过渡时间
  if (!read_response_ok(h, 500))
    return false;
  if (!send_one_frame(h, "set_pc_linkage 1\r\n", 18))
    return false;
  return read_response_ok(h, 500);
}

// 导出函数，供 Dart 语言调用
extern "C" {
ZEERAY_EXPORT int32_t zeeray_get_version() { return 100; }

// port_name：调用方拥有；本函数只读，不保存指针、不 free。
ZEERAY_EXPORT int32_t zeeray_open(const char *port_name) {
  if (g_port != INVALID_HANDLE_VALUE) {
    return 1; // 已经开过，直接算成功
  }
  if (!open_com(port_name, &g_port)) {
    g_port = INVALID_HANDLE_VALUE;
    return 0; // 打开失败，返回失败
  }
  if (!power_on(g_port) || !handshake(g_port)) {
    close_com(g_port);
    g_port = INVALID_HANDLE_VALUE;
    return 0;
  }
  return 1; // 打开成功，返回成功
}

ZEERAY_EXPORT void zeeray_stop_engine(); // 只声明，定义仍在下面

ZEERAY_EXPORT void zeeray_close() {
  if (g_port == INVALID_HANDLE_VALUE) {
    return; // 已经关过或没开过，直接算成功
  }
  // 先停止引擎
  zeeray_stop_engine();

  power_off(g_port); // 先发出关闭电源命令
  close_com(g_port); // 再关闭串口
  g_port = INVALID_HANDLE_VALUE;
}

// r,g,b 按值传入；帧缓冲在栈上，不跨调用存活。
ZEERAY_EXPORT int32_t zeeray_set_color(uint8_t r, uint8_t g, uint8_t b) {
  if (g_port == INVALID_HANDLE_VALUE) {
    return 0; // 没开过，返回失败
  }
  char color[7];
  snprintf(color, sizeof(color), "%02x%02x%02x", r, g, b);
  char frame[128];
  unsigned frame_id = 1;
  snprintf(frame, sizeof(frame),
           "set_rgb_pc %04x 00 63 %s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           frame_id, color, color, color, color, color, color, color, color,
           color, color);
  if (!send_one_frame(g_port, frame, (DWORD)(strlen(frame)))) {
    return 0; // 发送失败，返回失败
  }
  Sleep(50); // 等待50ms
  return 1;  // 发送成功，返回成功
}

ZEERAY_EXPORT int32_t zeeray_start_engine() {
  if (g_port == INVALID_HANDLE_VALUE)
    return 0; // 没 open
  if (g_engine_running)
    return 1; // 已在跑

  g_running.store(true);
  g_worker = std::thread(frame_loop, g_port);
  g_engine_running = true;
  return 1;
}

ZEERAY_EXPORT void zeeray_stop_engine() {
  if (!g_engine_running)
    return;

  g_running.store(false); // 1. 让 while 退出
  if (g_worker.joinable())
    g_worker.join();        // 2. 等线程真正结束
  g_engine_running = false; // 3. 再改状态
}
}