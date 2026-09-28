#pragma once

// 电影 letterbox：扫上下黑边 → 对称 inset → 采样 Y 映射进内容窗。
// 与 near_black / 死区正交；算法只在本翻译单元。
// 日志（状态变化）：enable / hard_disable / inset=N / inset=0 (fullscreen)
// 像素格式由调用方保证：BGRA8 或已转成可读的 mapped 缓冲（见 letterbox_process）。

void letterbox_set_enabled(bool on);
// 校准 / highlight：强制 inset=0；不改用户开关
void letterbox_set_hard_disable(bool on);
void letterbox_reset();

// 通用入口：format 为 DXGI_FORMAT_* 的数值；仅处理 BGRA8 与 FP16。
void letterbox_process(const unsigned char *pixels, int width, int height,
                       int stride, int bpp, unsigned format);

// 兼容旧名（仅 BGRA）
inline void letterbox_process_bgra(const unsigned char *pixels, int width,
                                   int height, int stride, int bpp) {
  // DXGI_FORMAT_B8G8R8A8_UNORM == 87
  letterbox_process(pixels, width, height, stride, bpp, 87u);
}

// 对称厚度（top==bottom）；未启用时均为 0
void letterbox_get_inset(int *top_px, int *bottom_px);

// 归一化 y(0..1) → 内容窗像素；contentH = H - 2*inset
int letterbox_map_y(float y_norm, int screen_h);
void letterbox_map_y_range(float y0, float y1, int screen_h, int *out_y0,
                           int *out_y1);
