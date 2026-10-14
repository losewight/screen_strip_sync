#pragma once

#include "dxgi_capture.h"

#include <cstddef>

// Music 路径组帧；不走 seg_gate / EMA。参数见 music_params.h。
DxgiErr produce_colors_music(int frame_index, char *out_frame, size_t out_cap);
