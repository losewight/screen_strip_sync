#include "music_params.h"

#include <atomic>
#include <cstdio>
#include <cstring>

// 为什么：发帧热路径只 load；IPC / 配置经 setter 写入，不进 engine_params 竞态区
static std::atomic<MusicSource> g_src{MusicSource::System};
static std::atomic<char> g_layout{'l'};
static std::atomic<bool> g_reverse{false};
static std::atomic<int> g_sensitivity{50};
static std::atomic<int> g_decay{50};
static std::atomic<char> g_silence{'o'};
static std::atomic<int> g_mirror0{-1};
static std::atomic<int> g_mirror1{-1};
static std::atomic<int> g_mirror2{-1};
static std::atomic<int> g_mirror3{-1};
static std::atomic<char> g_rest{'o'};
static std::atomic<char> g_palette{'v'};
static std::atomic<unsigned char> g_color_r{0x00};
static std::atomic<unsigned char> g_color_g{0xaa};
static std::atomic<unsigned char> g_color_b{0xff};

static char palette_to_char(MusicPalette p) {
  switch (p) {
  case MusicPalette::Rainbow:
    return 'r';
  case MusicPalette::Fixed:
    return 'f';
  case MusicPalette::Level:
    return 'l';
  case MusicPalette::Screen:
    return 's';
  case MusicPalette::Vu:
  default:
    return 'v';
  }
}

static MusicPalette palette_from_char(char c) {
  if (c == 'r' || c == 'R')
    return MusicPalette::Rainbow;
  if (c == 'f' || c == 'F')
    return MusicPalette::Fixed;
  if (c == 'l' || c == 'L')
    return MusicPalette::Level;
  if (c == 's' || c == 'S')
    return MusicPalette::Screen;
  return MusicPalette::Vu;
}

void music_set_source(MusicSource src) { g_src.store(src); }

MusicSource music_get_source() { return g_src.load(); }

void music_set_layout_linear_or_mirror(char layout) {
  g_layout.store((layout == 'm' || layout == 'M') ? 'm' : 'l');
}

char music_get_layout() { return g_layout.load(); }

void music_set_reverse(bool reverse) { g_reverse.store(reverse); }

bool music_get_reverse() { return g_reverse.load(); }

void music_set_sensitivity(int v) {
  if (v < 0)
    v = 0;
  if (v > 100)
    v = 100;
  g_sensitivity.store(v);
}

int music_get_sensitivity() { return g_sensitivity.load(); }

void music_set_decay(int v) {
  if (v < 0)
    v = 0;
  if (v > 100)
    v = 100;
  g_decay.store(v);
}

int music_get_decay() { return g_decay.load(); }

void music_set_silence(char mode) {
  g_silence.store((mode == 'm' || mode == 'M') ? 'm' : 'o');
}

char music_get_silence() { return g_silence.load(); }

void music_set_mirror(const int ends[4]) {
  if (!ends)
    return;
  g_mirror0.store(ends[0]);
  g_mirror1.store(ends[1]);
  g_mirror2.store(ends[2]);
  g_mirror3.store(ends[3]);
}

void music_clear_mirror() {
  g_mirror0.store(-1);
  g_mirror1.store(-1);
  g_mirror2.store(-1);
  g_mirror3.store(-1);
}

void music_get_mirror(int out[4]) {
  if (!out)
    return;
  out[0] = g_mirror0.load();
  out[1] = g_mirror1.load();
  out[2] = g_mirror2.load();
  out[3] = g_mirror3.load();
}

void music_set_rest(char mode) {
  if (mode == 'p' || mode == 'P')
    g_rest.store('p');
  else if (mode == 'b' || mode == 'B')
    g_rest.store('b');
  else
    g_rest.store('o');
}

char music_get_rest() { return g_rest.load(); }

void music_set_palette(MusicPalette p) {
  g_palette.store(palette_to_char(p));
}

void music_set_palette(char c) { g_palette.store(palette_to_char(palette_from_char(c))); }

bool music_set_palette_word(const char *word) {
  if (!word)
    return false;
  while (*word == ' ' || *word == '\t')
    ++word;
  if (strcmp(word, "vu") == 0)
    music_set_palette(MusicPalette::Vu);
  else if (strcmp(word, "rainbow") == 0)
    music_set_palette(MusicPalette::Rainbow);
  else if (strcmp(word, "fixed") == 0)
    music_set_palette(MusicPalette::Fixed);
  else if (strcmp(word, "level") == 0)
    music_set_palette(MusicPalette::Level);
  else if (strcmp(word, "screen") == 0)
    music_set_palette(MusicPalette::Screen);
  else
    return false;
  return true;
}

char music_get_palette() { return g_palette.load(); }

MusicPalette music_get_palette_enum() {
  return palette_from_char(g_palette.load());
}

bool music_set_color(const char *rrggbb) {
  if (!rrggbb)
    return false;
  while (*rrggbb == ' ' || *rrggbb == '\t')
    ++rrggbb;
  if (strlen(rrggbb) != 6)
    return false;
  unsigned char raw[3] = {};
  for (int c = 0; c < 3; ++c) {
    unsigned v = 0;
    for (int k = 0; k < 2; ++k) {
      char ch = rrggbb[c * 2 + k];
      unsigned nibble = 0;
      if (ch >= '0' && ch <= '9')
        nibble = (unsigned)(ch - '0');
      else if (ch >= 'a' && ch <= 'f')
        nibble = (unsigned)(ch - 'a' + 10);
      else if (ch >= 'A' && ch <= 'F')
        nibble = (unsigned)(ch - 'A' + 10);
      else
        return false;
      v = (v << 4) | nibble;
    }
    raw[c] = (unsigned char)v;
  }
  unsigned char norm[3] = {};
  if (!music_palette_normalize_rgb(raw, norm))
    return false;
  g_color_r.store(norm[0]);
  g_color_g.store(norm[1]);
  g_color_b.store(norm[2]);
  return true;
}

void music_get_color(unsigned char out[3]) {
  if (!out)
    return;
  out[0] = g_color_r.load();
  out[1] = g_color_g.load();
  out[2] = g_color_b.load();
}

void music_get_color_hex(char out[7]) {
  if (!out)
    return;
  snprintf(out, 7, "%02x%02x%02x", g_color_r.load(), g_color_g.load(),
           g_color_b.load());
}
