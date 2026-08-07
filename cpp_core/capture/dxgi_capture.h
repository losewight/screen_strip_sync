#pragma once

#include "segment_map.h"

#include <Windows.h>

enum class DxgiErr {
  Ok = 0,
  DeviceCreateFailed,
  QueryDxgiFailed,
  NoOutput,
  DuplicateFailed,
  AcquireTimeout,
  AcquireFailed,
  // 桌面复制失效（分辨率切换 / 锁屏等）；调用方须 shutdown 再建
  AccessLost,
};

DxgiErr dxgi_init();
void dxgi_shutdown();
// 休眠拆资源后为 false；ensure 时据此决定是否再 init
bool dxgi_is_ready();
DxgiErr dxgi_grab_one_frame(UINT timeout_ms);
// out_rgb[i]={R,G,B}。rects 非空：按矩形步进抽点+丢近黑+RMS；
// nullptr：现有顶边均分（未校准）。
DxgiErr dxgi_grab_and_sample(UINT timeout_ms, unsigned char out_rgb[10][3],
                             const SegmentRect *rects);

// 屏幕氛围：主屏百分比 bbox 竖直切 10 段；algo 'm'=均值 / 'x'=最大；
// blur 近似 BoxBlur 邻域；dark：RGB 皆 < 阈值则该段置黑。与 map 路径正交。
DxgiErr dxgi_grab_and_sample_region(UINT timeout_ms, int l, int t, int w, int h,
                                    char algo, int blur, int dark,
                                    unsigned char out_rgb[10][3]);

// 采样可调参；IPC 经 engine_set_* 转发。内部 clamp。
void dxgi_set_near_black(int v); // 0..64，默认 0
void dxgi_set_blur(int v);       // 0..8，默认 2；0=不扩邻域
