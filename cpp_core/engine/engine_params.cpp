#include "engine_internal.h"

#include "config_clamp.h"
#include "dxgi_capture.h"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>

// 为什么：主线程改 false，发帧线程 while 退出；Day7 的停止标志。
std::atomic<bool> g_running{false};
std::thread g_worker;
// 为什么：托盘菜单与 IPC 可能并发 start/stop，必须串行化防双 worker
std::mutex g_engine_mu;
// 为什么：IPC 写、发帧线程读；热路径不加锁，只 load
std::atomic<float> g_alpha{1.f};
// 为什么：默认 1.0（UI 100% 原色）；IPC/JSON 可改
std::atomic<float> g_saturation{1.f};
// 固定 'n'=减去中性色；'l'=保持亮度仅旧兼容（加载/IPC 会被钳为 'n'）
std::atomic<char> g_saturation_algo{'n'};
// 为什么：'a'|'b'；亮度方案已废弃，仅防配置丢失
std::atomic<char> g_mode{'a'};
// 屏幕氛围参数（与 map alpha/near_black/blur 正交）
std::atomic<char> g_region_algo{'m'};
std::atomic<int> g_region_blur{3};
std::atomic<float> g_region_smooth{0.8f};
std::atomic<int> g_region_dark{15};
std::mutex g_region_bbox_mu;
int g_region_l = 10, g_region_t = 20, g_region_w = 80, g_region_h = 60;
// 为什么：start / start_region 写，frame_loop 读
std::atomic<SyncPath> g_sync_path{SyncPath::Map};
// 为什么：字符串不能 atomic；set/reconnect 都在 IPC 线程，启动在
// main，仍用锁防竞态
std::mutex g_com_mu;
// 为什么：业务默认口只来自 HelperConfig；开串口前必须 config_apply / set com
char g_com_name[16] = "";
// 为什么：map 与调色正交；IPC 写、发帧读，短锁拷贝快照
std::mutex g_map_mu;
bool g_map_custom = false;
SegmentRect g_map[kSegmentCount] = {};
// 为什么：EMA 需要「上一帧平滑结果」；10 段 × RGB
float g_ema_r[10] = {};
float g_ema_g[10] = {};
float g_ema_b[10] = {};
bool g_ema_inited = false;
SegGate g_seg_gate[10] = {};

// 为什么：休眠软关会发临时黑帧，意图必须单独存，不能被黑帧冲掉
std::mutex g_intent_mu;
DisplayIntent g_intent{};

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

void engine_set_sample_algo(char algo) { dxgi_set_sample_algo(algo); }

void engine_set_near_black_luma(char mode) { dxgi_set_near_black_luma(mode); }

void engine_set_saturation(float v) {
  if (v < 0.5f)
    v = 0.5f;
  if (v > 2.f)
    v = 2.f;
  g_saturation.store(v);
}

void engine_set_saturation_algo(char algo) {
  (void)algo;
  // UI 已撤；固定减去中性色，忽略 IPC/旧调用传入的 luma
  g_saturation_algo.store('n');
}

void engine_set_mode(char mode) {
  // 调用前已校验；统一存小写
  g_mode.store(mode);
}

void engine_set_region_algo(char algo) {
  g_region_algo.store((algo == 'x' || algo == 'X') ? 'x' : 'm');
}

void engine_set_region_blur(int v) {
  if (v < 0)
    v = 0;
  if (v > 20)
    v = 20;
  g_region_blur.store(v);
}

void engine_set_region_smooth(float v) {
  if (v < 0.f)
    v = 0.f;
  if (v > 0.99f)
    v = 0.99f;
  g_region_smooth.store(v);
}

void engine_set_region_dark(int v) {
  if (v < 0)
    v = 0;
  if (v > 50)
    v = 50;
  g_region_dark.store(v);
}

void engine_set_region_bbox(int l, int t, int w, int h) {
  l = clamp_pct(l);
  t = clamp_pct(t);
  w = clamp_pct(w);
  h = clamp_pct(h);
  if (l + w > 100)
    w = 100 - l;
  if (t + h > 100)
    h = 100 - t;
  // 为什么：l=100 时 w 会收成 0；再强制 w=1 会越出 100%，与 valid_region_bbox 不一致
  if (!valid_region_bbox(l, t, w, h))
    return;
  std::lock_guard<std::mutex> lock(g_region_bbox_mu);
  g_region_l = l;
  g_region_t = t;
  g_region_w = w;
  g_region_h = h;
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

void engine_get_com(char *buf, size_t cap) {
  if (buf == nullptr || cap == 0)
    return;
  std::lock_guard<std::mutex> lock(g_com_mu);
  snprintf(buf, cap, "%s", g_com_name);
}

bool engine_is_running() { return g_running.load(); }

SyncPath engine_sync_path() { return g_sync_path.load(); }
