#pragma once

#include <Windows.h>
// 为什么用枚举：抓屏失败原因很多（建设备失败 / 无显示器 / 锁屏），
// 布尔值只能说「失败」，验收时没法区分。
enum class DxgiErr {
  Ok = 0,
  DeviceCreateFailed,
  QueryDxgiFailed,
  NoOutput,
  DuplicateFailed,
  AcquireTimeout, // 超时：桌面暂时没有新帧（常见，不是致命）
  AcquireFailed,  // 其它失败（含锁屏后常见 ACCESS_LOST）
};

// 初始化 Desktop Duplication；成功返回 Ok，失败返回具体原因。
DxgiErr dxgi_init();

// 释放 COM 对象（以后有指针了再补；现在先空实现也行）。
void dxgi_shutdown();
DxgiErr dxgi_grab_one_frame(UINT timeout_ms);
// 为什么：输出 RGB 字节而非 hex——EMA/降噪是算数，字符串只留给最后组帧
// out_rgb[i] = {R,G,B}，0~255
DxgiErr dxgi_grab_and_sample(UINT timeout_ms, unsigned char out_rgb[10][3]);