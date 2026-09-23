#include "letterbox_detect.h"

#include <atomic>
#include <mutex>

namespace {

// 约 5% 灰；与 near_black 独立
constexpr int kBlackThreshold = 13;
// 检出后再吃毛刺
constexpr int kBlurRemovePx = 2;
// ~50 帧 @~60ms ≈ 3s 才改厚度
constexpr unsigned kBorderSwitchCnt = 50;
// 偶发抖动丢弃
constexpr unsigned kMaxInconsistentCnt = 10;
// ~167 帧 @~60ms ≈ 10s 才退回全屏
constexpr unsigned kUnknownSwitchCnt = 167;
// 只搜高度前 1/3
constexpr int kMaxScanFraction = 3;

std::atomic<bool> g_enabled{false};
std::atomic<bool> g_hard_disable{false};

std::mutex g_mu;
int g_inset = 0; // 稳定输出；上下同值
int g_prev_raw = 0;
bool g_prev_unknown = true;
bool g_current_unknown = true;
unsigned g_consistent = 0;
unsigned g_inconsistent = 0;

inline bool is_black_bgra(const unsigned char *px) {
  // BGRA：B=0 G=1 R=2
  return px[2] < kBlackThreshold && px[1] < kBlackThreshold &&
         px[0] < kBlackThreshold;
}

inline const unsigned char *px_at(const unsigned char *base, int stride,
                                  int bpp, int x, int y) {
  return base + (size_t)y * (size_t)stride + (size_t)x * (size_t)bpp;
}

// 顶：25/50/75；同行 ≥2 非黑才算内容
int scan_top(const unsigned char *p, int w, int h, int stride, int bpp) {
  const int x25 = w / 4;
  const int x50 = w / 2;
  const int x75 = (w * 3) / 4;
  const int y_max = h / kMaxScanFraction;
  for (int y = 0; y < y_max; ++y) {
    int non_black = 0;
    if (!is_black_bgra(px_at(p, stride, bpp, x25, y)))
      ++non_black;
    if (!is_black_bgra(px_at(p, stride, bpp, x50, y)))
      ++non_black;
    if (!is_black_bgra(px_at(p, stride, bpp, x75, y)))
      ++non_black;
    if (non_black >= 2)
      return y;
  }
  return -1; // unknown
}

// 底：25/75（躲开字幕中心）；两条都非黑才算（≥2）
int scan_bottom(const unsigned char *p, int w, int h, int stride, int bpp) {
  const int x25 = w / 4;
  const int x75 = (w * 3) / 4;
  const int y_max = h / kMaxScanFraction;
  const int last = h - 1;
  for (int d = 0; d < y_max; ++d) {
    const int y = last - d;
    int non_black = 0;
    if (!is_black_bgra(px_at(p, stride, bpp, x25, y)))
      ++non_black;
    if (!is_black_bgra(px_at(p, stride, bpp, x75, y)))
      ++non_black;
    if (non_black >= 2)
      return d;
  }
  return -1;
}

// 对称：max(top,bottom)+blur；unknown 若任一侧失败
void detect_raw(const unsigned char *p, int w, int h, int stride, int bpp,
                int *out_inset, bool *out_unknown) {
  const int top = scan_top(p, w, h, stride, bpp);
  const int bottom = scan_bottom(p, w, h, stride, bpp);
  if (top < 0 || bottom < 0) {
    *out_unknown = true;
    *out_inset = 0;
    return;
  }
  int inset = top > bottom ? top : bottom;
  // 为什么：先判真实厚度再 +blur。内容贴边时 top=0，若先 +2 会永远卡在 inset=2，
  // 无黑边也退不回 fullscreen（日志里 32→2 后挂死）。
  if (inset < 2) {
    *out_unknown = false;
    *out_inset = 0;
    return;
  }
  inset += kBlurRemovePx;
  // 内容至少留一点高度
  const int max_inset = (h / 2) - 2;
  if (max_inset < 0) {
    *out_unknown = true;
    *out_inset = 0;
    return;
  }
  if (inset > max_inset)
    inset = max_inset;
  *out_unknown = false;
  *out_inset = inset;
}

void log_inset_if_changed(int old_inset, int new_inset) {
  if (old_inset == new_inset)
    return;
  if (new_inset == 0)
    printf("letterbox inset=0 (fullscreen)\n");
  else
    printf("letterbox inset=%d\n", new_inset);
}

void update_hysteresis(int raw_inset, bool raw_unknown) {
  // 与 HyperHDR updateBorder 同思路：稳定才切换；unknown 更慢
  const bool same =
      (raw_unknown == g_prev_unknown) &&
      (raw_unknown || raw_inset == g_prev_raw);

  if (same) {
    ++g_consistent;
    g_inconsistent = 0;
  } else {
    ++g_inconsistent;
    if (g_inconsistent <= kMaxInconsistentCnt)
      return; // 丢弃抖动，保持 previous
    g_prev_raw = raw_inset;
    g_prev_unknown = raw_unknown;
    g_consistent = 0;
  }

  if (raw_unknown == g_current_unknown &&
      (raw_unknown || raw_inset == g_inset)) {
    g_inconsistent = 0;
    return;
  }

  if (raw_unknown) {
    if (g_consistent >= kUnknownSwitchCnt) {
      const int old = g_inset;
      g_inset = 0;
      g_current_unknown = true;
      log_inset_if_changed(old, 0);
    }
  } else {
    if (g_current_unknown || g_consistent >= kBorderSwitchCnt) {
      const int old = g_inset;
      g_inset = raw_inset;
      g_current_unknown = false;
      log_inset_if_changed(old, raw_inset);
    }
  }
}

} // namespace

void letterbox_set_enabled(bool on) {
  const bool prev = g_enabled.exchange(on);
  if (prev == on)
    return;
  printf("letterbox enable=%d\n", on ? 1 : 0);
  if (!on) {
    std::lock_guard<std::mutex> lock(g_mu);
    const int old = g_inset;
    g_inset = 0;
    g_current_unknown = true;
    g_prev_unknown = true;
    g_prev_raw = 0;
    g_consistent = 0;
    g_inconsistent = 0;
    log_inset_if_changed(old, 0);
  }
}

void letterbox_set_hard_disable(bool on) {
  const bool prev = g_hard_disable.exchange(on);
  if (prev != on)
    printf("letterbox hard_disable=%d\n", on ? 1 : 0);
  // 进入/离开 hold 都清状态，避免解除后瞬间用陈旧 inset
  std::lock_guard<std::mutex> lock(g_mu);
  const int old = g_inset;
  g_inset = 0;
  g_current_unknown = true;
  g_prev_unknown = true;
  g_prev_raw = 0;
  g_consistent = 0;
  g_inconsistent = 0;
  // hold 进出清零：仅从非 0 落下时记一条，避免与 enable 日志重复刷
  if (on)
    log_inset_if_changed(old, 0);
}

void letterbox_reset() {
  std::lock_guard<std::mutex> lock(g_mu);
  const int old = g_inset;
  g_inset = 0;
  g_current_unknown = true;
  g_prev_unknown = true;
  g_prev_raw = 0;
  g_consistent = 0;
  g_inconsistent = 0;
  log_inset_if_changed(old, 0);
}

void letterbox_process_bgra(const unsigned char *pixels, int width, int height,
                            int stride, int bpp) {
  if (!pixels || width < 8 || height < 8 || bpp < 4)
    return;
  if (!g_enabled.load() || g_hard_disable.load()) {
    std::lock_guard<std::mutex> lock(g_mu);
    // 已在 set_enabled/hard_disable 清过；热路径不再打日志
    g_inset = 0;
    return;
  }

  int raw = 0;
  bool unknown = true;
  detect_raw(pixels, width, height, stride, bpp, &raw, &unknown);

  std::lock_guard<std::mutex> lock(g_mu);
  update_hysteresis(raw, unknown);
}

void letterbox_get_inset(int *top_px, int *bottom_px) {
  int v = 0;
  if (g_enabled.load() && !g_hard_disable.load()) {
    std::lock_guard<std::mutex> lock(g_mu);
    v = g_inset;
  }
  if (top_px)
    *top_px = v;
  if (bottom_px)
    *bottom_px = v;
}

int letterbox_map_y(float y_norm, int screen_h) {
  if (screen_h <= 0)
    return 0;
  if (y_norm < 0.f)
    y_norm = 0.f;
  if (y_norm > 1.f)
    y_norm = 1.f;
  int top = 0, bottom = 0;
  letterbox_get_inset(&top, &bottom);
  int content_h = screen_h - top - bottom;
  if (content_h < 1)
    content_h = 1;
  int y = top + (int)(y_norm * (float)content_h + 0.5f);
  if (y < 0)
    y = 0;
  if (y >= screen_h)
    y = screen_h - 1;
  return y;
}

void letterbox_map_y_range(float y0, float y1, int screen_h, int *out_y0,
                           int *out_y1) {
  int a = letterbox_map_y(y0, screen_h);
  int b = letterbox_map_y(y1, screen_h);
  // map_y 对 y1=1 会落到 content 底；保证至少 1px 高
  if (b <= a)
    b = a + 1;
  if (b > screen_h)
    b = screen_h;
  if (out_y0)
    *out_y0 = a;
  if (out_y1)
    *out_y1 = b;
}
