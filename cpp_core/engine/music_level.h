#pragma once

// 音乐电平纯函数：不依赖 Windows API，可离线单测。

struct MusicLevelState {
  float level = 0.f;
  int lit = 0;          // 单条 bar（linear）迟滞
  int lit_bars[2] = {}; // 双条镜像各自迟滞
  int peak_hold = 0;    // rest=peak 保留帧数
};

// rms/peak 线性幅度；sensitivity/decay 0..100；返回 0..1 平滑电平
float music_level_step(MusicLevelState *s, float rms, float peak,
                       int sensitivity, int decay);

// 电平 -> 点亮格数，带 0.3 格迟滞避免两档间抖动
int music_lit_count(MusicLevelState *s, float level, int bar_len, bool keep_min);

// rest_mode: 'o'=off | 'p'=peak | 'b'=base。
// 返回 0=灭 / 1=用终点色（peak）/ 2=用起点色（base）。'p' 时维护 peak_hold。
int music_rest_fill_kind(MusicLevelState *s, float level, char rest_mode);
