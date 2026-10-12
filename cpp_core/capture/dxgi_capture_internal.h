#pragma once

struct ID3D11Device;

// 供同目录枚举 / 诊断读当前 D3D 设备；未 init 返回 nullptr。
ID3D11Device *dxgi_d3d_device();
