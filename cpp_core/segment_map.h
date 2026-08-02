#pragma once

// 10 段屏幕采样矩形（归一化 0..1）；与 Flutter SegmentSample / IPC 百分比对齐。
static constexpr int kSegmentCount = 10;

struct SegmentRect {
  float x0 = 0.f;
  float y0 = 0.f;
  float x1 = 1.f;
  float y1 = 1.f;
};
