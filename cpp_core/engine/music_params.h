#pragma once

#include "audio_capture.h"
#include "music_palette.h"

// 音乐模式运行时参数：与 engine_params 解耦，供 music_frame 与后续
// engine_set_music_* 包装共用。

void music_set_source(MusicSource src);
MusicSource music_get_source();

void music_set_layout_linear_or_mirror(char layout); // 'l'|'m'
char music_get_layout();

void music_set_reverse(bool reverse);
bool music_get_reverse();

void music_set_sensitivity(int v); // 0..100
int music_get_sensitivity();

void music_set_decay(int v); // 0..100
int music_get_decay();

void music_set_silence(char mode); // 'o'=off | 'm'=min
char music_get_silence();

// 双条镜像端点 l0,l1,r0,r1；-1=未设。非法长度忽略。
void music_set_mirror(const int ends[4]);
void music_clear_mirror();
void music_get_mirror(int out[4]);

void music_set_rest(char mode); // 'o'|off | 'p'|peak | 'b'|base
char music_get_rest();

// 配色：enum / 单字符 v|r|f|l|s / 词 vu|rainbow|fixed|level|screen
void music_set_palette(MusicPalette p);
void music_set_palette(char c);
bool music_set_palette_word(const char *word); // 未知返回 false
// 存盘 / IPC 用单字符；热路径用 enum 版
char music_get_palette();
MusicPalette music_get_palette_enum();

// RRGGBB；最大通道→255；000000 / 非法返回 false，保留旧值
bool music_set_color(const char *rrggbb);
void music_get_color(unsigned char out[3]);
void music_get_color_hex(char out[7]); // "rrggbb\0"
