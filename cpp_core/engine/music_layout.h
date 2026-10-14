#pragma once

#include "segment_map.h"

// 音乐段序：若干 bar + rest 段。

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

// 双条镜像：ends = {l0,l1,r0,r1}（0..9）。左条 l0→l1、右条 r0→r1（含两端）；
// 段集合不相交才合法；其余段落 rest[]。非法返回 false（*out 未定义）。
bool music_layout_mirror(const int ends[4], MusicLayout *out);
