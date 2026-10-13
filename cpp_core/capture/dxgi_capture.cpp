#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#include "dxgi_capture.h"

#include "dxgi_capture_internal.h"
#include "dxgi_mapped.h"
#include "dxgi_output_internal.h"
#include "hdr_convert.h"
#include "helper_log.h"
#include "light_engine.h"

#include <cstdio>
#include <cwchar>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dxgi1_5.h>
#include <dxgi1_6.h>
#include <mutex>

std::recursive_mutex g_dxgi_life_mu;

static ID3D11Device *g_device = nullptr;
static ID3D11DeviceContext *g_context = nullptr;
static IDXGIOutputDuplication *g_duplication = nullptr;
static ID3D11Texture2D *g_staging = nullptr;

// E：HDR 诊断 / 转换参数；init 与 2s 轮询写
static bool g_hdr_active = false;
static float g_sdr_white_nits = 80.f;
static float g_max_luminance = 80.f;
static DXGI_FORMAT g_dup_format = DXGI_FORMAT_UNKNOWN;
static DWORD g_last_white_refresh_ms = 0;
static constexpr DWORD kWhiteRefreshPeriodMs = 2000;

// 热路径失败限流窗口（ms）；首条立即打，同 key 重复合并
static constexpr unsigned kDxgiFailLogPeriodMs = 5000;

ID3D11Device *dxgi_d3d_device() { return g_device; }

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
  const CaptureOutputInfo &info = dxgi_selected_output_info();
  if (info.device_name[0]) {
    MultiByteToWideChar(CP_UTF8, 0, info.device_name, -1, wide, 64);
  }
  const float white = query_sdr_white_nits(wide);
  g_sdr_white_nits = white;
  hdr_convert_set_params(white, g_max_luminance);
  g_last_white_refresh_ms = now;
}

DxgiErr dxgi_init() {
  std::lock_guard<std::recursive_mutex> life(g_dxgi_life_mu);
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
  const DxgiErr sel = dxgi_select_capture_output(adapter, &output1);
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
  const CaptureOutputInfo &info = dxgi_selected_output_info();
  if (info.device_name[0])
    MultiByteToWideChar(CP_UTF8, 0, info.device_name, -1, gdi_wide, 64);
  refresh_hdr_params(output1, gdi_wide, true);

  output1->Release();
  output1 = nullptr;

  printf("DuplicateOutput ok Format=%u hdr_active=%d\n", (unsigned)g_dup_format,
         g_hdr_active ? 1 : 0);
  dxgi_log_capture_output();
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

void dxgi_shutdown() {
  std::lock_guard<std::recursive_mutex> life(g_dxgi_life_mu);
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
  dxgi_clear_output_info();
  g_hdr_active = false;
  g_dup_format = DXGI_FORMAT_UNKNOWN;
}

bool dxgi_is_ready() {
  std::lock_guard<std::recursive_mutex> life(g_dxgi_life_mu);
  return g_device != nullptr && g_duplication != nullptr;
}
