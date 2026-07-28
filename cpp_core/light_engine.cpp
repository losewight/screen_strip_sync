#include "light_engine.h"

#include "dxgi_capture.h"
#include "serial_port.h"
#include <atomic>
#include <cstdio>
#include <cstring>
#include <thread>

// 为什么：主线程改 false，发帧线程 while 退出；Day7 的停止标志。
static std::atomic<bool> g_running{false};
static std::thread g_worker;
// 为什么：EMA 需要「上一帧平滑结果」；10 段 × RGB
static float g_ema_r[10] = {};
static float g_ema_g[10] = {};
static float g_ema_b[10] = {};
static bool g_ema_inited = false;

bool try_serial_ready(HANDLE *out_h) {
  HANDLE h = INVALID_HANDLE_VALUE;
  if (!open_com("COM10", &h))
    return false;
  if (!power_on(h) || !handshake(h)) {
    power_off(h);
    close_com(h);
    return false;
  }
  *out_h = h;
  return true;
}

bool power_on(HANDLE h) {
  if (!send_one_frame(h, "set_power 1\r\n",
                      (DWORD)(strlen("set_power 1\r\n")))) {
    return false;
  }
  return read_response_ok(h, 500);
}

bool handshake(HANDLE h) {
  if (!send_one_frame(h, "set_pc_available 1\r\n", 20))
    return false;
  if (!read_response_ok(h, 500))
    return false;
  if (!send_one_frame(h, "set_usb_dim_time 45\r\n", 21))
    return false;
  if (!read_response_ok(h, 500))
    return false;
  if (!send_one_frame(h, "set_pc_linkage 1\r\n", 18))
    return false;
  return read_response_ok(h, 500);
}

bool power_off(HANDLE h) {
  if (!send_one_frame(h, "set_power 0\r\n",
                      (DWORD)(strlen("set_power 0\r\n")))) {
    return false;
  }
  return read_response_ok(h, 500);
}

bool send_solid(HANDLE h, const char *rrggbb) {
  char frame[128];
  snprintf(frame, sizeof(frame),
           "set_rgb_pc %04x 00 63 %s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           1, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb,
           rrggbb, rrggbb);

  DWORD len = (DWORD)strlen(frame);
  if (len >= 120) { // 红线：拒绝 >=120
    printf("frame too long: %lu\n", (unsigned long)len);
    return false;
  }
  if (!send_one_frame(h, frame, len))
    return false;
  Sleep(50); // 红线：帧间隔 ≥50ms
  return true;
}

// 为什么：produce = 抓屏采样；timeout 常见，应跳过本帧而不是当致命错误
static bool produce_colors(int frame_index, char *out_frame, size_t out_cap) {
  unsigned char rgb[10][3] = {};
  DxgiErr e = dxgi_grab_and_sample(50, rgb); // 循环里用短超时
  if (e != DxgiErr::Ok)
    return false;

  // α 越小越拖影；0.3 偏跟手像硬切，先用 0.1 看拖影
  const float alpha = 0.3f;
  char colors[10][7] = {};

  for (int i = 0; i < 10; ++i) {
    // 为什么：直接用采样字节做 EMA，不再 sscanf 绕 ASCII
    const float r = (float)rgb[i][0];
    const float g = (float)rgb[i][1];
    const float b = (float)rgb[i][2];

    if (!g_ema_inited) {
      g_ema_r[i] = r;
      g_ema_g[i] = g;
      g_ema_b[i] = b;
    } else {
      // out = α * new + (1-α) * old
      g_ema_r[i] = alpha * r + (1.f - alpha) * g_ema_r[i];
      g_ema_g[i] = alpha * g + (1.f - alpha) * g_ema_g[i];
      g_ema_b[i] = alpha * b + (1.f - alpha) * g_ema_b[i];
    }

    // 字符串只在组帧前出现一次
    snprintf(colors[i], 7, "%02x%02x%02x", (unsigned)(g_ema_r[i] + 0.5f),
             (unsigned)(g_ema_g[i] + 0.5f), (unsigned)(g_ema_b[i] + 0.5f));
  }
  g_ema_inited = true;

  const unsigned frame_id = (unsigned)frame_index & 0xFFFFu;
  snprintf(out_frame, out_cap,
           "set_rgb_pc %04x 00 63 "
           "%s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           frame_id, colors[0], colors[1], colors[2], colors[3], colors[4],
           colors[5], colors[6], colors[7], colors[8], colors[9]);

  // 红线：组完再查长度
  if (strlen(out_frame) >= 120)
    return false;
  return true;
}

static bool consumer_to_serial(HANDLE h, const char *frame, DWORD frame_len) {
  if (!send_one_frame(h, frame, frame_len))
    return false;
  Sleep(50);
  return true;
}

static void frame_loop(HANDLE h) {
  int i = 0;
  while (g_running.load()) {
    char frame_buf[128];
    if (!produce_colors(i, frame_buf, sizeof(frame_buf))) {
      Sleep(10);
      continue;
    }
    if (!consumer_to_serial(h, frame_buf, (DWORD)strlen(frame_buf)))
      break;
    i++;
  }
}

void engine_start(HANDLE h) {
  if (g_running.load())
    return; // 避免重复 start 起两个线程
  g_running.store(true);
  g_worker = std::thread(frame_loop, h);
}

void engine_request_stop() { g_running.store(false); }

void engine_stop() {
  g_running.store(false);
  if (g_worker.joinable())
    g_worker.join();
  g_ema_inited = false;
}
