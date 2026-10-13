#pragma once

#include <mutex>

struct ID3D11Device;

// init/shutdown、跨线程查询（enum / current_output）、grab 采样全程共用。
// recursive：dxgi_init 内会调 dxgi_shutdown；grab 持锁时可能再进 is_ready。
extern std::recursive_mutex g_dxgi_life_mu;

// 供同目录枚举 / 诊断读当前 D3D 设备；未 init 返回 nullptr。
ID3D11Device *dxgi_d3d_device();
