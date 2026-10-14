#pragma once

#include "audio_capture.h"

// 音乐模式运行时参数：与 engine_params 解耦，供 music_frame 与后续
// engine_set_music_* 包装共用。

void music_set_source(MusicSource src);
MusicSource music_get_source();

void music_set_layout_linear_or_mirror(char layout); // 'l'|'m'；P1 mirror 仍按 linear
char music_get_layout();

void music_set_reverse(bool reverse);
bool music_get_reverse();

void music_set_sensitivity(int v); // 0..100
int music_get_sensitivity();

void music_set_decay(int v); // 0..100
int music_get_decay();

void music_set_silence(char mode); // 'o'=off | 'm'=min
char music_get_silence();
