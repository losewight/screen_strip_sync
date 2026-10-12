#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#include "dxgi_output_internal.h"

#include "dxgi_capture_internal.h"

#include <cstdio>
#include <cstring>
#include <cwchar>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <mutex>

// 当前 duplicate 的那块屏。日志 / IPC 上报 / 校准蒙版对齐共用。
// DeviceName 转成 UTF-8 窄字符：helper.log 是字节流，项目开了 /utf-8，
// 不能 printf("%ls")（宽窄混写会乱码）。
static CaptureOutputInfo g_output_info{};
// 配置要抓的屏；shutdown 不清，ACCESS_LOST 重建仍按这个名字匹配。
static char g_wanted_output[64] = "";

void dxgi_set_capture_output(const char *wanted) {
  if (!wanted) {
    g_wanted_output[0] = '\0';
    return;
  }
  snprintf(g_wanted_output, sizeof(g_wanted_output), "%s", wanted);
}

const char *dxgi_wanted_output() { return g_wanted_output; }

const CaptureOutputInfo &dxgi_selected_output_info() { return g_output_info; }

void dxgi_clear_output_info() { g_output_info = {}; }

static void wide_to_utf8(const WCHAR *wide, char *out, int cap) {
  if (!out || cap <= 0)
    return;
  out[0] = '\0';
  if (!wide)
    return;
  const int n = WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, cap, nullptr,
                                    nullptr);
  if (n <= 0)
    out[0] = '\0';
}

// 友好名会进 IPC 行尾；去掉换行和 '%'，避免拆行 / printf 吃掉后续格式。
static void sanitize_ipc_rest(char *s) {
  if (!s)
    return;
  char *w = s;
  for (const char *r = s; *r; ++r) {
    const char c = *r;
    if (c == '\r' || c == '\n' || c == '%')
      continue;
    *w++ = c;
  }
  *w = '\0';
  while (w > s && (w[-1] == ' ' || w[-1] == '\t'))
    *--w = '\0';
  char *p = s;
  while (*p == ' ' || *p == '\t')
    ++p;
  if (p != s)
    std::memmove(s, p, std::strlen(p) + 1);
}

// DXGI DeviceName（\\.\DISPLAYn）对 CCD 的 viewGdiDeviceName。
// 优先 QueryDisplayConfig 的 monitorFriendlyDeviceName（Twinkle Tray 同类），
// 查不到再退 EnumDisplayDevices 的监视器 DeviceString。
static void fill_friendly_name(const WCHAR *gdi_device, char *out, int cap) {
  if (!out || cap <= 1)
    return;
  out[0] = '\0';
  if (!gdi_device || !gdi_device[0])
    return;

  UINT32 pathCount = 0, modeCount = 0;
  if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount,
                                  &modeCount) == ERROR_SUCCESS &&
      pathCount > 0 && pathCount <= 32 && modeCount > 0 && modeCount <= 128) {
    DISPLAYCONFIG_PATH_INFO paths[32];
    DISPLAYCONFIG_MODE_INFO modes[128];
    UINT32 pc = pathCount;
    UINT32 mc = modeCount;
    if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pc, paths, &mc, modes,
                           nullptr) == ERROR_SUCCESS) {
      for (UINT32 i = 0; i < pc; ++i) {
        DISPLAYCONFIG_SOURCE_DEVICE_NAME src{};
        src.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
        src.header.size = sizeof(src);
        src.header.adapterId = paths[i].sourceInfo.adapterId;
        src.header.id = paths[i].sourceInfo.id;
        if (DisplayConfigGetDeviceInfo(&src.header) != ERROR_SUCCESS)
          continue;
        if (std::wcscmp(src.viewGdiDeviceName, gdi_device) != 0)
          continue;

        DISPLAYCONFIG_TARGET_DEVICE_NAME tgt{};
        tgt.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
        tgt.header.size = sizeof(tgt);
        tgt.header.adapterId = paths[i].targetInfo.adapterId;
        tgt.header.id = paths[i].targetInfo.id;
        if (DisplayConfigGetDeviceInfo(&tgt.header) != ERROR_SUCCESS)
          continue;
        if (tgt.monitorFriendlyDeviceName[0] == L'\0')
          continue;
        wide_to_utf8(tgt.monitorFriendlyDeviceName, out, cap);
        sanitize_ipc_rest(out);
        if (out[0])
          return;
      }
    }
  }

  DISPLAY_DEVICEW mon{};
  mon.cb = sizeof(mon);
  if (EnumDisplayDevicesW(gdi_device, 0, &mon, 0) && mon.DeviceString[0]) {
    wide_to_utf8(mon.DeviceString, out, cap);
    sanitize_ipc_rest(out);
  }
}

static bool wanted_is_auto(const char *wanted) {
  return wanted == nullptr || wanted[0] == '\0' ||
         std::strcmp(wanted, "auto") == 0;
}

static void fill_output_info(const DXGI_OUTPUT_DESC &desc, UINT index,
                             UINT total, CaptureOutputInfo *info) {
  if (!info)
    return;
  *info = CaptureOutputInfo{};
  wide_to_utf8(desc.DeviceName, info->device_name,
               (int)sizeof(info->device_name));
  fill_friendly_name(desc.DeviceName, info->friendly_name,
                     (int)sizeof(info->friendly_name));
  info->desktop = desc.DesktopCoordinates;
  // 为什么：Windows 定义主屏左上角即虚拟桌面原点 (0,0)，与上报的
  // DesktopCoordinates 同源，不必再调 GetMonitorInfo。
  info->is_primary =
      desc.DesktopCoordinates.left == 0 && desc.DesktopCoordinates.top == 0;
  info->index = index;
  info->total = total;
}

// 唯一选屏点。匹配顺序（wanted 为空或 "auto" 时跳过第一步）：
//   1) DXGI_OUTPUT_DESC.DeviceName 精确匹配配置值
//   2) 主屏 —— DesktopCoordinates 左上角为 (0,0)
//   3) 序号 0（兜底，不保证是主屏）
// 为什么走 DeviceName 而不是 index：index 由驱动与接口连接顺序决定，
// 拔插显示器会漂；DeviceName 稳定。
// 调用方拿到 *out 后负责 Release。
DxgiErr dxgi_select_capture_output(IDXGIAdapter *adapter, IDXGIOutput1 **out) {
  if (!out)
    return DxgiErr::NoOutput;
  *out = nullptr;
  if (!adapter)
    return DxgiErr::NoOutput;

  const char *wanted = g_wanted_output;
  const bool want_named = !wanted_is_auto(wanted);
  int match_i = -1;
  int primary_i = -1;
  UINT total = 0;

  for (UINT i = 0;; ++i) {
    IDXGIOutput *output = nullptr;
    const HRESULT hr = adapter->EnumOutputs(i, &output);
    if (hr == DXGI_ERROR_NOT_FOUND)
      break;
    if (FAILED(hr) || !output) {
      printf("EnumOutputs(%u) failed: 0x%08lx\n", i, (unsigned long)hr);
      break;
    }
    DXGI_OUTPUT_DESC desc{};
    if (SUCCEEDED(output->GetDesc(&desc))) {
      char name[64]{};
      wide_to_utf8(desc.DeviceName, name, (int)sizeof(name));
      if (want_named && match_i < 0 && std::strcmp(name, wanted) == 0)
        match_i = (int)i;
      if (primary_i < 0 && desc.DesktopCoordinates.left == 0 &&
          desc.DesktopCoordinates.top == 0)
        primary_i = (int)i;
    }
    output->Release();
    ++total;
  }

  if (total == 0)
    return DxgiErr::NoOutput;

  if (want_named && match_i < 0)
    printf("capture output '%s' not found, fallback primary/index0\n", wanted);

  UINT pick = 0;
  if (match_i >= 0)
    pick = (UINT)match_i;
  else if (primary_i >= 0)
    pick = (UINT)primary_i;

  IDXGIOutput *output = nullptr;
  HRESULT hr = adapter->EnumOutputs(pick, &output);
  if (FAILED(hr) || !output) {
    printf("EnumOutputs(%u) retry failed: 0x%08lx\n", pick,
           (unsigned long)hr);
    return DxgiErr::NoOutput;
  }

  DXGI_OUTPUT_DESC desc{};
  const HRESULT desc_hr = output->GetDesc(&desc);

  IDXGIOutput1 *output1 = nullptr;
  hr = output->QueryInterface(__uuidof(IDXGIOutput1), (void **)&output1);
  output->Release();
  output = nullptr;
  if (FAILED(hr) || !output1) {
    printf("QueryInterface IDXGIOutput1 failed: 0x%08lx\n", (unsigned long)hr);
    return DxgiErr::DuplicateFailed;
  }

  if (SUCCEEDED(desc_hr))
    fill_output_info(desc, pick, total, &g_output_info);
  else
    g_output_info = CaptureOutputInfo{};

  *out = output1;
  return DxgiErr::Ok;
}

void dxgi_log_capture_output() {
  const RECT &r = g_output_info.desktop;
  const int w = r.right - r.left;
  const int h = r.bottom - r.top;
  printf("capture output: %s %dx%d at (%d,%d)%s index=%u/%u%s%s\n",
         g_output_info.device_name[0] ? g_output_info.device_name : "?", w, h,
         (int)r.left, (int)r.top, g_output_info.is_primary ? " primary" : "",
         g_output_info.index, g_output_info.total,
         g_output_info.friendly_name[0] ? " " : "",
         g_output_info.friendly_name);
}

bool dxgi_current_output(CaptureOutputInfo *out) {
  if (!out)
    return false;
  // 为什么：与 ACCESS_LOST 路径的 shutdown 竞态；持 life 锁拷贝快照
  std::lock_guard<std::recursive_mutex> life(g_dxgi_life_mu);
  if (!dxgi_is_ready() || g_output_info.device_name[0] == '\0')
    return false;
  *out = g_output_info;
  return true;
}

UINT dxgi_enum_outputs(CaptureOutputInfo *out, UINT cap) {
  if (!out || cap == 0)
    return 0;

  // 为什么：枚举可能较慢；持锁只 AddRef 设备，解锁后再 EnumOutputs
  ID3D11Device *device = nullptr;
  {
    std::lock_guard<std::recursive_mutex> life(g_dxgi_life_mu);
    device = dxgi_d3d_device();
    if (!device)
      return 0;
    device->AddRef();
  }

  IDXGIDevice *dxgi_device = nullptr;
  HRESULT hr =
      device->QueryInterface(__uuidof(IDXGIDevice), (void **)&dxgi_device);
  if (FAILED(hr) || !dxgi_device) {
    device->Release();
    return 0;
  }

  IDXGIAdapter *adapter = nullptr;
  hr = dxgi_device->GetParent(__uuidof(IDXGIAdapter), (void **)&adapter);
  dxgi_device->Release();
  dxgi_device = nullptr;
  if (FAILED(hr) || !adapter) {
    device->Release();
    return 0;
  }

  UINT n = 0;
  for (UINT i = 0; n < cap; ++i) {
    IDXGIOutput *output = nullptr;
    hr = adapter->EnumOutputs(i, &output);
    if (hr == DXGI_ERROR_NOT_FOUND)
      break;
    if (FAILED(hr) || !output)
      break;
    DXGI_OUTPUT_DESC desc{};
    if (SUCCEEDED(output->GetDesc(&desc))) {
      fill_output_info(desc, i, 0, &out[n]);
      ++n;
    }
    output->Release();
  }
  adapter->Release();
  device->Release();

  for (UINT i = 0; i < n; ++i)
    out[i].total = n;
  return n;
}
