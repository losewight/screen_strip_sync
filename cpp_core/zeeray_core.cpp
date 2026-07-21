#include "serial_port.h"
#include <cstdint>
#include <cstdio>
#include <cstring>

#define ZEERAY_EXPORT __declspec(dllexport)

// 句柄归 DLL 静态数据段所有；调用方只拿成功/失败，不拿 HANDLE。
static HANDLE g_port = INVALID_HANDLE_VALUE;

// 电源打开
static bool power_on(HANDLE h) {
  if (!send_one_frame(h, "set_power 1\r\n",
                      (DWORD)(strlen("set_power 1\r\n")))) {
    return false;
  }
  return read_response_ok(h, 500);
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
    return false;
  if (!read_response_ok(h, 500))
    return false;
  if (!send_one_frame(h, "set_pc_linkage 1\r\n", 18))
    return false;
  return read_response_ok(h, 500);
}

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

ZEERAY_EXPORT void zeeray_close() {
  if (g_port == INVALID_HANDLE_VALUE) {
    return; // 已经关过或没开过，直接算成功
  }
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
}