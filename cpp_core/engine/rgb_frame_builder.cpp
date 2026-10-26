#include "rgb_frame_builder.h"

#include <atomic>
#include <cstdio>
#include <cstring>

static std::atomic<int> g_device_step{2};

int engine_get_device_step() {
  return g_device_step.load(std::memory_order_relaxed);
}

void engine_set_device_step(int step) {
  if (is_valid_strip_length(step)) {
    g_device_step.store(step, std::memory_order_relaxed);
  }
}

bool is_valid_strip_length(int meters) {
  return meters >= 2 && meters <= 5;
}

int parse_strip_length(const char *buf) {
  if (!buf)
    return 0;

  // 1. 优先匹配设备推送状态：rep_length N
  const char *rep = strstr(buf, "rep_length");
  if (rep) {
    int v = 0;
    if (sscanf(rep, "rep_length %d", &v) == 1) {
      if (is_valid_strip_length(v))
        return v;
    }
  }

  // 2. 逐行匹配响应中的数字（2, 3, 4）
  const char *p = buf;
  while (*p) {
    while (*p == ' ' || *p == '\r' || *p == '\n')
      p++;
    if (!*p)
      break;

    int val = 0;
    if (sscanf(p, "%d", &val) == 1 && is_valid_strip_length(val)) {
      // 确认数字之后紧跟的是分隔符或结尾（防多位数字如 20、40）
      const char *num_end = p;
      while (*num_end >= '0' && *num_end <= '9')
        num_end++;
      if (*num_end == '\r' || *num_end == '\n' || *num_end == ' ' ||
          *num_end == '\0') {
        return val;
      }
    }

    // 移动到下一行
    while (*p && *p != '\n')
      p++;
  }
  return 0;
}

template <typename ColorGetter>
static bool build_rgb_pc_frame_internal(unsigned frame_id, unsigned brightness,
                                        ColorGetter get_color, int step,
                                        char *out_frame, size_t out_cap) {
  if (!out_frame || out_cap < 120) {
    return false;
  }

  const int eff_step = (step > 0) ? step : engine_get_device_step();
  if (!is_valid_strip_length(eff_step)) {
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
