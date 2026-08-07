#include "wall_comp.h"

#include <atomic>
#include <cstring>

// 为什么：IPC/配置写、发帧读；热路径只 load
static std::atomic<bool> g_wall_comp_on{false};
static std::atomic<bool> g_wall_color_set{false};
static std::atomic<float> g_wall_ref_r{1.f};
static std::atomic<float> g_wall_ref_g{1.f};
static std::atomic<float> g_wall_ref_b{1.f};

// 近黑通道防除零；1/255 ≈ 单级反射率
static constexpr float kRefEps = 1.f / 255.f;

void engine_set_wall_comp(bool on) { g_wall_comp_on.store(on); }

void engine_clear_wall_color() {
  g_wall_color_set.store(false);
  g_wall_ref_r.store(1.f);
  g_wall_ref_g.store(1.f);
  g_wall_ref_b.store(1.f);
}

bool engine_set_wall_color(const char *rrggbb) {
  if (!rrggbb)
    return false;
  while (*rrggbb == ' ' || *rrggbb == '\t')
    ++rrggbb;
  if (rrggbb[0] == '\0') {
    engine_clear_wall_color();
    return true;
  }
  if (strlen(rrggbb) != 6)
    return false;
  unsigned rgb[3] = {};
  for (int c = 0; c < 3; ++c) {
    unsigned v = 0;
    for (int k = 0; k < 2; ++k) {
      char ch = rrggbb[c * 2 + k];
      unsigned d = 0;
      if (ch >= '0' && ch <= '9')
        d = (unsigned)(ch - '0');
      else if (ch >= 'a' && ch <= 'f')
        d = (unsigned)(ch - 'a' + 10);
      else if (ch >= 'A' && ch <= 'F')
        d = (unsigned)(ch - 'A' + 10);
      else
        return false;
      v = (v << 4) | d;
    }
    rgb[c] = v;
  }
  auto ref = [](unsigned w) -> float {
    float r = (float)w / 255.f;
    return r < kRefEps ? kRefEps : r;
  };
  g_wall_ref_r.store(ref(rgb[0]));
  g_wall_ref_g.store(ref(rgb[1]));
  g_wall_ref_b.store(ref(rgb[2]));
  g_wall_color_set.store(true);
  return true;
}

void wall_comp_apply(float *r, float *g, float *b) {
  if (!r || !g || !b)
    return;
  if (!g_wall_comp_on.load() || !g_wall_color_set.load())
    return;

  // 全黑：保持熄灭，不做除法归一
  if (*r <= 0.f && *g <= 0.f && *b <= 0.f) {
    *r = 0.f;
    *g = 0.f;
    *b = 0.f;
    return;
  }

  const float tr = *r / g_wall_ref_r.load();
  const float tg = *g / g_wall_ref_g.load();
  const float tb = *b / g_wall_ref_b.load();
  float mx = tr;
  if (tg > mx)
    mx = tg;
  if (tb > mx)
    mx = tb;
  if (mx <= 0.f) {
    *r = 0.f;
    *g = 0.f;
    *b = 0.f;
    return;
  }
  // 为什么：不能按通道截断 255，否则比例崩掉又变回「墙上看像白」
  const float scale = 255.f / mx;
  *r = tr * scale;
  *g = tg * scale;
  *b = tb * scale;
  if (*r > 255.f)
    *r = 255.f;
  if (*g > 255.f)
    *g = 255.f;
  if (*b > 255.f)
    *b = 255.f;
  if (*r < 0.f)
    *r = 0.f;
  if (*g < 0.f)
    *g = 0.f;
  if (*b < 0.f)
    *b = 0.f;
}
