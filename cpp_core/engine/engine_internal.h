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
extern std::atomic<float> g_saturation;
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

// D1 硬件死区：每段 OFF/ON + 灭灯确认帧（与 g_ema_* 同步启停重置）
struct SegState {
  bool on = false;
  int off_count = 0;
};
extern SegState g_seg[10];
// 默认见 PLAN_D §6：T_on=1 / T_off=0 / N=2；enable 关则旁路方便 A/B
extern std::atomic<int> g_dz_ton;
extern std::atomic<int> g_dz_toff;
extern std::atomic<int> g_dz_off_frames;
extern std::atomic<bool> g_dz_enable;

extern std::mutex g_intent_mu;
extern DisplayIntent g_intent;

// 发帧线程入口（engine_frame.cpp）；engine_start_path 启动时挂上去
void frame_loop(HANDLE h);
