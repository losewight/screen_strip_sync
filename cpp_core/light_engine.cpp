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
// 为什么：托盘菜单与 IPC 可能并发 start/stop，必须串行化防双 worker
static std::mutex g_engine_mu;
// 为什么：IPC 写、发帧线程读；热路径不加锁，只 load
static std::atomic<float> g_alpha{0.3f};
// 为什么：'a'|'b'；阶段 C 前 produce_colors 不读，仅防配置丢失
static std::atomic<char> g_mode{'a'};
// 为什么：字符串不能 atomic；set/reconnect 都在 IPC 线程，启动在
// main，仍用锁防竞态
static std::mutex g_com_mu;
// 为什么：业务默认口只来自 HelperConfig；开串口前必须 config_apply / set com
static char g_com_name[16] = "";
// 为什么：map 与调色正交；IPC 写、发帧读，短锁拷贝快照
static std::mutex g_map_mu;
static bool g_map_custom = false;
static SegmentRect g_map[kSegmentCount] = {};
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

void engine_set_near_black(int v) { dxgi_set_near_black(v); }

void engine_set_blur(int v) { dxgi_set_blur(v); }

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

bool engine_set_map_from_ipc(const char *payload) {
  if (payload == nullptr)
    return false;
  while (*payload == ' ' || *payload == '\t')
    ++payload;

  SegmentRect parsed[kSegmentCount];
  const char *p = payload;
  for (int i = 0; i < kSegmentCount; ++i) {
    auto read_int = [](const char *&q, int *out) -> bool {
      if (*q < '0' || *q > '9')
        return false;
      int v = 0;
      while (*q >= '0' && *q <= '9') {
        v = v * 10 + (*q - '0');
        if (v > 100)
          return false;
        ++q;
      }
      *out = v;
      return true;
    };
    int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    if (!read_int(p, &x0) || *p != ',')
      return false;
    ++p;
    if (!read_int(p, &y0) || *p != ',')
      return false;
    ++p;
    if (!read_int(p, &x1) || *p != ',')
      return false;
    ++p;
    if (!read_int(p, &y1))
      return false;
    if (x0 < 0 || y0 < 0 || x1 > 100 || y1 > 100 || x0 >= x1 || y0 >= y1)
      return false;
    parsed[i].x0 = x0 / 100.f;
    parsed[i].y0 = y0 / 100.f;
    parsed[i].x1 = x1 / 100.f;
    parsed[i].y1 = y1 / 100.f;
    if (i + 1 < kSegmentCount) {
      if (*p != ';')
        return false;
      ++p;
    }
  }
  while (*p == ' ' || *p == '\t')
    ++p;
  if (*p != '\0')
    return false;

  std::lock_guard<std::mutex> lock(g_map_mu);
  for (int i = 0; i < kSegmentCount; ++i)
    g_map[i] = parsed[i];
  g_map_custom = true;
  return true;
}

void engine_clear_map() {
  std::lock_guard<std::mutex> lock(g_map_mu);
  g_map_custom = false;
}

void engine_copy_map_snapshot(bool *out_custom,
                              SegmentRect out_rects[kSegmentCount]) {
  if (out_custom == nullptr || out_rects == nullptr)
    return;
  std::lock_guard<std::mutex> lock(g_map_mu);
  *out_custom = g_map_custom;
  if (g_map_custom) {
    for (int i = 0; i < kSegmentCount; ++i)
      out_rects[i] = g_map[i];
  }
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

bool send_highlight(HANDLE h, int seg) {
  if (seg < 0 || seg >= kSegmentCount)
    return false;
  const char *colors[kSegmentCount];
  for (int i = 0; i < kSegmentCount; ++i)
    colors[i] = (i == seg) ? "ffffff" : "000000";

  char frame[128];
  snprintf(frame, sizeof(frame),
           "set_rgb_pc %04x 00 63 "
           "%s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           1, colors[0], colors[1], colors[2], colors[3], colors[4], colors[5],
           colors[6], colors[7], colors[8], colors[9]);

  DWORD len = (DWORD)strlen(frame);
  if (len >= 120) {
    printf("highlight frame too long: %lu\n", (unsigned long)len);
    return false;
  }
  if (!send_one_frame(h, frame, len))
    return false;
  Sleep(50);
  return true;
}

// 为什么：produce = 抓屏采样；AccessLost 交给 frame_loop 拆再建；
// timeout / 其它失败跳过本帧
static DxgiErr produce_colors(int frame_index, char *out_frame,
                              size_t out_cap) {
  unsigned char rgb[10][3] = {};
  bool custom = false;
  SegmentRect rects[kSegmentCount];
  engine_copy_map_snapshot(&custom, rects);
  // 调用：有自定义表则按矩形采；否则顶边默认
  DxgiErr e = dxgi_grab_and_sample(50, rgb, custom ? rects : nullptr);
  if (e != DxgiErr::Ok)
    return e;

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
    return DxgiErr::AcquireFailed;
  return DxgiErr::Ok;
}

static bool consumer_to_serial(HANDLE h, const char *frame, DWORD frame_len) {
  if (!send_one_frame(h, frame, frame_len))
    return false;
  Sleep(50);
  return true;
}

static void frame_loop(HANDLE h) {
  int i = 0;
  int recover_fails = 0;
  DWORD last_recover_log = 0;
  while (g_running.load()) {
    char frame_buf[128];
    DxgiErr e = produce_colors(i, frame_buf, sizeof(frame_buf));
    // DuplicateFailed：recover 拆掉后 init 失败，指针已空，须继续试再建
    if (e == DxgiErr::AccessLost || e == DxgiErr::DuplicateFailed) {
      // 为什么：ACCESS_LOST 后死指针仍非空，必须 recover 而非 ensure
      const DWORD now = GetTickCount();
      if (now - last_recover_log >= 2000) {
        printf("frame_loop: DXGI access lost, recovering\n");
        last_recover_log = now;
      }
      if (engine_recover_dxgi()) {
        recover_fails = 0;
        continue;
      }
      ++recover_fails;
      // 首败已立刻试过；之后 200ms 起，连续失败拉长，上限 2s
      DWORD sleep_ms = 200u * (DWORD)recover_fails;
      if (sleep_ms > 2000)
        sleep_ms = 2000;
      Sleep(sleep_ms);
      continue;
    }
    if (e != DxgiErr::Ok) {
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

bool engine_ensure_dxgi() {
  if (dxgi_is_ready())
    return true;
  DxgiErr e = dxgi_init();
  if (e != DxgiErr::Ok) {
    printf("engine_ensure_dxgi failed: %d\n", (int)e);
    return false;
  }
  printf("engine_ensure_dxgi: re-inited\n");
  return true;
}

bool engine_recover_dxgi() {
  // 为什么：ACCESS_LOST 后指针仍非空，ensure 会误判 ready；必须先拆再建
  dxgi_shutdown();
  DxgiErr e = dxgi_init();
  if (e != DxgiErr::Ok) {
    printf("engine_recover_dxgi failed: %d\n", (int)e);
    return false;
  }
  printf("engine_recover_dxgi: ok\n");
  return true;
}

void apply_display_intent(HANDLE h, const DisplayIntent &intent) {
  if (h == nullptr || h == INVALID_HANDLE_VALUE) {
    printf("apply_display_intent: no serial\n");
    return;
  }
  switch (intent.kind) {
  case DisplayIntentKind::Engine:
    if (!engine_ensure_dxgi())
      return;
    engine_start(h);
    engine_set_intent_engine();
    printf("apply_display_intent: engine\n");
    break;
  case DisplayIntentKind::Solid:
    engine_stop();
    engine_set_intent_solid(intent.solid);
    send_solid(h, intent.solid);
    printf("apply_display_intent: solid %s\n", intent.solid);
    break;
  case DisplayIntentKind::SoftOff:
    engine_stop();
    engine_set_intent_soft_off();
    send_solid(h, "000000");
    printf("apply_display_intent: soft_off\n");
    break;
  case DisplayIntentKind::Idle:
  default:
    engine_stop();
    engine_set_intent_idle();
    printf("apply_display_intent: idle\n");
    break;
  }
}

bool parse_last_scene(const char *s, DisplayIntent *out) {
  if (!s || !out)
    return false;
  DisplayIntent intent{};
  if (strcmp(s, "engine") == 0) {
    intent.kind = DisplayIntentKind::Engine;
  } else if (strcmp(s, "idle") == 0) {
    intent.kind = DisplayIntentKind::Idle;
  } else if (strcmp(s, "off") == 0) {
    intent.kind = DisplayIntentKind::SoftOff;
  } else if (strncmp(s, "solid ", 6) == 0) {
    const char *hex = s + 6;
    if (strlen(hex) != 6)
      return false;
    for (int i = 0; i < 6; ++i) {
      char c = hex[i];
      if (c >= 'A' && c <= 'F')
        c = (char)(c - 'A' + 'a');
      else if (c >= 'a' && c <= 'f')
        ;
      else if (c >= '0' && c <= '9')
        ;
      else
        return false;
      intent.solid[i] = c;
    }
    intent.solid[6] = '\0';
    intent.kind = DisplayIntentKind::Solid;
  } else {
    return false;
  }
  *out = intent;
  return true;
}

void engine_start(HANDLE h) {
  std::lock_guard<std::mutex> lock(g_engine_mu);
  if (g_running.load())
    return; // 避免重复 start 起两个线程
  // 为什么：休眠 teardown 会 dxgi_shutdown；追色前必须再 init
  if (!dxgi_is_ready()) {
    DxgiErr e = dxgi_init();
    if (e != DxgiErr::Ok) {
      printf("engine_start: dxgi_init failed: %d\n", (int)e);
      return;
    }
  }
  g_running.store(true);
  g_worker = std::thread(frame_loop, h);
}

void engine_request_stop() { g_running.store(false); }

void engine_stop() {
  std::lock_guard<std::mutex> lock(g_engine_mu);
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
