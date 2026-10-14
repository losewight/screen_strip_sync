#pragma once

// 音乐动态配色：纯函数，不依赖 DXGI / 全局状态。
// t = 段在本条 bar 内位置 0..1；level = 当前电平 0..1；now_ms 供 Rainbow 流动。

enum class MusicPalette { Vu, Rainbow, Fixed, Level, Screen };

void music_palette_color(MusicPalette p, float t, float level, unsigned now_ms,
                         const unsigned char fixed[3],
                         const unsigned char *screen_rgb, // 仅 Screen；可空
                         unsigned char out[3]);

// Fixed 下发：最大通道 → 255；全 0 非法，返回 false 且不写 out。
bool music_palette_normalize_rgb(const unsigned char in[3],
                                 unsigned char out[3]);
