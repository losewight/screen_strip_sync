#include "light_engine.h"

#include "dxgi_capture.h"
#include "serial_port.h"
#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>

// 为什么：主线程改 false，发帧线程 while 退出；Day7 的停止标志。
static std::atomic<bool> g_running{false};
static std::thread g_worker;
// 为什么：IPC 写、发帧线程读；热路径不加锁，只 load
static std::atomic<float> g_alpha{0.3f};
// 为什么：'a'|'b'；阶段 C 前 produce_colors 不读，仅防配置丢失
static std::atomic<char> g_mode{'a'};
// 为什么：字符串不能 atomic；set/reconnect 都在 IPC 线程，启动在
// main，仍用锁防竞态
static std::mutex g_com_mu;
static char g_com_name[16] = "COM10";
// 为什么：EMA 需要「上一帧平滑结果」；10 段 × RGB
static float g_ema_r[10] = {};
static float g_ema_g[10] = {};
static float g_ema_b[10] = {};
static bool g_ema_inited = false;

// 为什么：休眠软关会发临时黑帧，意图必须单独存，不能被黑帧冲掉
static std::mutex g_intent_mu;
static DisplayIntent g_intent{};

void engine_set_alpha(float alpha) {
  // 与 Flutter AppConfig 对齐：[0.05, 1.0]
  if (alpha < 0.05f)
    alpha = 0.05f;
  if (alpha > 1.f)
    alpha = 1.f;
  g_alpha.store(alpha);
}

void engine_set_mode(char mode) {
  // 调用前已校验；统一存小写
  g_mode.store(mode);
}

bool engine_set_com(const char *name) {
  if (name == nullptr)
    return false;
  while (*name == ' ' || *name == '\t')
    ++name;

  // 期望 COMn / comn，n 为 1～3 位数字
  char c0 = name[0], c1 = name[1], c2 = name[2];
  if (!((c0 == 'C' || c0 == 'c') && (c1 == 'O' || c1 == 'o') &&
        (c2 == 'M' || c2 == 'm')))
    return false;

  const char *digits = name + 3;
  if (*digits < '0' || *digits > '9')
    return false;
  int n = 0;
  while (digits[n] >= '0' && digits[n] <= '9') {
    ++n;
    if (n > 3)
      return false;
  }
  if (n < 1)
    return false;
  const char *rest = digits + n;
  while (*rest == ' ' || *rest == '\t')
    ++rest;
  if (*rest != '\0')
    return false;

  char norm[16];
  // 规范成 COM + 数字
  snprintf(norm, sizeof(norm), "COM%.*s", n, digits);

  std::lock_guard<std::mutex> lock(g_com_mu);
  snprintf(g_com_name, sizeof(g_com_name), "%s", norm);
  return true;
}

static void play_strip_scan(HANDLE h);

bool try_serial_ready(HANDLE *out_h) {
  char name[16];
  {
    std::lock_guard<std::mutex> lock(g_com_mu);
    snprintf(name, sizeof(name), "%s", g_com_name);
  }
  HANDLE h = INVALID_HANDLE_VALUE;
  if (!open_com(name, &h)) {
    printf("open_com %s failed\n", name);
    return false;
  }
  if (!power_on(h) || !handshake(h)) {
    power_off(h);
    close_com(h);
    return false;
  }
  play_strip_scan(h);
  *out_h = h;
  printf("serial ready on %s\n", name);
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

// 握手后自检：00FFFF 以 2 段为步幅从头到尾依次亮起（已亮保持）
static bool send_seq_frame(HANDLE h, int frame_id, int lit_through) {
  char colors[10][7];
  for (int seg = 0; seg < 10; ++seg) {
    const char *color = (seg <= lit_through) ? "00ffff" : "000000";
    snprintf(colors[seg], 7, "%s", color);
  }

  char frame[128];
  const int n = snprintf(frame, sizeof(frame),
                         "set_rgb_pc %04x 00 63 "
                         "%s 2 %s 2 %s 2 %s 2 %s 2 "
                         "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
                         frame_id & 0xFFFF, colors[0], colors[1], colors[2],
                         colors[3], colors[4], colors[5], colors[6], colors[7],
                         colors[8], colors[9]);
  if (n < 0 || (size_t)n >= sizeof(frame))
    return false;

  const DWORD len = (DWORD)strlen(frame);
  if (len >= 120)
    return false;
  if (!send_one_frame(h, frame, len))
    return false;
  Sleep(300); // 自检动画用 300ms 间隔（仍 ≥50ms 红线）
  return true;
}

static void play_strip_scan(HANDLE h) {
  int frame_id = 1;

  // lit_through：当前已亮到的段下标（含），每步 +2
  for (int lit_through = 1; lit_through < 10; lit_through += 2) {
    if (!send_seq_frame(h, frame_id++, lit_through)) {
      printf("strip seq light failed at segment %d\n", lit_through);
      return;
    }
  }
  printf("strip seq light ok\n");
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

  // α 越小越拖影；由 IPC set alpha 写入 g_alpha
  const float alpha = g_alpha.load();
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

void engine_set_intent_idle() {
  std::lock_guard<std::mutex> lock(g_intent_mu);
  g_intent.kind = DisplayIntentKind::Idle;
  g_intent.solid[0] = '\0';
}

void engine_set_intent_engine() {
  std::lock_guard<std::mutex> lock(g_intent_mu);
  g_intent.kind = DisplayIntentKind::Engine;
  g_intent.solid[0] = '\0';
}

void engine_set_intent_solid(const char *rrggbb) {
  if (rrggbb == nullptr || strlen(rrggbb) != 6)
    return;
  std::lock_guard<std::mutex> lock(g_intent_mu);
  g_intent.kind = DisplayIntentKind::Solid;
  // 规范成小写 hex，恢复时直接组帧
  for (int i = 0; i < 6; ++i) {
    char c = rrggbb[i];
    if (c >= 'A' && c <= 'F')
      c = (char)(c - 'A' + 'a');
    g_intent.solid[i] = c;
  }
  g_intent.solid[6] = '\0';
}

void engine_set_intent_soft_off() {
  std::lock_guard<std::mutex> lock(g_intent_mu);
  g_intent.kind = DisplayIntentKind::SoftOff;
  g_intent.solid[0] = '\0';
}

DisplayIntent engine_get_display_intent() {
  std::lock_guard<std::mutex> lock(g_intent_mu);
  return g_intent;
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

bool engine_is_running() { return g_running.load(); }

void engine_get_com(char *buf, size_t cap) {
  if (buf == nullptr || cap == 0)
    return;
  std::lock_guard<std::mutex> lock(g_com_mu);
  snprintf(buf, cap, "%s", g_com_name);
}
