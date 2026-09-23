#pragma once

// 电影 letterbox：扫上下黑边 → 对称 inset → 采样 Y 映射进内容窗。
// 与 near_black / 死区正交；算法只在本翻译单元。
// 日志（状态变化）：enable / hard_disable / inset=N / inset=0 (fullscreen)

void letterbox_set_enabled(bool on);
// 校准 / highlight：强制 inset=0；不改用户开关
void letterbox_set_hard_disable(bool on);
void letterbox_reset();

// BGRA8 mapped 帧；关开关或 hard_disable 时 clear inset 并直接返回
void letterbox_process_bgra(const unsigned char *pixels, int width, int height,
                            int stride, int bpp);

// 对称厚度（top==bottom）；未启用时均为 0
void letterbox_get_inset(int *top_px, int *bottom_px);

// 归一化 y(0..1) → 内容窗像素；contentH = H - 2*inset
int letterbox_map_y(float y_norm, int screen_h);
void letterbox_map_y_range(float y0, float y1, int screen_h, int *out_y0,
                           int *out_y1);
