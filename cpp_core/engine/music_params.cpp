#include "music_params.h"

#include <atomic>

// 为什么：发帧热路径只 load；IPC / 配置经 setter 写入，不进 engine_params 竞态区
static std::atomic<MusicSource> g_src{MusicSource::System};
static std::atomic<char> g_layout{'l'};
static std::atomic<bool> g_reverse{false};
static std::atomic<int> g_sensitivity{50};
static std::atomic<int> g_decay{50};
static std::atomic<char> g_silence{'o'};

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
