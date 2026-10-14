#include "music_frame.h"

#include "audio_capture.h"
#include "music_layout.h"
#include "music_level.h"
#include "music_params.h"

#include <cmath>
#include <cstdio>
#include <cstring>

namespace {

MusicLevelState g_level_state{};

// HSV→RGB；S=V=1 时已满饱和，再按 max 通道拉到 255（与规格一致）
void hsv_vu_rgb(float hue_deg, unsigned char *r, unsigned char *g,
                unsigned char *b) {
  float h = hue_deg;
  if (h < 0.f)
    h = 0.f;
  if (h > 360.f)
    h = 360.f;
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

} // namespace

DxgiErr produce_colors_music(int frame_index, char *out_frame, size_t out_cap) {
  if (out_frame == nullptr || out_cap == 0)
    return DxgiErr::AcquireFailed;

  float rms = 0.f, peak = 0.f;
  audio_take_window(&rms, &peak);

  const float level =
      music_level_step(&g_level_state, rms, peak, music_get_sensitivity(),
                       music_get_decay());
  const bool keep_min = music_get_silence() == 'm';

  // P1：mirror 回退为 linear
  MusicLayout layout{};
  music_layout_linear(music_get_reverse(), &layout);

  unsigned char rgb[kSegmentCount][3] = {};
  for (int bi = 0; bi < layout.bar_count; ++bi) {
    const MusicBar &bar = layout.bars[bi];
    if (bar.len <= 0)
      continue;
    const int lit =
        music_lit_count(&g_level_state, level, bar.len, keep_min);
    for (int k = 0; k < bar.len; ++k) {
      const int seg = bar.seg[k];
      if (seg < 0 || seg >= kSegmentCount)
        continue;
      if (k < lit) {
        const float t =
            (bar.len <= 1) ? 0.f : (float)k / (float)(bar.len - 1);
        // 绿(120°) → 红(0°)
        hsv_vu_rgb(120.f * (1.f - t), &rgb[seg][0], &rgb[seg][1],
                   &rgb[seg][2]);
      }
      // 未点亮保持 000000
    }
  }

  char colors[kSegmentCount][7] = {};
  for (int i = 0; i < kSegmentCount; ++i)
    snprintf(colors[i], sizeof(colors[i]), "%02x%02x%02x", rgb[i][0],
             rgb[i][1], rgb[i][2]);

  const unsigned frame_id = (unsigned)frame_index & 0xFFFFu;
  snprintf(out_frame, out_cap,
           "set_rgb_pc %04x 00 63 "
           "%s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           frame_id, colors[0], colors[1], colors[2], colors[3], colors[4],
           colors[5], colors[6], colors[7], colors[8], colors[9]);

  if (strlen(out_frame) >= 120)
    return DxgiErr::AcquireFailed;
  return DxgiErr::Ok;
}
