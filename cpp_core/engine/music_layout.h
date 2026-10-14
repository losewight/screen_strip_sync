#pragma once

#include "segment_map.h"

// 音乐段序：若干 bar + rest 段；P1 只实现 linear（一条 bar 占满 10 段）。

struct MusicBar {
  int seg[kSegmentCount];
  int len;
};

struct MusicLayout {
  MusicBar bars[2];
  int bar_count;
  bool rest[kSegmentCount];
};

// 一条 bar：0..9 或 9..0；rest 全 false
void music_layout_linear(bool reverse, MusicLayout *out);
