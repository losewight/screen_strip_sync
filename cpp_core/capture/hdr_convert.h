#pragma once

#include <cstdint>

// HDR FP16 scRGB → sRGB8。白点归一 + Reinhard 软压缩；LUT 热路径查表。
// white_nits：系统 SDR 内容白（DISPLAYCONFIG_SDR_WHITE_LEVEL → nits）。
// peak_nits：显示器 MaxLuminance；不足 white 时按 white 处理。

constexpr float kHdrKnee = 0.75f;

void hdr_convert_set_params(float white_nits, float peak_nits);

float hdr_convert_white_nits();
float hdr_convert_peak_nits();

// rgba_half：R16G16B16A16_FLOAT 一像素；out_rgb = {R,G,B} 0..255 sRGB。
void hdr_px_to_rgb8(const std::uint16_t *rgba_half, std::uint8_t out_rgb[3]);

// 测试 / 工具：float → IEEE half 位型。
std::uint16_t hdr_float_to_half(float f);
