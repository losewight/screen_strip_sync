#pragma once

// Map 忽略字幕：扫内容区底部亮字/半透明条 → 滑动窗命中 → 裁 y1。
// 与 letterbox 正交（先黑边再字幕）；不用 near-black=13，不用连续稳定迟滞。
// 仅 map sample_rects；region / sample_top 不调用。

void subtitle_set_enabled(bool on);
// 校准 hold：强制 crop=0；不改用户开关
void subtitle_set_hard_disable(bool on);
void subtitle_reset();

// letterbox_process 之后调用；format 为 DXGI_FORMAT_*
void subtitle_process(const unsigned char *pixels, int width, int height,
                      int stride, int bpp, unsigned format);

// active 时的底部裁切像素（相对内容底）；未启用 / hold 为 0
void subtitle_get_bottom_crop(int *crop_px);
