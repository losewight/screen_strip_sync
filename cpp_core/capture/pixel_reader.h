#pragma once

#include "hdr_convert.h"

#include <cstdint>

// map / region / letterbox 共用像素读取器；按类型模板展开，热路径无格式分支。

struct BgraReader {
  static constexpr int kBpp = 4;

  static void read_rgb(const unsigned char *px, unsigned *r, unsigned *g,
                       unsigned *b) {
    *b = px[0];
    *g = px[1];
    *r = px[2];
  }

  // letterbox：与历史 is_black_bgra 同口径（每通道 < thr）
  static bool is_near_black(const unsigned char *px, int thr) {
    return px[2] < (unsigned)thr && px[1] < (unsigned)thr &&
           px[0] < (unsigned)thr;
  }
};

struct Fp16Reader {
  static constexpr int kBpp = 8;

  static void read_rgb(const unsigned char *px, unsigned *r, unsigned *g,
                       unsigned *b) {
    std::uint8_t rgb[3];
    hdr_px_to_rgb8(reinterpret_cast<const std::uint16_t *>(px), rgb);
    *r = rgb[0];
    *g = rgb[1];
    *b = rgb[2];
  }

  static bool is_near_black(const unsigned char *px, int thr) {
    unsigned r = 0, g = 0, b = 0;
    read_rgb(px, &r, &g, &b);
    return r < (unsigned)thr && g < (unsigned)thr && b < (unsigned)thr;
  }
};
