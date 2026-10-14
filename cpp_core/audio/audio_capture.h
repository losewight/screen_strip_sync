#pragma once

// WASAPI 系统 loopback / 麦克风采集；独立线程，发帧路径只取窗口电平。

enum class MusicSource { System, Mic, Both };

enum class AudioStatus { Ok, NoDevice, Denied, Error };

void audio_start(MusicSource src);
void audio_stop();
void audio_restart(MusicSource src);
// 取走自上次读取以来的累计窗口：rms / peak 都是 0..1 线性幅度；Both 取两路 max
void audio_take_window(float *out_rms, float *out_peak);
AudioStatus audio_status();
