#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#include "dxgi_capture.h"

#include "dxgi_mapped.h"
#include "hdr_convert.h"
#include "helper_log.h"
#include "letterbox_detect.h"
#include "light_engine.h"
#include "pixel_reader.h"
#include "subtitle_detect.h"

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dxgi1_5.h>
#include <dxgi1_6.h>

static ID3D11Device *g_device = nullptr;
static ID3D11DeviceContext *g_context = nullptr;
static IDXGIOutputDuplication *g_duplication = nullptr;
static ID3D11Texture2D *g_staging = nullptr;

// 当前 duplicate 的那块屏。日志 / IPC 上报 / 校准蒙版对齐共用。
// DeviceName 转成 UTF-8 窄字符：helper.log 是字节流，项目开了 /utf-8，
// 不能 printf("%ls")（宽窄混写会乱码）。
static CaptureOutputInfo g_output_info{};
// 配置要抓的屏；shutdown 不清，ACCESS_LOST 重建仍按这个名字匹配。
static char g_wanted_output[64] = "";

// 为什么：IPC 写、采样热路径只 load；与 Flutter AppConfig 对齐
static std::atomic<int> g_near_black{30}; // 0..64；默认与 HelperConfig 对齐
static std::atomic<int> g_blur_step{0};  // 0..8
static std::atomic<char> g_sample_algo{'m'}; // 固定 mean；'r'=rms 保留接口兼容
// 近黑亮度：'6'=Rec.601（默认），'a'=(R+G+B)/3
static std::atomic<char> g_near_black_luma{'6'};

// E：HDR 诊断 / 转换参数；init 与 2s 轮询写，采样与 IPC 读
static bool g_hdr_active = false;
static float g_sdr_white_nits = 80.f;
static float g_max_luminance = 80.f;
static DXGI_FORMAT g_dup_format = DXGI_FORMAT_UNKNOWN;
static DWORD g_last_white_refresh_ms = 0;
static constexpr DWORD kWhiteRefreshPeriodMs = 2000;

// Rec.601 luma：同等算术平均下绿远亮于蓝，简单均值会把暗蓝留下、把暗绿误剔。
static unsigned rec601_luma(unsigned r, unsigned g, unsigned b) {
  return (299u * r + 587u * g + 114u * b) / 1000u;
}

static unsigned avg_luma(unsigned r, unsigned g, unsigned b) {
  return (r + g + b) / 3u;
}

static unsigned pixel_luma(unsigned r, unsigned g, unsigned b) {
  return g_near_black_luma.load() == 'a' ? avg_luma(r, g, b)
                                         : rec601_luma(r, g, b);
}

// 热路径失败限流窗口（ms）；首条立即打，同 key 重复合并
static constexpr unsigned kDxgiFailLogPeriodMs = 5000;

// 为什么：ACCESS_LOST 后指针仍活着，必须让上层拆再建；ACCESS_DENIED /
// INVALID_CALL 在 duplication 已死后走同一条恢复路径（与唤醒 0x80070005 同源）
static bool is_duplication_lost(HRESULT hr) {
  return hr == DXGI_ERROR_ACCESS_LOST || hr == DXGI_ERROR_ACCESS_DENIED ||
         hr == DXGI_ERROR_INVALID_CALL;
}

static DxgiErr acquire_fail_err(HRESULT hr) {
  // 稳定地址作限流 key（勿直接传临时字面量指针跨编译单元歧义）
  static const char kKeyLost[] = "dxgi.acquire.lost";
  static const char kKeyFail[] = "dxgi.acquire.fail";
  if (is_duplication_lost(hr)) {
    // 为什么：ACCESS_LOST 恢复环可能连打数千行；限流保诊断密度
    helper_log_rate(kKeyLost, kDxgiFailLogPeriodMs,
                    "AcquireNextFrame access lost: 0x%08lx\n",
                    (unsigned long)hr);
    return DxgiErr::AccessLost;
  }
  helper_log_rate(kKeyFail, kDxgiFailLogPeriodMs,
                  "AcquireNextFrame failed: 0x%08lx\n", (unsigned long)hr);
  return DxgiErr::AcquireFailed;
}

void dxgi_set_near_black(int v) {
  if (v < 0)
    v = 0;
  if (v > 64)
    v = 64;
  g_near_black.store(v);
}

void dxgi_set_blur(int v) {
  if (v < 0)
    v = 0;
  if (v > 8)
    v = 8;
  g_blur_step.store(v);
}

void dxgi_set_sample_algo(char algo) {
  (void)algo;
  // UI 已撤；map 采样固定算术平均。
  g_sample_algo.store('m');
}

void dxgi_set_near_black_luma(char mode) {
  (void)mode;
  // UI 已撤；近黑亮度固定 Rec.601。
  g_near_black_luma.store('6');
}

void dxgi_set_capture_output(const char *wanted) {
  if (!wanted) {
    g_wanted_output[0] = '\0';
    return;
  }
  snprintf(g_wanted_output, sizeof(g_wanted_output), "%s", wanted);
}

// 为什么：真桌面 format 不固定；按 format 算每像素字节数，才能和 RowPitch
// 对照。
static int bytes_per_pixel(DXGI_FORMAT fmt) {
  switch (fmt) {
  case DXGI_FORMAT_B8G8R8A8_UNORM:
  case DXGI_FORMAT_R8G8B8A8_UNORM:
    return 4;
  case DXGI_FORMAT_R16G16B16A16_FLOAT:
    return 8;
  default:
    return 0;
  }
}

// CCD：按 GDI DeviceName 查 SDR 白点（nits）。失败回落 80。
static float query_sdr_white_nits(const WCHAR *gdi_device) {
  if (!gdi_device || !gdi_device[0])
    return 80.f;
  UINT32 pathCount = 0, modeCount = 0;
  if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount,
                                  &modeCount) != ERROR_SUCCESS ||
      pathCount == 0 || pathCount > 32 || modeCount == 0 || modeCount > 128)
    return 80.f;
  DISPLAYCONFIG_PATH_INFO paths[32];
  DISPLAYCONFIG_MODE_INFO modes[128];
  UINT32 pc = pathCount;
  UINT32 mc = modeCount;
  if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pc, paths, &mc, modes,
                         nullptr) != ERROR_SUCCESS)
    return 80.f;
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

    DISPLAYCONFIG_SDR_WHITE_LEVEL lvl{};
    lvl.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SDR_WHITE_LEVEL;
    lvl.header.size = sizeof(lvl);
    lvl.header.adapterId = paths[i].targetInfo.adapterId;
    lvl.header.id = paths[i].targetInfo.id;
    if (DisplayConfigGetDeviceInfo(&lvl.header) != ERROR_SUCCESS)
      return 80.f;
    // SDRWhiteLevel：以 1000 为基准的倍率；nits = level/1000 * 80
    if (lvl.SDRWhiteLevel == 0)
      return 80.f;
    return (float)lvl.SDRWhiteLevel / 1000.f * 80.f;
  }
  return 80.f;
}

static const char *color_space_name(DXGI_COLOR_SPACE_TYPE cs) {
  switch (cs) {
  case DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709:
    return "G22_P709";
  case DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709:
    return "G10_P709";
  case DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020:
    return "G2084_P2020";
  case DXGI_COLOR_SPACE_RGB_STUDIO_G2084_NONE_P2020:
    return "G2084_P2020_studio";
  default:
    return "other";
  }
}

// 读 Output6 描述 + SDR 白点，写入全局并重建 LUT。
static void refresh_hdr_params(IDXGIOutput1 *output1, const WCHAR *gdi_device,
                               bool log_line) {
  float max_nits = 80.f;
  UINT bits = 0;
  DXGI_COLOR_SPACE_TYPE cs = DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709;
  bool got_desc1 = false;
  if (output1) {
    IDXGIOutput6 *o6 = nullptr;
    if (SUCCEEDED(output1->QueryInterface(__uuidof(IDXGIOutput6),
                                          (void **)&o6)) &&
        o6) {
      DXGI_OUTPUT_DESC1 d1{};
      if (SUCCEEDED(o6->GetDesc1(&d1))) {
        max_nits = d1.MaxLuminance > 0.f ? d1.MaxLuminance : 80.f;
        bits = d1.BitsPerColor;
        cs = d1.ColorSpace;
        got_desc1 = true;
      }
      o6->Release();
    }
  }
  const float white = query_sdr_white_nits(gdi_device);
  g_sdr_white_nits = white;
  g_max_luminance = max_nits;
  hdr_convert_set_params(white, max_nits);
  g_last_white_refresh_ms = GetTickCount();
  if (log_line) {
    printf("hdr diag: ColorSpace=%s(%u) BitsPerColor=%u MaxLuminance=%.1f "
           "SDRWhite=%.1f nits Format=%u%s\n",
           color_space_name(cs), (unsigned)cs, bits, max_nits, white,
           (unsigned)g_dup_format, got_desc1 ? "" : " (no Output6)");
  }
}

static void maybe_refresh_white_level() {
  const DWORD now = GetTickCount();
  if (now - g_last_white_refresh_ms < kWhiteRefreshPeriodMs)
    return;
  // 无 output 指针时只刷新白点（峰值沿用 init 时的 MaxLuminance）
  WCHAR wide[64]{};
  if (g_output_info.device_name[0]) {
    MultiByteToWideChar(CP_UTF8, 0, g_output_info.device_name, -1, wide, 64);
  }
  const float white = query_sdr_white_nits(wide);
  g_sdr_white_nits = white;
  hdr_convert_set_params(white, g_max_luminance);
  g_last_white_refresh_ms = now;
}

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
static DxgiErr select_capture_output(IDXGIAdapter *adapter, const char *wanted,
                                     IDXGIOutput1 **out) {
  if (!out)
    return DxgiErr::NoOutput;
  *out = nullptr;
  if (!adapter)
    return DxgiErr::NoOutput;

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

static void log_capture_output() {
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

DxgiErr dxgi_init() {
  // 为什么：失败半截或休眠 teardown 后再 init，必须先清干净再重建
  if (g_device || g_context || g_duplication || g_staging)
    dxgi_shutdown();

  D3D_FEATURE_LEVEL level_out = {};
  HRESULT hr = D3D11CreateDevice(
      nullptr,                  // 默认适配器（主显卡）
      D3D_DRIVER_TYPE_HARDWARE, // 用真 GPU，不用 WARP 软件光栅
      nullptr,
      0,          // 无调试 flag（先简单）
      nullptr, 0, // 默认 feature level 列表
      D3D11_SDK_VERSION, &g_device, &level_out, &g_context);

  if (FAILED(hr) || !g_device || !g_context) {
    printf("D3D11CreateDevice failed: 0x%08lx\n", (unsigned long)hr);
    dxgi_shutdown();
    return DxgiErr::DeviceCreateFailed;
  }

  printf("D3D11 device ok, feature_level=0x%x\n", (unsigned)level_out);

  IDXGIDevice *dxgi_device = nullptr;
  hr = g_device->QueryInterface(__uuidof(IDXGIDevice), (void **)&dxgi_device);
  if (FAILED(hr) || !dxgi_device) {
    printf("QueryInterface IDXGIDevice failed: 0x%08lx\n", (unsigned long)hr);
    dxgi_shutdown();
    return DxgiErr::QueryDxgiFailed;
  }

  IDXGIAdapter *adapter = nullptr;
  hr = dxgi_device->GetParent(__uuidof(IDXGIAdapter), (void **)&adapter);
  dxgi_device->Release();
  dxgi_device = nullptr;
  if (FAILED(hr) || !adapter) {
    printf("GetParent IDXGIAdapter failed: 0x%08lx\n", (unsigned long)hr);
    dxgi_shutdown();
    return DxgiErr::QueryDxgiFailed;
  }

  IDXGIOutput1 *output1 = nullptr;
  const DxgiErr sel =
      select_capture_output(adapter, g_wanted_output, &output1);
  adapter->Release();
  adapter = nullptr;
  if (sel != DxgiErr::Ok || !output1) {
    printf("select_capture_output failed: %d\n", (int)sel);
    dxgi_shutdown();
    return sel != DxgiErr::Ok ? sel : DxgiErr::NoOutput;
  }

  // 为什么：DuplicateOutput1 可要 FP16；失败回落旧 DuplicateOutput（仍可能被系统降成 8 位）
  IDXGIOutput5 *output5 = nullptr;
  HRESULT hr5 =
      output1->QueryInterface(__uuidof(IDXGIOutput5), (void **)&output5);
  if (SUCCEEDED(hr5) && output5) {
    const DXGI_FORMAT supported[] = {
        DXGI_FORMAT_R16G16B16A16_FLOAT,
        DXGI_FORMAT_B8G8R8A8_UNORM,
    };
    hr = output5->DuplicateOutput1(g_device, 0, ARRAYSIZE(supported), supported,
                                   &g_duplication);
    output5->Release();
    output5 = nullptr;
    if (FAILED(hr) || !g_duplication) {
      printf("DuplicateOutput1 failed: 0x%08lx, fallback DuplicateOutput\n",
             (unsigned long)hr);
      g_duplication = nullptr;
      hr = output1->DuplicateOutput(g_device, &g_duplication);
    } else {
      printf("DuplicateOutput1 ok\n");
    }
  } else {
    printf("IDXGIOutput5 unavailable, fallback DuplicateOutput\n");
    hr = output1->DuplicateOutput(g_device, &g_duplication);
  }

  if (FAILED(hr) || !g_duplication) {
    printf("DuplicateOutput failed: 0x%08lx\n", (unsigned long)hr);
    output1->Release();
    dxgi_shutdown();
    return DxgiErr::DuplicateFailed;
  }

  DXGI_OUTDUPL_DESC dup_desc{};
  g_duplication->GetDesc(&dup_desc);
  g_dup_format = dup_desc.ModeDesc.Format;
  g_hdr_active = (g_dup_format == DXGI_FORMAT_R16G16B16A16_FLOAT);

  WCHAR gdi_wide[64]{};
  if (g_output_info.device_name[0])
    MultiByteToWideChar(CP_UTF8, 0, g_output_info.device_name, -1, gdi_wide, 64);
  refresh_hdr_params(output1, gdi_wide, true);

  output1->Release();
  output1 = nullptr;

  printf("DuplicateOutput ok Format=%u hdr_active=%d\n", (unsigned)g_dup_format,
         g_hdr_active ? 1 : 0);
  log_capture_output();
  return DxgiErr::Ok;
}

DxgiErr dxgi_grab_one_frame(UINT timeout_ms) {
  if (!g_duplication)
    return DxgiErr::DuplicateFailed;

  DXGI_OUTDUPL_FRAME_INFO info = {};
  IDXGIResource *resource = nullptr;
  HRESULT hr = g_duplication->AcquireNextFrame(timeout_ms, &info, &resource);

  if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
    // 为什么：桌面无刷新时属常态；勿每帧打日志（曾刷爆诊断包）
    static const char kKeyTimeout[] = "dxgi.acquire.timeout";
    helper_log_rate(kKeyTimeout, kDxgiFailLogPeriodMs,
                    "AcquireNextFrame: timeout (no new frame)\n");
    return DxgiErr::AcquireTimeout;
  }
  if (FAILED(hr))
    return acquire_fail_err(hr);

  // printf("AcquireNextFrame ok, LastPresentTime=%lld\n",
  //        (long long)info.LastPresentTime.QuadPart);

  // 1) resource → Texture2D
  ID3D11Texture2D *gpu_tex = nullptr;
  hr = resource->QueryInterface(__uuidof(ID3D11Texture2D), (void **)&gpu_tex);
  resource->Release();
  resource = nullptr;
  if (FAILED(hr) || !gpu_tex) {
    printf("QI Texture2D failed: 0x%08lx\n", (unsigned long)hr);
    g_duplication->ReleaseFrame();
    return DxgiErr::AcquireFailed;
  }

  D3D11_TEXTURE2D_DESC desc = {};
  gpu_tex->GetDesc(&desc);
  // printf("desktop tex: %ux%u format=%u\n", desc.Width, desc.Height,
  //        (unsigned)desc.Format);

  // 2) 建 Staging（CPU 可读），CopyResource 从 GPU 拷过来
  D3D11_TEXTURE2D_DESC staging_desc = desc;
  staging_desc.Usage = D3D11_USAGE_STAGING;
  staging_desc.BindFlags = 0;
  staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  staging_desc.MiscFlags = 0;

  ID3D11Texture2D *staging = nullptr;
  hr = g_device->CreateTexture2D(&staging_desc, nullptr, &staging);
  if (FAILED(hr) || !staging) {
    printf("CreateTexture2D staging failed: 0x%08lx\n", (unsigned long)hr);
    gpu_tex->Release();
    g_duplication->ReleaseFrame();
    return DxgiErr::AcquireFailed;
  }

  g_context->CopyResource(staging, gpu_tex);
  gpu_tex->Release();
  gpu_tex = nullptr;

  // 3) Map：拿到 CPU 指针 + RowPitch（= stride）
  D3D11_MAPPED_SUBRESOURCE mapped = {};
  hr = g_context->Map(staging, 0, D3D11_MAP_READ, 0, &mapped);
  if (FAILED(hr)) {
    printf("Map failed: 0x%08lx\n", (unsigned long)hr);
    staging->Release();
    g_duplication->ReleaseFrame();
    return DxgiErr::AcquireFailed;
  }

  const int bpp = bytes_per_pixel(desc.Format);
  const unsigned char *p = (const unsigned char *)mapped.pData;
  // printf("stride(RowPitch)=%u  W*bpp=%u  bpp=%d\n",
  // (unsigned)mapped.RowPitch,
  //        bpp > 0 ? desc.Width * (unsigned)bpp : 0u, bpp);

  if (desc.Format == DXGI_FORMAT_B8G8R8A8_UNORM) {
    printf("pixel0 BGRA=%02x %02x %02x %02x\n", p[0], p[1], p[2], p[3]);
  } else if (desc.Format == DXGI_FORMAT_R16G16B16A16_FLOAT) {
    const unsigned short *h = (const unsigned short *)p;
    unsigned char rgb[3];
    hdr_px_to_rgb8(h, rgb);
    printf("pixel0 RGB(from float16)=%02x %02x %02x\n", rgb[0], rgb[1],
           rgb[2]);
  } else {
    printf("pixel0: unsupported format, skip decode\n");
  }

  g_context->Unmap(staging, 0);
  staging->Release();

  g_duplication->ReleaseFrame();
  return DxgiErr::Ok;
}

DxgiErr dxgi_map_desktop(UINT timeout_ms, DxgiMappedFrame *out) {
  if (!out)
    return DxgiErr::AcquireFailed;
  *out = DxgiMappedFrame{};
  if (!g_duplication || !g_device || !g_context)
    return DxgiErr::DuplicateFailed;

  maybe_refresh_white_level();

  DXGI_OUTDUPL_FRAME_INFO info = {};
  IDXGIResource *resource = nullptr;
  HRESULT hr = E_FAIL;

  // 为什么：30×timeout 不可打断会拖住 engine_stop；丢掉 1～2 帧全黑首帧足够
  for (int try_i = 0; try_i < 2; ++try_i) {
    if (!engine_is_running())
      return DxgiErr::AcquireTimeout;
    info = {};
    resource = nullptr;
    hr = g_duplication->AcquireNextFrame(timeout_ms, &info, &resource);

    if (hr == DXGI_ERROR_WAIT_TIMEOUT)
      continue;

    if (FAILED(hr))
      return acquire_fail_err(hr);

    if (info.LastPresentTime.QuadPart != 0)
      break;

    resource->Release();
    resource = nullptr;
    g_duplication->ReleaseFrame();
  }

  if (FAILED(hr) || !resource) {
    // 桌面静止时属常态；frame_loop 只 Sleep(10) 就重试，无节流会刷爆 helper.log
    static const char kKeyNoPresent[] = "dxgi.acquire.nopresent";
    helper_log_rate(kKeyNoPresent, kDxgiFailLogPeriodMs,
                    "AcquireNextFrame: no valid present after retries\n");
    return DxgiErr::AcquireTimeout;
  }

  ID3D11Texture2D *gpu_tex = nullptr;
  hr = resource->QueryInterface(__uuidof(ID3D11Texture2D), (void **)&gpu_tex);
  resource->Release();
  resource = nullptr;
  if (FAILED(hr) || !gpu_tex) {
    printf("QI Texture2D failed: 0x%08lx\n", (unsigned long)hr);
    g_duplication->ReleaseFrame();
    return DxgiErr::AcquireFailed;
  }

  D3D11_TEXTURE2D_DESC desc = {};
  gpu_tex->GetDesc(&desc);

  bool need_new = (g_staging == nullptr);
  if (!need_new) {
    D3D11_TEXTURE2D_DESC old = {};
    g_staging->GetDesc(&old);
    if (old.Width != desc.Width || old.Height != desc.Height ||
        old.Format != desc.Format)
      need_new = true;
  }

  if (need_new) {
    if (g_staging) {
      g_staging->Release();
      g_staging = nullptr;
    }
    D3D11_TEXTURE2D_DESC staging_desc = desc;
    staging_desc.Usage = D3D11_USAGE_STAGING;
    staging_desc.BindFlags = 0;
    staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    staging_desc.MiscFlags = 0;

    hr = g_device->CreateTexture2D(&staging_desc, nullptr, &g_staging);
    if (FAILED(hr) || !g_staging) {
      printf("CreateTexture2D staging failed: 0x%08lx\n", (unsigned long)hr);
      gpu_tex->Release();
      g_duplication->ReleaseFrame();
      return DxgiErr::AcquireFailed;
    }
  }

  g_context->CopyResource(g_staging, gpu_tex);
  gpu_tex->Release();

  D3D11_MAPPED_SUBRESOURCE mapped = {};
  hr = g_context->Map(g_staging, 0, D3D11_MAP_READ, 0, &mapped);
  if (FAILED(hr)) {
    printf("Map failed: 0x%08lx\n", (unsigned long)hr);
    g_duplication->ReleaseFrame();
    return DxgiErr::AcquireFailed;
  }

  const int bpp = bytes_per_pixel(desc.Format);
  if (bpp <= 0) {
    g_context->Unmap(g_staging, 0);
    g_duplication->ReleaseFrame();
    return DxgiErr::AcquireFailed;
  }

  out->desc = desc;
  out->mapped = mapped;
  out->bpp = bpp;
  out->stride = mapped.RowPitch;
  out->pixels = (const unsigned char *)mapped.pData;
  return DxgiErr::Ok;
}

void dxgi_unmap_desktop() {
  if (g_context && g_staging)
    g_context->Unmap(g_staging, 0);
  if (g_duplication)
    g_duplication->ReleaseFrame();
}

DxgiErr dxgi_grab_and_sample(UINT timeout_ms, unsigned char out_rgb[10][3],
                             const SegmentRect *rects) {
  DxgiMappedFrame frame{};
  DxgiErr e = dxgi_map_desktop(timeout_ms, &frame);
  if (e != DxgiErr::Ok)
    return e;

  const D3D11_TEXTURE2D_DESC &desc = frame.desc;
  const unsigned char *p = frame.pixels;
  const int bpp = frame.bpp;
  const UINT stride = frame.stride;
  const unsigned fmt = (unsigned)desc.Format;

  if (fmt != (unsigned)DXGI_FORMAT_B8G8R8A8_UNORM &&
      fmt != (unsigned)DXGI_FORMAT_R16G16B16A16_FLOAT) {
    dxgi_unmap_desktop();
    return DxgiErr::AcquireFailed;
  }

  const LARGE_INTEGER t0 = [] {
    LARGE_INTEGER v{};
    QueryPerformanceCounter(&v);
    return v;
  }();

  letterbox_process(p, (int)desc.Width, (int)desc.Height, (int)stride, bpp,
                    fmt);
  subtitle_process(p, (int)desc.Width, (int)desc.Height, (int)stride, bpp,
                   fmt);

  auto sample_rects = [&](auto reader_tag) {
    using Reader = decltype(reader_tag);
    const int nearBlack = g_near_black.load();
    const int blur = g_blur_step.load();
    const bool use_rms = g_sample_algo.load() != 'm';
    // FP16 更贵：略降抽点（E4）
    const int dens = (Reader::kBpp > 4) ? 12 : 16;
    int lb_bottom = 0;
    letterbox_get_inset(nullptr, &lb_bottom);
    int sub_crop = 0;
    subtitle_get_bottom_crop(&sub_crop);
    for (int i = 0; i < kSegmentCount; ++i) {
      int x0 = (int)(rects[i].x0 * (float)desc.Width);
      int x1 = (int)(rects[i].x1 * (float)desc.Width);
      int y0 = 0, y1 = 0;
      letterbox_map_y_range(rects[i].y0, rects[i].y1, (int)desc.Height, &y0,
                            &y1);
      if (x0 < 0)
        x0 = 0;
      if (x1 > (int)desc.Width)
        x1 = (int)desc.Width;
      if (x1 <= x0)
        x1 = x0 + 1;
      if (x1 > (int)desc.Width)
        x1 = (int)desc.Width;
      if (y1 > (int)desc.Height)
        y1 = (int)desc.Height;
      // 字幕带：内容底再上收；与 letterbox Y 映射串联
      const int y_limit = (int)desc.Height - lb_bottom - sub_crop;
      if (y1 > y_limit)
        y1 = y_limit;
      if (y1 <= y0) {
        out_rgb[i][0] = 0;
        out_rgb[i][1] = 0;
        out_rgb[i][2] = 0;
        continue;
      }

      const int rw = x1 - x0;
      const int rh = y1 - y0;
      int step_x = rw > dens ? rw / dens : 1;
      int step_y = rh > dens ? rh / dens : 1;
      if (step_x < 1)
        step_x = 1;
      if (step_y < 1)
        step_y = 1;

      unsigned long long acc_r = 0, acc_g = 0, acc_b = 0;
      int count = 0;
      for (int y = y0; y < y1; y += step_y) {
        for (int x = x0; x < x1; x += step_x) {
          for (int dy = -blur; dy <= blur; ++dy) {
            const int sy = y + dy;
            if (sy < 0 || sy >= (int)desc.Height)
              continue;
            for (int dx = -blur; dx <= blur; ++dx) {
              const int sx = x + dx;
              if (sx < 0 || sx >= (int)desc.Width)
                continue;
              const unsigned char *px =
                  p + (UINT)sy * stride + (UINT)sx * (UINT)bpp;
              unsigned r = 0, g = 0, b = 0;
              Reader::read_rgb(px, &r, &g, &b);
              if (pixel_luma(r, g, b) < (unsigned)nearBlack)
                continue;
              if (use_rms) {
                acc_r += (unsigned long long)r * r;
                acc_g += (unsigned long long)g * g;
                acc_b += (unsigned long long)b * b;
              } else {
                acc_r += r;
                acc_g += g;
                acc_b += b;
              }
              ++count;
            }
          }
        }
      }
      if (count == 0) {
        out_rgb[i][0] = 0;
        out_rgb[i][1] = 0;
        out_rgb[i][2] = 0;
      } else if (use_rms) {
        const float inv = 1.f / (float)count;
        out_rgb[i][0] = (unsigned char)(sqrtf((float)acc_r * inv) + 0.5f);
        out_rgb[i][1] = (unsigned char)(sqrtf((float)acc_g * inv) + 0.5f);
        out_rgb[i][2] = (unsigned char)(sqrtf((float)acc_b * inv) + 0.5f);
      } else {
        out_rgb[i][0] = (unsigned char)(acc_r / (unsigned long long)count);
        out_rgb[i][1] = (unsigned char)(acc_g / (unsigned long long)count);
        out_rgb[i][2] = (unsigned char)(acc_b / (unsigned long long)count);
      }
    }
  };

  auto sample_top = [&](auto reader_tag) {
    using Reader = decltype(reader_tag);
    int top = 0, bottom = 0;
    letterbox_get_inset(&top, &bottom);
    const UINT y =
        (UINT)(top + (desc.Height > (UINT)(top + 2) ? 2 : 0));
    const int blurStep = g_blur_step.load();
    const int nearBlack = g_near_black.load();
    const bool use_rms = g_sample_algo.load() != 'm';
    for (int i = 0; i < 10; ++i) {
      const UINT x = (UINT)((i + 0.5) * desc.Width / 10);
      unsigned long long acc_r = 0, acc_g = 0, acc_b = 0;
      int count = 0;
      for (int dx = -blurStep; dx <= blurStep; ++dx) {
        const int sx = (int)x + dx;
        if (sx < 0 || sx >= (int)desc.Width)
          continue;
        const unsigned char *px = p + y * stride + (UINT)sx * (UINT)bpp;
        unsigned r = 0, g = 0, b = 0;
        Reader::read_rgb(px, &r, &g, &b);
        if (pixel_luma(r, g, b) < (unsigned)nearBlack)
          continue;
        if (use_rms) {
          acc_r += (unsigned long long)r * r;
          acc_g += (unsigned long long)g * g;
          acc_b += (unsigned long long)b * b;
        } else {
          acc_r += r;
          acc_g += g;
          acc_b += b;
        }
        ++count;
      }
      if (count == 0) {
        out_rgb[i][0] = 0;
        out_rgb[i][1] = 0;
        out_rgb[i][2] = 0;
      } else if (use_rms) {
        const float inv = 1.f / (float)count;
        out_rgb[i][0] = (unsigned char)(sqrtf((float)acc_r * inv) + 0.5f);
        out_rgb[i][1] = (unsigned char)(sqrtf((float)acc_g * inv) + 0.5f);
        out_rgb[i][2] = (unsigned char)(sqrtf((float)acc_b * inv) + 0.5f);
      } else {
        out_rgb[i][0] = (unsigned char)(acc_r / (unsigned long long)count);
        out_rgb[i][1] = (unsigned char)(acc_g / (unsigned long long)count);
        out_rgb[i][2] = (unsigned char)(acc_b / (unsigned long long)count);
      }
    }
  };

  if (fmt == (unsigned)DXGI_FORMAT_R16G16B16A16_FLOAT) {
    if (rects)
      sample_rects(Fp16Reader{});
    else
      sample_top(Fp16Reader{});
  } else {
    if (rects)
      sample_rects(BgraReader{});
    else
      sample_top(BgraReader{});
  }

  // E4：限流打采样耗时，blur 大时盯 FP16 成本
  {
    LARGE_INTEGER t1{}, freq{};
    QueryPerformanceCounter(&t1);
    QueryPerformanceFrequency(&freq);
    const double ms =
        freq.QuadPart
            ? (double)(t1.QuadPart - t0.QuadPart) * 1000.0 / (double)freq.QuadPart
            : 0.0;
    static const char kKeySampleMs[] = "dxgi.sample.ms";
    helper_log_rate(kKeySampleMs, 5000,
                    "sample %.2fms format=%u blur=%d hdr=%d\n", ms,
                    (unsigned)fmt, g_blur_step.load(), g_hdr_active ? 1 : 0);
  }

  dxgi_unmap_desktop();
  return DxgiErr::Ok;
}

void dxgi_shutdown() {
  if (g_staging) {
    g_staging->Release();
    g_staging = nullptr;
  }
  if (g_duplication) {
    g_duplication->Release();
    g_duplication = nullptr;
  }
  if (g_context) {
    g_context->Release();
    g_context = nullptr;
  }
  if (g_device) {
    g_device->Release();
    g_device = nullptr;
  }
  g_output_info = {};
  g_hdr_active = false;
  g_dup_format = DXGI_FORMAT_UNKNOWN;
}

bool dxgi_is_ready() { return g_device != nullptr && g_duplication != nullptr; }

bool dxgi_current_output(CaptureOutputInfo *out) {
  if (!out)
    return false;
  if (!dxgi_is_ready() || g_output_info.device_name[0] == '\0')
    return false;
  *out = g_output_info;
  return true;
}

UINT dxgi_enum_outputs(CaptureOutputInfo *out, UINT cap) {
  if (!out || cap == 0 || !g_device)
    return 0;

  IDXGIDevice *dxgi_device = nullptr;
  HRESULT hr =
      g_device->QueryInterface(__uuidof(IDXGIDevice), (void **)&dxgi_device);
  if (FAILED(hr) || !dxgi_device)
    return 0;

  IDXGIAdapter *adapter = nullptr;
  hr = dxgi_device->GetParent(__uuidof(IDXGIAdapter), (void **)&adapter);
  dxgi_device->Release();
  dxgi_device = nullptr;
  if (FAILED(hr) || !adapter)
    return 0;

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

  for (UINT i = 0; i < n; ++i)
    out[i].total = n;
  return n;
}
