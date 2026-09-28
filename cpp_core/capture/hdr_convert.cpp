#include "hdr_convert.h"

#include <cmath>
#include <cstring>

namespace {

constexpr float kDefaultWhiteNits = 80.f;
constexpr float kDefaultPeakNits = 1000.f;
constexpr int kLinLutSize = 4097; // index = round(lin * 4096), lin in [0,1]

float g_white_nits = kDefaultWhiteNits;
float g_peak_nits = kDefaultPeakNits;
float g_peak_ratio = kDefaultPeakNits / kDefaultWhiteNits; // ≥1

// half 位型 → 已按白点归一的线性 scRGB（负/NaN→0）
float g_half_to_lin[65536];
// 线性 [0,1] → sRGB8
std::uint8_t g_lin_to_srgb8[kLinLutSize];

float half_bits_to_float(std::uint16_t h) {
  const unsigned sign = (h >> 15) & 1u;
  const unsigned exp = (h >> 10) & 0x1Fu;
  const unsigned mant = h & 0x3FFu;
  float f;
  if (exp == 0) {
    if (mant == 0)
      f = 0.f;
    else
      f = std::ldexpf((float)mant / 1024.f, -14);
  } else if (exp == 31) {
    // Inf / NaN：按 0，避免灯带飞掉
    return 0.f;
  } else {
    f = std::ldexpf(1.f + (float)mant / 1024.f, (int)exp - 15);
  }
  return sign ? -f : f;
}

std::uint8_t lin_to_srgb_byte(float lin) {
  if (lin <= 0.f)
    return 0;
  if (lin >= 1.f)
    return 255;
  float s;
  if (lin <= 0.0031308f)
    s = 12.92f * lin;
  else
    s = 1.055f * std::powf(lin, 1.f / 2.4f) - 0.055f;
  if (s < 0.f)
    s = 0.f;
  if (s > 1.f)
    s = 1.f;
  return (std::uint8_t)(s * 255.f + 0.5f);
}

// extended Reinhard 思路：膝点以上软肩；强制 f(1)=1 以保住 SDR 白→255。
// [0,knee] 原样；(knee,1] smoothstep 到 1；(1,peak] 压到 1（灯带无头上空间）。
float rolloff_max(float m, float knee, float peak) {
  if (m <= knee)
    return m;
  if (m <= 1.f) {
    const float span = 1.f - knee;
    if (span < 1e-4f)
      return m;
    const float t = (m - knee) / span;
    // smoothstep：f(knee)=knee、f(1)=1，肩部略抬
    const float s = t * t * (3.f - 2.f * t);
    return knee + span * s;
  }
  // HDR 高光：无 8bit 头上空间，软压到 1（峰值为白）
  (void)peak;
  return 1.f;
}

void rebuild_luts() {
  const float scale = 80.f / g_white_nits;
  for (int i = 0; i < 65536; ++i) {
    float v = half_bits_to_float((std::uint16_t)i) * scale;
    if (!(v > 0.f)) // 负、NaN、-0 → 0
      v = 0.f;
    g_half_to_lin[i] = v;
  }
  for (int i = 0; i < kLinLutSize; ++i) {
    const float lin = (float)i / 4096.f;
    g_lin_to_srgb8[i] = lin_to_srgb_byte(lin);
  }
}

std::uint8_t lin_lookup(float lin) {
  if (lin <= 0.f)
    return 0;
  if (lin >= 1.f)
    return 255;
  int i = (int)(lin * 4096.f + 0.5f);
  if (i < 0)
    i = 0;
  if (i >= kLinLutSize)
    i = kLinLutSize - 1;
  return g_lin_to_srgb8[i];
}

struct LutInit {
  LutInit() { rebuild_luts(); }
};
LutInit g_lut_init;

} // namespace

void hdr_convert_set_params(float white_nits, float peak_nits) {
  if (!(white_nits >= 1.f))
    white_nits = kDefaultWhiteNits;
  if (white_nits > 10000.f)
    white_nits = 10000.f;
  if (!(peak_nits >= white_nits))
    peak_nits = white_nits;
  if (peak_nits > 100000.f)
    peak_nits = 100000.f;

  // 参数未变则跳过重建（含白点 2s 轮询）
  if (std::fabs(white_nits - g_white_nits) < 0.05f &&
      std::fabs(peak_nits - g_peak_nits) < 0.5f)
    return;

  g_white_nits = white_nits;
  g_peak_nits = peak_nits;
  g_peak_ratio = peak_nits / white_nits;
  if (g_peak_ratio < 1.f)
    g_peak_ratio = 1.f;
  rebuild_luts();
}

float hdr_convert_white_nits() { return g_white_nits; }
float hdr_convert_peak_nits() { return g_peak_nits; }

void hdr_px_to_rgb8(const std::uint16_t *rgba_half, std::uint8_t out_rgb[3]) {
  if (!rgba_half || !out_rgb) {
    if (out_rgb)
      out_rgb[0] = out_rgb[1] = out_rgb[2] = 0;
    return;
  }
  float r = g_half_to_lin[rgba_half[0]];
  float g = g_half_to_lin[rgba_half[1]];
  float b = g_half_to_lin[rgba_half[2]];
  float m = r > g ? r : g;
  if (b > m)
    m = b;
  if (m > kHdrKnee) {
    const float out_m = rolloff_max(m, kHdrKnee, g_peak_ratio);
    const float s = out_m / m;
    r *= s;
    g *= s;
    b *= s;
  }
  out_rgb[0] = lin_lookup(r);
  out_rgb[1] = lin_lookup(g);
  out_rgb[2] = lin_lookup(b);
}

std::uint16_t hdr_float_to_half(float f) {
  // 简化：与 LUT 解码互逆；NaN/Inf → 0
  if (!(f == f) || !std::isfinite(f))
    return 0;
  const bool neg = f < 0.f;
  if (neg)
    f = -f;
  if (f == 0.f)
    return neg ? 0x8000u : 0;

  int exp;
  float mant = std::frexpf(f, &exp); // f = mant * 2^exp, mant in [0.5,1)
  // half：1.m * 2^(e-15)，mant_half in [1,2) → 用 frexp 的 [0.5,1) 调整
  // 1.m = mant*2 → exp' = exp-1
  exp -= 1;
  mant *= 2.f; // now [1, 2)

  if (exp > 15) {
    // overflow → +inf bit pattern；解码侧当 0，测试勿依赖
    return (std::uint16_t)((neg ? 0x8000u : 0u) | 0x7C00u);
  }
  if (exp < -14) {
    // denormal
    const float scaled = std::ldexpf(f, 24); // mant * 2^(exp+14) * 1024 / 2? 
    // value = mant_bits/1024 * 2^-14
    int bits = (int)(std::ldexpf(f, 14 + 10) + 0.5f);
    if (bits <= 0)
      return neg ? 0x8000u : 0;
    if (bits > 0x3FF)
      bits = 0x3FF;
    return (std::uint16_t)((neg ? 0x8000u : 0u) | (unsigned)bits);
  }

  int e_bits = exp + 15;
  int m_bits = (int)((mant - 1.f) * 1024.f + 0.5f);
  if (m_bits > 0x3FF) {
    m_bits = 0;
    ++e_bits;
    if (e_bits >= 31)
      return (std::uint16_t)((neg ? 0x8000u : 0u) | 0x7C00u);
  }
  return (std::uint16_t)((neg ? 0x8000u : 0u) | ((unsigned)e_bits << 10) |
                         (unsigned)m_bits);
}
