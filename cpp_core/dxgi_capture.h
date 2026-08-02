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
};

DxgiErr dxgi_init();
void dxgi_shutdown();
DxgiErr dxgi_grab_one_frame(UINT timeout_ms);
// out_rgb[i]={R,G,B}。rects 非空：按矩形步进抽点+丢近黑+RMS；
// nullptr：现有顶边均分（未校准）。
DxgiErr dxgi_grab_and_sample(UINT timeout_ms, unsigned char out_rgb[10][3],
                             const SegmentRect *rects);

// 采样可调参；IPC 经 engine_set_* 转发。内部 clamp。
void dxgi_set_near_black(int v); // 0..64，默认 12
void dxgi_set_blur(int v);       // 0..8，默认 2；0=不扩邻域
