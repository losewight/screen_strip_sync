#include "subtitle_detect.h"

#include "letterbox_detect.h"
#include "pixel_reader.h"

#include <atomic>
#include <cstdio>
#include <mutex>

#include <dxgi.h>

namespace {

// 稳态 ~60ms/次：167≈10s 窗；全停后 (167-10)×60ms≈9.4s 关
constexpr int kWindow = 167;
constexpr int kOnHits = 56;
constexpr int kOffHits = 10;
// 只扫内容高底部 1/5
constexpr int kMaxScanFraction = 5;
constexpr int kBrightLuma = 160;
constexpr int kContrastSpan = 80;
constexpr int kContrastMaxMin = 140;
constexpr int kMinBandPx = 8;
constexpr int kPadPx = 4;
constexpr int kGapTol = 2;

std::atomic<bool> g_enabled{true};
std::atomic<bool> g_hard_disable{false};

std::mutex g_mu;
bool g_hit_ring[kWindow] = {};
int g_crop_ring[kWindow] = {};
int g_ring_pos = 0;
int g_ring_count = 0;
int g_hits = 0;
bool g_active = false;
int g_crop = 0; // 稳定输出

inline const unsigned char *px_at(const unsigned char *base, int stride,
                                  int bpp, int x, int y) {
  return base + (size_t)y * (size_t)stride + (size_t)x * (size_t)bpp;
}

inline unsigned luma601(unsigned r, unsigned g, unsigned b) {
  return (r * 299u + g * 587u + b * 114u) / 1000u;
}

template <typename Reader>
bool row_is_subtitle(const unsigned char *p, int w, int stride, int bpp,
                     int y) {
  const int xs[5] = {(w * 20) / 100, (w * 35) / 100, (w * 50) / 100,
                     (w * 65) / 100, (w * 80) / 100};
  int bright = 0;
  unsigned mn = 255, mx = 0;
  for (int i = 0; i < 5; ++i) {
    unsigned r = 0, g = 0, b = 0;
    Reader::read_rgb(px_at(p, stride, bpp, xs[i], y), &r, &g, &b);
    const unsigned L = luma601(r, g, b);
    if (L >= (unsigned)kBrightLuma)
      ++bright;
    if (L < mn)
      mn = L;
    if (L > mx)
      mx = L;
  }
  if (bright >= 2)
    return true;
  return (int)(mx - mn) >= kContrastSpan && (int)mx >= kContrastMaxMin;
}

template <typename Reader>
int detect_raw_crop(const unsigned char *p, int w, int h, int stride, int bpp) {
  int top = 0, bottom = 0;
  letterbox_get_inset(&top, &bottom);
  const int content_bottom = h - bottom - 1;
  const int content_h = h - top - bottom;
  if (content_h < 16 || content_bottom <= top)
    return 0;

  int scan_max = content_h / kMaxScanFraction;
  if (scan_max < kMinBandPx)
    scan_max = kMinBandPx;
  if (scan_max > content_h)
    scan_max = content_h;

  // 从内容底往上：找连续字幕带（允许 ≤kGapTol 行空隙）
  int band_from_bottom = 0;
  int gap = 0;
  bool seen = false;
  for (int d = 0; d < scan_max; ++d) {
    const int y = content_bottom - d;
    if (y < top)
      break;
    if (row_is_subtitle<Reader>(p, w, stride, bpp, y)) {
      seen = true;
      gap = 0;
      band_from_bottom = d + 1;
    } else if (seen) {
      ++gap;
      if (gap > kGapTol)
        break;
    }
  }

  if (band_from_bottom < kMinBandPx)
    return 0;
  int crop = band_from_bottom + kPadPx;
  if (crop > scan_max)
    crop = scan_max;
  return crop;
}

void clear_window_locked() {
  for (int i = 0; i < kWindow; ++i) {
    g_hit_ring[i] = false;
    g_crop_ring[i] = 0;
  }
  g_ring_pos = 0;
  g_ring_count = 0;
  g_hits = 0;
  g_active = false;
  g_crop = 0;
}

void push_sample_locked(int raw_crop) {
  const bool hit = raw_crop > 0;
  if (g_ring_count == kWindow) {
    if (g_hit_ring[g_ring_pos])
      --g_hits;
  } else {
    ++g_ring_count;
  }
  g_hit_ring[g_ring_pos] = hit;
  g_crop_ring[g_ring_pos] = raw_crop;
  if (hit)
    ++g_hits;
  g_ring_pos = (g_ring_pos + 1) % kWindow;

  const bool was = g_active;
  const int old_crop = g_crop;
  if (!g_active) {
    if (g_hits >= kOnHits)
      g_active = true;
  } else {
    if (g_hits <= kOffHits) {
      g_active = false;
      g_crop = 0;
    }
  }

  if (g_active) {
    int mx = 0;
    for (int i = 0; i < g_ring_count; ++i) {
      // 环内已占槽：从 pos 往回 ring_count 个
      const int idx =
          (g_ring_pos - 1 - i + kWindow * 2) % kWindow;
      if (g_hit_ring[idx] && g_crop_ring[idx] > mx)
        mx = g_crop_ring[idx];
    }
    if (mx > 0)
      g_crop = mx;
    // 无 hit 时保持上一 crop（直到 Off）
  }

  if (was != g_active || old_crop != g_crop)
    printf("subtitle crop=%d hits=%d/%d active=%d\n", g_crop, g_hits,
           g_ring_count, g_active ? 1 : 0);
}

} // namespace

void subtitle_set_enabled(bool on) {
  const bool prev = g_enabled.exchange(on);
  if (prev == on)
    return;
  printf("subtitle enable=%d\n", on ? 1 : 0);
  if (!on) {
    std::lock_guard<std::mutex> lock(g_mu);
    clear_window_locked();
    printf("subtitle crop=0 hits=0/%d active=0\n", 0);
  }
}

void subtitle_set_hard_disable(bool on) {
  const bool prev = g_hard_disable.exchange(on);
  if (prev != on)
    printf("subtitle hard_disable=%d\n", on ? 1 : 0);
  std::lock_guard<std::mutex> lock(g_mu);
  clear_window_locked();
}

void subtitle_reset() {
  std::lock_guard<std::mutex> lock(g_mu);
  clear_window_locked();
  printf("subtitle crop=0 (reset)\n");
}

void subtitle_process(const unsigned char *pixels, int width, int height,
                      int stride, int bpp, unsigned format) {
  if (!pixels || width < 8 || height < 8 || bpp < 4)
    return;
  if (!g_enabled.load() || g_hard_disable.load()) {
    std::lock_guard<std::mutex> lock(g_mu);
    g_crop = 0;
    g_active = false;
    return;
  }

  int raw = 0;
  if (format == (unsigned)DXGI_FORMAT_B8G8R8A8_UNORM) {
    raw = detect_raw_crop<BgraReader>(pixels, width, height, stride, bpp);
  } else if (format == (unsigned)DXGI_FORMAT_R16G16B16A16_FLOAT) {
    raw = detect_raw_crop<Fp16Reader>(pixels, width, height, stride, bpp);
  } else {
    return;
  }

  std::lock_guard<std::mutex> lock(g_mu);
  push_sample_locked(raw);
}

void subtitle_get_bottom_crop(int *crop_px) {
  int v = 0;
  if (g_enabled.load() && !g_hard_disable.load()) {
    std::lock_guard<std::mutex> lock(g_mu);
    if (g_active)
      v = g_crop;
  }
  if (crop_px)
    *crop_px = v;
}
