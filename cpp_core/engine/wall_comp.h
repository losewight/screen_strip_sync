#pragma once

// 墙面反射补偿：按墙色相对比例施加阻尼补偿，保持输入峰值亮度量纲 (orig_max)。
// 热路径：map/region 组帧前、send_solid 入参后；highlight 不做。

// 对 r/g/b（0..255 浮点）就地补偿；未启用或未设墙色则原样。
void wall_comp_apply(float *r, float *g, float *b);

void engine_set_wall_comp(bool on);
// 6 位 hex；非法返回 false。空串清除墙色（启用也 no-op）。
bool engine_set_wall_color(const char *rrggbb);
void engine_clear_wall_color();
