#include "rgb_frame_builder.h"

#include <atomic>
#include <cstdio>
#include <cstring>

static std::atomic<int> g_device_step{2};

int engine_get_device_step() {
  return g_device_step.load(std::memory_order_relaxed);
}

void engine_set_device_step(int step) {
  if (step >= 1 && step <= 9) {
    g_device_step.store(step, std::memory_order_relaxed);
  }
}

template <typename ColorGetter>
static bool build_rgb_pc_frame_internal(unsigned frame_id, unsigned brightness,
                                        ColorGetter get_color, int step,
                                        char *out_frame, size_t out_cap) {
  if (!out_frame || out_cap < 120) {
    return false;
  }

  const int eff_step = (step > 0) ? step : engine_get_device_step();
  if (eff_step < 1 || eff_step > 9) {
    out_frame[0] = '\0';
    return false;
  }

  const unsigned eff_id = frame_id & 0xFFFFu;
  const unsigned eff_brt = brightness & 0xFFu;

  // 帧头：set_rgb_pc %04x 00 %02x
  int written = snprintf(out_frame, out_cap, "set_rgb_pc %04x 00 %02x", eff_id,
                         eff_brt);
  if (written < 0 || (size_t)written >= out_cap) {
    out_frame[0] = '\0';
    return false;
  }

  // 10 段色彩与步进
  for (int i = 0; i < kSegmentCount; ++i) {
    const char *col = get_color(i);
    if (!col || strlen(col) != 6) {
      out_frame[0] = '\0';
      return false;
    }
    const int seg_n = snprintf(out_frame + written, out_cap - (size_t)written,
                               " %s %d", col, eff_step);
    if (seg_n < 0 || (size_t)(written + seg_n) >= out_cap) {
      out_frame[0] = '\0';
      return false;
    }
    written += seg_n;
  }

  // 帧尾：\r\n\0
  if (out_cap - (size_t)written < 3) {
    out_frame[0] = '\0';
    return false;
  }
  out_frame[written++] = '\r';
  out_frame[written++] = '\n';
  out_frame[written] = '\0';

  // 生产红线：帧长含 \r\n 必须严格 < 120 字节（距单片机 128 字节崩溃线留足余量）
  if (written >= 120) {
    out_frame[0] = '\0';
    return false;
  }

  return true;
}

bool build_rgb_pc_frame(unsigned frame_id, unsigned brightness,
                        const char colors[kSegmentCount][7], int step,
                        char *out_frame, size_t out_cap) {
  return build_rgb_pc_frame_internal(
      frame_id, brightness, [&colors](int i) { return colors[i]; }, step,
      out_frame, out_cap);
}

bool build_rgb_pc_frame(unsigned frame_id, unsigned brightness,
                        const char *const colors[kSegmentCount], int step,
                        char *out_frame, size_t out_cap) {
  if (!colors) {
    if (out_frame && out_cap > 0)
      out_frame[0] = '\0';
    return false;
  }
  return build_rgb_pc_frame_internal(
      frame_id, brightness, [colors](int i) { return colors[i]; }, step,
      out_frame, out_cap);
}

bool build_rgb_pc_solid_frame(unsigned frame_id, unsigned brightness,
                              const char *color_hex, int step,
                              char *out_frame, size_t out_cap) {
  if (!color_hex || strlen(color_hex) != 6) {
    if (out_frame && out_cap > 0)
      out_frame[0] = '\0';
    return false;
  }
  return build_rgb_pc_frame_internal(
      frame_id, brightness, [color_hex](int /*i*/) { return color_hex; }, step,
      out_frame, out_cap);
}
