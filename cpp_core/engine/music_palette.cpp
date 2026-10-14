#include "music_palette.h"

#include <cmath>
#include <cstring>

namespace {

// HSV→RGB；S=V=1 时已满饱和，再按 max 通道拉到 255
void hsv_sv1_rgb(float hue_deg, unsigned char *r, unsigned char *g,
                 unsigned char *b) {
  float h = hue_deg;
  while (h < 0.f)
    h += 360.f;
  while (h >= 360.f)
    h -= 360.f;
  const float c = 1.f;
  const float x = c * (1.f - std::fabs(std::fmod(h / 60.f, 2.f) - 1.f));
  float rf = 0.f, gf = 0.f, bf = 0.f;
  if (h < 60.f) {
    rf = c;
    gf = x;
  } else if (h < 120.f) {
    rf = x;
    gf = c;
  } else if (h < 180.f) {
    rf = 0.f;
    gf = c;
    bf = x;
  } else if (h < 240.f) {
    rf = 0.f;
    gf = x;
    bf = c;
  } else if (h < 300.f) {
    rf = x;
    gf = 0.f;
    bf = c;
  } else {
    rf = c;
    gf = 0.f;
    bf = x;
  }
  float mx = rf;
  if (gf > mx)
    mx = gf;
  if (bf > mx)
    mx = bf;
  if (mx <= 0.f) {
    *r = *g = *b = 0;
    return;
  }
  const float scale = 255.f / mx;
  *r = (unsigned char)(rf * scale + 0.5f);
  *g = (unsigned char)(gf * scale + 0.5f);
  *b = (unsigned char)(bf * scale + 0.5f);
}

void clamp01(float *v) {
  if (*v < 0.f)
    *v = 0.f;
  if (*v > 1.f)
    *v = 1.f;
}

bool screen_is_off(const unsigned char *rgb) {
  return !rgb || (rgb[0] == 0 && rgb[1] == 0 && rgb[2] == 0);
}

} // namespace

bool music_palette_normalize_rgb(const unsigned char in[3],
                                 unsigned char out[3]) {
  if (!in || !out)
    return false;
  const unsigned mx =
      in[0] > in[1] ? (in[0] > in[2] ? in[0] : in[2])
                    : (in[1] > in[2] ? in[1] : in[2]);
  if (mx == 0)
    return false;
  out[0] = (unsigned char)((in[0] * 255u + mx / 2u) / mx);
  out[1] = (unsigned char)((in[1] * 255u + mx / 2u) / mx);
  out[2] = (unsigned char)((in[2] * 255u + mx / 2u) / mx);
  return true;
}

void music_palette_color(MusicPalette p, float t, float level, unsigned now_ms,
                         const unsigned char fixed[3],
                         const unsigned char *screen_rgb,
                         unsigned char out[3]) {
  if (!out)
    return;
  clamp01(&t);
  clamp01(&level);

  switch (p) {
  case MusicPalette::Vu:
    // 绿(120°) → 红(0°)
    hsv_sv1_rgb(120.f * (1.f - t), &out[0], &out[1], &out[2]);
    return;
  case MusicPalette::Rainbow: {
    // base 每秒转 36°（10s 一圈）；hue = base + t * 300°
    const float base =
        std::fmod((float)now_ms * (36.f / 1000.f), 360.f);
    hsv_sv1_rgb(base + t * 300.f, &out[0], &out[1], &out[2]);
    return;
  }
  case MusicPalette::Fixed:
    if (fixed) {
      out[0] = fixed[0];
      out[1] = fixed[1];
      out[2] = fixed[2];
    } else {
      out[0] = out[1] = out[2] = 0;
    }
    return;
  case MusicPalette::Level:
    // 蓝(240°) → 红(0°) 随 level
    hsv_sv1_rgb(240.f * (1.f - level), &out[0], &out[1], &out[2]);
    return;
  case MusicPalette::Screen:
    if (screen_is_off(screen_rgb)) {
      hsv_sv1_rgb(120.f * (1.f - t), &out[0], &out[1], &out[2]);
    } else {
      out[0] = screen_rgb[0];
      out[1] = screen_rgb[1];
      out[2] = screen_rgb[2];
    }
    return;
  }
  out[0] = out[1] = out[2] = 0;
}
