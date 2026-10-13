#include "wall_comp.h"

#include <atomic>
#include <cstdint>
#include <cstring>

// 为什么：IPC/配置写、发帧读；热路径只 load
static std::atomic<bool> g_wall_comp_on{false};
// 打包：bit24=已设置；低 24 位 = R<<16|G<<8|B（原始 0..255 字节）
// 一次 load 保证三通道 + 标志一致，避免多 atomic 交错读到混色
static std::atomic<uint32_t> g_wall_rgb{0};

// 近黑通道防除零；1/255 ≈ 单级反射率
static constexpr float kRefEps = 1.f / 255.f;

static float ref_from_byte(unsigned w) {
  float r = (float)w / 255.f;
  return r < kRefEps ? kRefEps : r;
}

void engine_set_wall_comp(bool on) { g_wall_comp_on.store(on); }

void engine_clear_wall_color() { g_wall_rgb.store(0); }

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
  const uint32_t packed = (1u << 24) | ((rgb[0] & 0xffu) << 16) |
                          ((rgb[1] & 0xffu) << 8) | (rgb[2] & 0xffu);
  g_wall_rgb.store(packed);
  return true;
}

void wall_comp_apply(float *r, float *g, float *b) {
  if (!r || !g || !b)
    return;
  if (!g_wall_comp_on.load())
    return;
  const uint32_t packed = g_wall_rgb.load();
  if ((packed & (1u << 24)) == 0)
    return;

  // 为什么：取整后已是 0 的近黑残差若再按墙反射率放大，
  // 会把「该灭」变成很亮，废掉快速灭灯并造成切黑啪亮。
  // 口径与组帧 / disp_zero 一致：+0.5 取整后三通道皆 0。
  const unsigned ur = (unsigned)(*r + 0.5f);
  const unsigned ug = (unsigned)(*g + 0.5f);
  const unsigned ub = (unsigned)(*b + 0.5f);
  if (ur == 0 && ug == 0 && ub == 0) {
    *r = *g = *b = 0.f;
    return;
  }

  const float ref_r = ref_from_byte((packed >> 16) & 0xffu);
  const float ref_g = ref_from_byte((packed >> 8) & 0xffu);
  const float ref_b = ref_from_byte(packed & 0xffu);
  const float tr = *r / ref_r;
  const float tg = *g / ref_g;
  const float tb = *b / ref_b;
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
