#include "music_layout.h"

void music_layout_linear(bool reverse, MusicLayout *out) {
  if (!out)
    return;
  *out = MusicLayout{};
  out->bar_count = 1;
  out->bars[0].len = kSegmentCount;
  for (int i = 0; i < kSegmentCount; ++i) {
    out->bars[0].seg[i] = reverse ? (kSegmentCount - 1 - i) : i;
    out->rest[i] = false;
  }
}
