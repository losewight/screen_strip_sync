#pragma once

#include "segment_map.h"
#include <cstddef>

// 全局物理灯带规格（支持 2、3、4、5 米，对应 20、30、40、50 颗物理灯珠）。
// 默认为 2；自检/握手时根据 get_length 动态更新。
int engine_get_device_step();
void engine_set_device_step(int step);

// 校验是否为支持的米数（2, 3, 4, 5）
bool is_valid_strip_length(int meters);

// 解析固件返回的长度响应（支持 "2\r\n", "4\r\n", "rep_length 4\r\n" 等；未识别返回 0）
int parse_strip_length(const char *buf);

// 通用组帧生成器（生成 set_rgb_pc ASCII 控制帧）
// 格式：set_rgb_pc %04x 00 %02x %s %d %s %d ... %s %d\r\n
//
// 参数说明：
// - frame_id: 帧序列号（0..0xFFFF）
// - brightness: 全局亮度（0..100，十六进制输出为 00..64；默认常亮帧用 0x63）
// - colors: 10 段色彩 hex 字符串（格式如 "rrggbb" 或 "00ffff"）
// - step: 每段步进；若传 <= 0 则自动采用 engine_get_device_step()
// - out_frame: 输出字符缓冲区
// - out_cap: 输出缓冲区容量（至少需 >= 120 字节）
//
// 返回值：
// - 成功返回 true；
// - 参数非法、缓冲区不足或组帧长度 >= 120 字节（触碰红线）时返回 false，且清空输出。

// 1. 数组形式（char colors[10][7]）
bool build_rgb_pc_frame(unsigned frame_id, unsigned brightness,
                        const char colors[kSegmentCount][7], int step,
                        char *out_frame, size_t out_cap);

// 2. 指针数组形式（const char *const colors[10]）
bool build_rgb_pc_frame(unsigned frame_id, unsigned brightness,
                        const char *const colors[kSegmentCount], int step,
                        char *out_frame, size_t out_cap);

// 3. 纯色快捷形式（全 10 段均为相同颜色 color_hex）
bool build_rgb_pc_solid_frame(unsigned frame_id, unsigned brightness,
                              const char *color_hex, int step,
                              char *out_frame, size_t out_cap);
