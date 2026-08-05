#pragma once

#include "dxgi_capture.h"

#include <d3d11.h>

// 抓一帧桌面到 staging 并 Map。成功后调用方必须 dxgi_unmap_desktop。
// map / region 采样共用，避免两套 Acquire 路径分叉。
struct DxgiMappedFrame {
  D3D11_TEXTURE2D_DESC desc{};
  D3D11_MAPPED_SUBRESOURCE mapped{};
  int bpp = 0;
  UINT stride = 0;
  const unsigned char *pixels = nullptr;
};

DxgiErr dxgi_map_desktop(UINT timeout_ms, DxgiMappedFrame *out);
void dxgi_unmap_desktop();
