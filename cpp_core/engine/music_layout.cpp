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

static bool fill_bar(int a, int b, MusicBar *bar, bool used[kSegmentCount]) {
  if (!bar || a < 0 || a >= kSegmentCount || b < 0 || b >= kSegmentCount)
    return false;
  bar->len = 0;
  if (a <= b) {
    for (int i = a; i <= b; ++i) {
      if (used[i])
        return false;
      used[i] = true;
      bar->seg[bar->len++] = i;
    }
  } else {
    for (int i = a; i >= b; --i) {
      if (used[i])
        return false;
      used[i] = true;
      bar->seg[bar->len++] = i;
    }
  }
  return bar->len > 0;
}

bool music_layout_mirror(const int ends[4], MusicLayout *out) {
  if (!ends || !out)
    return false;
  for (int i = 0; i < 4; ++i) {
    if (ends[i] < 0 || ends[i] >= kSegmentCount)
      return false;
  }

  MusicLayout lay{};
  bool used[kSegmentCount] = {};
  if (!fill_bar(ends[0], ends[1], &lay.bars[0], used))
    return false;
  if (!fill_bar(ends[2], ends[3], &lay.bars[1], used))
    return false;
  lay.bar_count = 2;
  for (int i = 0; i < kSegmentCount; ++i)
    lay.rest[i] = !used[i];
  *out = lay;
  return true;
}
