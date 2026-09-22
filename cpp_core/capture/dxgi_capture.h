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
// out_rgb[i]={R,G,B}。rects 非空：按矩形步进抽点+Rec.601 丢近黑+rms/mean；
// nullptr：顶边均分 + Rec.601 丢近黑 + blur；count==0 输出黑。
DxgiErr dxgi_grab_and_sample(UINT timeout_ms, unsigned char out_rgb[10][3],
                             const SegmentRect *rects);

// 屏幕氛围：被抓那块屏的百分比 bbox 竖直切 10 段；algo 'm'=均值 / 'x'=最大；
// blur 近似 BoxBlur 邻域；dark：RGB 皆 < 阈值则该段置黑。与 map 路径正交。
DxgiErr dxgi_grab_and_sample_region(UINT timeout_ms, int l, int t, int w, int h,
                                    char algo, int blur, int dark,
                                    unsigned char out_rgb[10][3]);

// 采样可调参；IPC 经 engine_set_* 转发。内部 clamp。
void dxgi_set_near_black(int v); // 0..64，默认 0
void dxgi_set_blur(int v);       // 0..8，默认 0；0=不扩邻域
void dxgi_set_sample_algo(char algo); // 'r'=rms, 'm'=mean；默认 rms
// 下次 dxgi_init 用的目标屏；空 / "auto" = 主屏再序号 0。不立刻换屏。
void dxgi_set_capture_output(const char *wanted);

// DeviceName 已转 UTF-8（如 \\.\DISPLAY1）；desktop 是虚拟桌面物理像素。
// friendly_name 是 CCD/EDID 友好名（如 Q27G4SL_WS）；查不到则为空。
// 选屏身份永远是 DeviceName，友好名只给 UI 显示。
struct CaptureOutputInfo {
  char device_name[64]{};
  char friendly_name[128]{};
  RECT desktop{};
  bool is_primary = false;
  UINT index = 0;
  UINT total = 0;
};

// 当前 duplicate 的那块（auto 解析后的结果）。未就绪返回 false。
bool dxgi_current_output(CaptureOutputInfo *out);
// 现场枚举当前 D3D 设备所在 adapter 的 output。返回写入条数（≤ cap）。
// 为什么：混合显卡上 Flutter 能看见的屏不一定能 Duplicate；蒙版矩形须与
// duplication 同源。
UINT dxgi_enum_outputs(CaptureOutputInfo *out, UINT cap);
