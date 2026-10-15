#include "music_frame.h"

#include "audio_capture.h"
#include "dxgi_capture.h"
#include "light_engine.h"
#include "music_layout.h"
#include "music_level.h"
#include "music_palette.h"
#include "music_params.h"
#include "segment_map.h"

#include <cstdio>
#include <cstring>
#include <windows.h>

namespace {

MusicLevelState g_level_state{};

// Screen 配色：超时沿用上一帧，避免静止画面跳帧熄灯
unsigned char g_last_screen[kSegmentCount][3] = {};
bool g_have_screen = false;

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

  MusicLayout layout{};
  if (music_get_layout() == 'm') {
    int ends[4];
    music_get_mirror(ends);
    if (!music_layout_mirror(ends, &layout)) {
      helper_log_rate("music_mirror_fallback", 5000,
                      "music layout=mirror but ends invalid; fallback linear\n");
      music_layout_linear(music_get_reverse(), &layout);
    }
  } else {
    music_layout_linear(music_get_reverse(), &layout);
  }

  const MusicPalette palette = music_get_palette_enum();
  unsigned char fixed[3] = {};
  music_get_color(fixed);
  const unsigned now_ms = (unsigned)GetTickCount();

  // Screen：确保 DXGI；AccessLost 交 frame_loop；超时复用上一帧色
  const unsigned char (*screen_rows)[3] = nullptr;
  if (palette == MusicPalette::Screen) {
    if (!dxgi_is_ready()) {
      if (!engine_ensure_dxgi()) {
        helper_log_rate("music_screen_dxgi", 5000,
                        "music Screen: dxgi not ready; Vu fallback this frame\n");
      }
    }
    if (dxgi_is_ready()) {
      unsigned char fresh[kSegmentCount][3] = {};
      DxgiErr se = map_sample_step(5, fresh);
      if (se == DxgiErr::AccessLost || se == DxgiErr::DuplicateFailed)
        return se;
      if (se == DxgiErr::Ok) {
        memcpy(g_last_screen, fresh, sizeof(g_last_screen));
        g_have_screen = true;
      }
      // AcquireTimeout / 其它：沿用 g_last_screen（若有）
      if (g_have_screen)
        screen_rows = g_last_screen;
    }
  }

  unsigned char rgb[kSegmentCount][3] = {};
  for (int bi = 0; bi < layout.bar_count; ++bi) {
    const MusicBar &bar = layout.bars[bi];
    if (bar.len <= 0)
      continue;
    int lit = 0;
    if (layout.bar_count == 1) {
      lit = music_lit_count(&g_level_state, level, bar.len, keep_min);
    } else {
      MusicLevelState slot{};
      slot.level = g_level_state.level;
      slot.lit = (bi >= 0 && bi < 2) ? g_level_state.lit_bars[bi] : 0;
      lit = music_lit_count(&slot, level, bar.len, keep_min);
      if (bi >= 0 && bi < 2)
        g_level_state.lit_bars[bi] = slot.lit;
    }
    for (int k = 0; k < bar.len; ++k) {
      const int seg = bar.seg[k];
      if (seg < 0 || seg >= kSegmentCount)
        continue;
      if (k < lit) {
        const float t =
            (bar.len <= 1) ? 0.f : (float)k / (float)(bar.len - 1);
        const unsigned char *scr =
            screen_rows ? screen_rows[seg] : nullptr;
        music_palette_color(palette, t, level, now_ms, fixed, scr,
                            rgb[seg]);
      }
      // 未点亮保持 000000
    }
  }

  const int rest_kind =
      music_rest_fill_kind(&g_level_state, level, music_get_rest());
  if (rest_kind != 0) {
    // peak=t1 / base=t0；Screen 按段取屏色，灭则回退 Vu
    const float t_rest = (rest_kind == 1) ? 1.f : 0.f;
    for (int i = 0; i < kSegmentCount; ++i) {
      if (!layout.rest[i])
        continue;
      const unsigned char *scr = screen_rows ? screen_rows[i] : nullptr;
      music_palette_color(palette, t_rest, level, now_ms, fixed, scr,
                          rgb[i]);
    }
  }

  char colors[kSegmentCount][7] = {};
  bool any_lit = false;
  for (int i = 0; i < kSegmentCount; ++i) {
    snprintf(colors[i], sizeof(colors[i]), "%02x%02x%02x", rgb[i][0],
             rgb[i][1], rgb[i][2]);
    if (rgb[i][0] | rgb[i][1] | rgb[i][2])
      any_lit = true;
  }

  // 音乐模式：有段点亮时 BRT 随 level 单调亮→暗；全灭时保持 63（与今日黑帧一致）。
  // 不做 63↔L 交替、不做鼓点 pulse。floor=0x14（~20%）保证低电平仍可读。
  constexpr unsigned kMusicBrtFloor = 0x14;
  constexpr unsigned kMusicBrtCeil = 0x63;
  unsigned brt = kMusicBrtCeil;
  if (any_lit) {
    float lv = level;
    if (lv < 0.f)
      lv = 0.f;
    if (lv > 1.f)
      lv = 1.f;
    brt = kMusicBrtFloor +
          (unsigned)((kMusicBrtCeil - kMusicBrtFloor) * lv + 0.5f);
    if (brt > kMusicBrtCeil)
      brt = kMusicBrtCeil;
  }

  const unsigned frame_id = (unsigned)frame_index & 0xFFFFu;
  snprintf(out_frame, out_cap,
           "set_rgb_pc %04x 00 %02x "
           "%s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           frame_id, brt, colors[0], colors[1], colors[2], colors[3],
           colors[4], colors[5], colors[6], colors[7], colors[8],
           colors[9]);

  if (strlen(out_frame) >= 120)
    return DxgiErr::AcquireFailed;
  return DxgiErr::Ok;
}
