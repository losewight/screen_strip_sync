#include "music_level.h"

#include <cmath>

// 电平纯函数；另一 agent 可替换实现，接线侧按此 API 调用。

namespace {

constexpr float kSilenceDb = -70.f;
constexpr float kNormLoDb = -50.f;
constexpr float kNormHiDb = -10.f;

float lin_to_dbfs(float amp) {
  if (amp <= 1e-10f)
    return -200.f;
  return 20.f * log10f(amp);
}

float clamp01(float v) {
  if (v < 0.f)
    return 0.f;
  if (v > 1.f)
    return 1.f;
  return v;
}

} // namespace

float music_level_step(MusicLevelState *s, float rms, float peak,
                       int sensitivity, int decay) {
  if (!s)
    return 0.f;
  if (sensitivity < 0)
    sensitivity = 0;
  if (sensitivity > 100)
    sensitivity = 100;
  if (decay < 0)
    decay = 0;
  if (decay > 100)
    decay = 100;

  const float amp = rms * 1.41f > peak * 0.8f ? rms * 1.41f : peak * 0.8f;
  float db = lin_to_dbfs(amp);
  if (db < kSilenceDb) {
    // 静音：按回落速率落到 0
    const float max_drop = 0.03f + (float)decay * 0.0027f;
    s->level = s->level > max_drop ? s->level - max_drop : 0.f;
    return s->level;
  }

  const float gain_db = (float)(sensitivity - 50) * 0.6f;
  db += gain_db;
  float target = (db - kNormLoDb) / (kNormHiDb - kNormLoDb);
  target = clamp01(target);

  if (target >= s->level) {
    s->level = target; // 起音即时
  } else {
    const float max_drop = 0.03f + (float)decay * 0.0027f;
    const float next = s->level - max_drop;
    s->level = next > target ? next : target;
  }
  return s->level;
}

int music_lit_count(MusicLevelState *s, float level, int bar_len,
                    bool keep_min) {
  if (!s || bar_len <= 0)
    return 0;
  level = clamp01(level);
  const float x = level * (float)bar_len;
  int lit = s->lit;
  if (lit < 0)
    lit = 0;
  if (lit > bar_len)
    lit = bar_len;
  // 为什么：用「下一整数±0.3」门槛，避免 lit=(int)exact 在 5.3~5.9 卡死升不了档
  while (lit < bar_len && x >= (float)(lit + 1) - 0.3f)
    ++lit;
  while (lit > 0 && x < (float)lit - 0.3f)
    --lit;
  if (keep_min && lit < 1)
    lit = 1;
  s->lit = lit;
  return lit;
}

int music_rest_fill_kind(MusicLevelState *s, float level, char rest_mode) {
  if (rest_mode == 'b' || rest_mode == 'B')
    return 2;
  if (rest_mode == 'p' || rest_mode == 'P') {
    if (!s)
      return 0;
    if (level >= 0.95f)
      s->peak_hold = 3;
    if (s->peak_hold <= 0)
      return 0;
    --s->peak_hold;
    return 1;
  }
  return 0;
}
