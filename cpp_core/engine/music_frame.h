#pragma once

#include "dxgi_capture.h"

#include <cstddef>

// Music 路径组帧。合成配色不走 seg_gate；Screen 经 map_sample_step。
// 参数见 music_params.h / music_palette.h。
DxgiErr produce_colors_music(int frame_index, char *out_frame, size_t out_cap);
