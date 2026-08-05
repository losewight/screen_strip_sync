#pragma once

// light_engine 模块内部共享状态；对外仍只暴露 light_engine.h。

#include "light_engine.h"

#include <atomic>
#include <mutex>
#include <thread>

extern std::atomic<bool> g_running;
extern std::thread g_worker;
extern std::mutex g_engine_mu;

extern std::atomic<float> g_alpha;
extern std::atomic<char> g_mode;

extern std::atomic<char> g_region_algo;
extern std::atomic<int> g_region_blur;
extern std::atomic<float> g_region_smooth;
extern std::atomic<int> g_region_dark;
extern std::mutex g_region_bbox_mu;
extern int g_region_l, g_region_t, g_region_w, g_region_h;

extern std::atomic<SyncPath> g_sync_path;

extern std::mutex g_com_mu;
extern char g_com_name[16];

extern std::mutex g_map_mu;
extern bool g_map_custom;
extern SegmentRect g_map[kSegmentCount];

extern float g_ema_r[10];
extern float g_ema_g[10];
extern float g_ema_b[10];
extern bool g_ema_inited;

extern std::mutex g_intent_mu;
extern DisplayIntent g_intent;

// 发帧线程入口（engine_frame.cpp）；engine_start_path 启动时挂上去
void frame_loop(HANDLE h);
