#include "dxgi_capture.h"

#include <atomic>
#include <cmath>
#include <cstdio>
#include <d3d11.h>
#include <dxgi1_2.h>

static ID3D11Device *g_device = nullptr;
static ID3D11DeviceContext *g_context = nullptr;
static IDXGIOutputDuplication *g_duplication = nullptr;
static ID3D11Texture2D *g_staging = nullptr;

// 为什么：IPC 写、采样热路径只 load；与 Flutter AppConfig 对齐
static std::atomic<int> g_near_black{12}; // 0..64
static std::atomic<int> g_blur_step{2};   // 0..8

// 为什么：ACCESS_LOST 后指针仍活着，必须让上层拆再建；ACCESS_DENIED /
// INVALID_CALL 在 duplication 已死后走同一条恢复路径（与唤醒 0x80070005 同源）
static bool is_duplication_lost(HRESULT hr) {
  return hr == DXGI_ERROR_ACCESS_LOST || hr == DXGI_ERROR_ACCESS_DENIED ||
         hr == DXGI_ERROR_INVALID_CALL;
}

static DxgiErr acquire_fail_err(HRESULT hr) {
  if (is_duplication_lost(hr)) {
    printf("AcquireNextFrame access lost: 0x%08lx\n", (unsigned long)hr);
    return DxgiErr::AccessLost;
  }
  printf("AcquireNextFrame failed: 0x%08lx\n", (unsigned long)hr);
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

// half-float → 0~255，仅用于打印验证（Day20 还不采样发灯）
static unsigned half_to_u8(unsigned short h) {
  const unsigned exp = (h >> 10) & 0x1F;
  const unsigned mant = h & 0x3FF;
  float f;
  if (exp == 0)
    f = 0.f;
  else if (exp == 31)
    f = 1.f;
  else
    f = ldexpf(1.f + mant / 1024.f, (int)exp - 15);

  if (f < 0.f)
    f = 0.f;
  if (f > 1.f)
    f = 1.f;
  return (unsigned)(f * 255.f + 0.5f);
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

  IDXGIOutput *output = nullptr;
  hr = adapter->EnumOutputs(0, &output); // 0 = 主显示器
  adapter->Release();
  adapter = nullptr;
  if (FAILED(hr) || !output) {
    printf("EnumOutputs(0) failed: 0x%08lx\n", (unsigned long)hr);
    dxgi_shutdown();
    return DxgiErr::NoOutput;
  }

  IDXGIOutput1 *output1 = nullptr;
  hr = output->QueryInterface(__uuidof(IDXGIOutput1), (void **)&output1);
  output->Release();
  output = nullptr;
  if (FAILED(hr) || !output1) {
    printf("QueryInterface IDXGIOutput1 failed: 0x%08lx\n", (unsigned long)hr);
    dxgi_shutdown();
    return DxgiErr::DuplicateFailed;
  }

  // 为什么：DuplicateOutput 要绑定「创建桌面复制的那个 D3D 设备」
  hr = output1->DuplicateOutput(g_device, &g_duplication);
  output1->Release();
  output1 = nullptr;
  if (FAILED(hr) || !g_duplication) {
    printf("DuplicateOutput failed: 0x%08lx\n", (unsigned long)hr);
    dxgi_shutdown();
    return DxgiErr::DuplicateFailed;
  }

  printf("DuplicateOutput ok\n");
  return DxgiErr::Ok;
}

DxgiErr dxgi_grab_one_frame(UINT timeout_ms) {
  if (!g_duplication)
    return DxgiErr::DuplicateFailed;

  DXGI_OUTDUPL_FRAME_INFO info = {};
  IDXGIResource *resource = nullptr;
  HRESULT hr = g_duplication->AcquireNextFrame(timeout_ms, &info, &resource);

  if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
    printf("AcquireNextFrame: timeout (no new frame)\n");
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
    printf("pixel0 RGB(from float16)=%02x %02x %02x\n", half_to_u8(h[0]),
           half_to_u8(h[1]), half_to_u8(h[2]));
  } else {
    printf("pixel0: unsupported format, skip decode\n");
  }

  g_context->Unmap(staging, 0);
  staging->Release();

  g_duplication->ReleaseFrame();
  return DxgiErr::Ok;
}

DxgiErr dxgi_grab_and_sample(UINT timeout_ms, unsigned char out_rgb[10][3],
                             const SegmentRect *rects) {
  if (!g_duplication)
    return DxgiErr::DuplicateFailed;

  DXGI_OUTDUPL_FRAME_INFO info = {};
  IDXGIResource *resource = nullptr;
  HRESULT hr = E_FAIL;

  // 为什么：DuplicateOutput 后首帧常 LastPresentTime=0 且像素全黑，需丢掉再采。
  for (int try_i = 0; try_i < 30; ++try_i) {
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
    printf("AcquireNextFrame: no valid present after retries\n");
    return DxgiErr::AcquireTimeout;
  }

  // 为什么：成功路径不 printf——控制台 I/O 比采样贵，易被调度放大
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

  // 为什么：分辨率/format 不变时复用 Staging，避免每帧 Create 整屏纹理
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
  gpu_tex = nullptr;

  // 3) Map：拿到 CPU 指针 + RowPitch（= stride）
  D3D11_MAPPED_SUBRESOURCE mapped = {};
  hr = g_context->Map(g_staging, 0, D3D11_MAP_READ, 0, &mapped);
  if (FAILED(hr)) {
    printf("Map failed: 0x%08lx\n", (unsigned long)hr);
    // 为什么：g_staging 进程级复用，失败也不 Release，下次还能用
    g_duplication->ReleaseFrame();
    return DxgiErr::AcquireFailed;
  }

  const int bpp = bytes_per_pixel(desc.Format);
  const unsigned char *p = (const unsigned char *)mapped.pData;

  if (bpp <= 0) {
    g_context->Unmap(g_staging, 0);
    g_duplication->ReleaseFrame();
    return DxgiErr::AcquireFailed;
  }

  const UINT stride = mapped.RowPitch;

  if (desc.Format == DXGI_FORMAT_B8G8R8A8_UNORM) {
    if (rects != nullptr) {
      // 步进抽点 + 丢近黑 + 可选 blur 邻域 + RMS
      const int nearBlack = g_near_black.load();
      const int blur = g_blur_step.load();
      for (int i = 0; i < kSegmentCount; ++i) {
        int x0 = (int)(rects[i].x0 * (float)desc.Width);
        int y0 = (int)(rects[i].y0 * (float)desc.Height);
        int x1 = (int)(rects[i].x1 * (float)desc.Width);
        int y1 = (int)(rects[i].y1 * (float)desc.Height);
        if (x0 < 0)
          x0 = 0;
        if (y0 < 0)
          y0 = 0;
        if (x1 > (int)desc.Width)
          x1 = (int)desc.Width;
        if (y1 > (int)desc.Height)
          y1 = (int)desc.Height;
        if (x1 <= x0)
          x1 = x0 + 1;
        if (y1 <= y0)
          y1 = y0 + 1;
        if (x1 > (int)desc.Width)
          x1 = (int)desc.Width;
        if (y1 > (int)desc.Height)
          y1 = (int)desc.Height;

        const int rw = x1 - x0;
        const int rh = y1 - y0;
        // 为什么：每段大约最多 ~16×16 点，控 CPU
        int step_x = rw > 16 ? rw / 16 : 1;
        int step_y = rh > 16 ? rh / 16 : 1;
        if (step_x < 1)
          step_x = 1;
        if (step_y < 1)
          step_y = 1;

        // 为什么：sRGB 算术均值偏灰；累加平方再开方 ≈ 线性空间均值
        unsigned long long sum_r2 = 0, sum_g2 = 0, sum_b2 = 0;
        int count = 0;
        for (int y = y0; y < y1; y += step_y) {
          for (int x = x0; x < x1; x += step_x) {
            // blur>0：格子点 ±blur 邻域一并采样（仍过近黑）
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
                const unsigned r = px[2], g = px[1], b = px[0];
                if ((r + g + b) / 3u < (unsigned)nearBlack)
                  continue;
                sum_r2 += (unsigned long long)r * r;
                sum_g2 += (unsigned long long)g * g;
                sum_b2 += (unsigned long long)b * b;
                ++count;
              }
            }
          }
        }
        if (count == 0) {
          out_rgb[i][0] = 0;
          out_rgb[i][1] = 0;
          out_rgb[i][2] = 0;
        } else {
          const float inv = 1.f / (float)count;
          out_rgb[i][0] = (unsigned char)(sqrtf((float)sum_r2 * inv) + 0.5f);
          out_rgb[i][1] = (unsigned char)(sqrtf((float)sum_g2 * inv) + 0.5f);
          out_rgb[i][2] = (unsigned char)(sqrtf((float)sum_b2 * inv) + 0.5f);
        }
      }
    } else {
      // 未校准：顶边均分；blur 为水平邻域半宽
      const UINT y = desc.Height > 2 ? 2u : 0;
      const int blurStep = g_blur_step.load();
      for (int i = 0; i < 10; ++i) {
        const UINT x = (UINT)((i + 0.5) * desc.Width / 10);
        unsigned sum_r = 0, sum_g = 0, sum_b = 0;
        int count = 0;
        for (int dx = -blurStep; dx <= blurStep; ++dx) {
          const int sx = (int)x + dx;
          if (sx < 0 || sx >= (int)desc.Width)
            continue;
          const unsigned char *px = p + y * stride + (UINT)sx * (UINT)bpp;
          sum_b += px[0];
          sum_g += px[1];
          sum_r += px[2];
          ++count;
        }
        out_rgb[i][0] = (unsigned char)(sum_r / count);
        out_rgb[i][1] = (unsigned char)(sum_g / count);
        out_rgb[i][2] = (unsigned char)(sum_b / count);
      }
    }
  } else if (desc.Format == DXGI_FORMAT_R16G16B16A16_FLOAT) {
    // float16：自定义 map 仍采矩形中心一点（罕见 format，先保可用）
    for (int i = 0; i < 10; ++i) {
      UINT x, y;
      if (rects != nullptr) {
        const float mx = 0.5f * (rects[i].x0 + rects[i].x1);
        const float my = 0.5f * (rects[i].y0 + rects[i].y1);
        x = (UINT)(mx * (float)desc.Width);
        y = (UINT)(my * (float)desc.Height);
        if (x >= desc.Width)
          x = desc.Width - 1;
        if (y >= desc.Height)
          y = desc.Height - 1;
      } else {
        x = (UINT)((i + 0.5) * desc.Width / 10);
        y = desc.Height > 2 ? 2u : 0;
      }
      const unsigned short *h =
          (const unsigned short *)(p + y * stride + x * (UINT)bpp);
      out_rgb[i][0] = (unsigned char)half_to_u8(h[0]);
      out_rgb[i][1] = (unsigned char)half_to_u8(h[1]);
      out_rgb[i][2] = (unsigned char)half_to_u8(h[2]);
    }
  } else {
    g_context->Unmap(g_staging, 0);
    g_duplication->ReleaseFrame();
    return DxgiErr::AcquireFailed;
  }

  g_context->Unmap(g_staging, 0);
  // 为什么：不 Release g_staging——归 dxgi_shutdown 管

  g_duplication->ReleaseFrame();
  return DxgiErr::Ok;
}

DxgiErr dxgi_grab_and_sample_region(UINT timeout_ms, int l, int t, int w, int h,
                                    char algo, int blur, int dark,
                                    unsigned char out_rgb[10][3]) {
  if (!g_duplication || !g_device || !g_context)
    return DxgiErr::DuplicateFailed;

  // clamp bbox
  if (l < 0)
    l = 0;
  if (t < 0)
    t = 0;
  if (w < 1)
    w = 1;
  if (h < 1)
    h = 1;
  if (l > 100)
    l = 100;
  if (t > 100)
    t = 100;
  if (w > 100)
    w = 100;
  if (h > 100)
    h = 100;
  if (l + w > 100)
    w = 100 - l;
  if (t + h > 100)
    h = 100 - t;
  if (w < 1 || h < 1)
    return DxgiErr::AcquireFailed;
  if (blur < 0)
    blur = 0;
  if (blur > 20)
    blur = 20;
  if (dark < 0)
    dark = 0;
  if (dark > 50)
    dark = 50;
  const bool use_max = (algo == 'x' || algo == 'X');

  DXGI_OUTDUPL_FRAME_INFO info = {};
  IDXGIResource *resource = nullptr;
  HRESULT hr = E_FAIL;

  for (int try_i = 0; try_i < 30; ++try_i) {
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
    printf("region AcquireNextFrame: no valid present\n");
    return DxgiErr::AcquireTimeout;
  }

  ID3D11Texture2D *gpu_tex = nullptr;
  hr = resource->QueryInterface(__uuidof(ID3D11Texture2D), (void **)&gpu_tex);
  resource->Release();
  resource = nullptr;
  if (FAILED(hr) || !gpu_tex) {
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
      gpu_tex->Release();
      g_duplication->ReleaseFrame();
      return DxgiErr::AcquireFailed;
    }
  }

  g_context->CopyResource(g_staging, gpu_tex);
  gpu_tex->Release();
  gpu_tex = nullptr;

  D3D11_MAPPED_SUBRESOURCE mapped = {};
  hr = g_context->Map(g_staging, 0, D3D11_MAP_READ, 0, &mapped);
  if (FAILED(hr)) {
    g_duplication->ReleaseFrame();
    return DxgiErr::AcquireFailed;
  }

  const int bpp = bytes_per_pixel(desc.Format);
  const unsigned char *p = (const unsigned char *)mapped.pData;
  if (bpp <= 0 || desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM) {
    // region 路径只支持常见 BGRA；其它 format 填黑避免乱色
    for (int i = 0; i < 10; ++i) {
      out_rgb[i][0] = 0;
      out_rgb[i][1] = 0;
      out_rgb[i][2] = 0;
    }
    g_context->Unmap(g_staging, 0);
    g_duplication->ReleaseFrame();
    return DxgiErr::Ok;
  }

  const UINT stride = mapped.RowPitch;
  const int screen_w = (int)desc.Width;
  const int screen_h = (int)desc.Height;
  int x0 = (l * screen_w) / 100;
  int y0 = (t * screen_h) / 100;
  int x1 = ((l + w) * screen_w) / 100;
  int y1 = ((t + h) * screen_h) / 100;
  if (x0 < 0)
    x0 = 0;
  if (y0 < 0)
    y0 = 0;
  if (x1 > screen_w)
    x1 = screen_w;
  if (y1 > screen_h)
    y1 = screen_h;
  if (x1 <= x0)
    x1 = x0 + 1;
  if (y1 <= y0)
    y1 = y0 + 1;
  if (x1 > screen_w)
    x1 = screen_w;
  if (y1 > screen_h)
    y1 = screen_h;

  const int region_w = x1 - x0;
  const int region_h = y1 - y0;

  // 竖直切 10 段（对齐 Python np.array_split axis=1）
  for (int i = 0; i < 10; ++i) {
    const int zx0 = x0 + (i * region_w) / 10;
    const int zx1 = x0 + ((i + 1) * region_w) / 10;
    int z_w = zx1 - zx0;
    if (z_w < 1)
      z_w = 1;

    // blur：扩采样窗近似 BoxBlur（不整图滤波，控 CPU）
    int sx0 = zx0 - blur;
    int sx1 = zx0 + z_w + blur;
    int sy0 = y0 - blur;
    int sy1 = y1 + blur;
    if (sx0 < 0)
      sx0 = 0;
    if (sy0 < 0)
      sy0 = 0;
    if (sx1 > screen_w)
      sx1 = screen_w;
    if (sy1 > screen_h)
      sy1 = screen_h;

    const int rw = sx1 - sx0;
    const int rh = sy1 - sy0;
    int step_x = rw > 24 ? rw / 24 : 1;
    int step_y = rh > 24 ? rh / 24 : 1;
    if (step_x < 1)
      step_x = 1;
    if (step_y < 1)
      step_y = 1;

    if (use_max) {
      unsigned max_r = 0, max_g = 0, max_b = 0;
      for (int y = sy0; y < sy1; y += step_y) {
        for (int x = sx0; x < sx1; x += step_x) {
          const unsigned char *px = p + (UINT)y * stride + (UINT)x * (UINT)bpp;
          const unsigned r = px[2], g = px[1], b = px[0];
          if (r > max_r)
            max_r = r;
          if (g > max_g)
            max_g = g;
          if (b > max_b)
            max_b = b;
        }
      }
      unsigned tr = max_r, tg = max_g, tb = max_b;
      if (tr < (unsigned)dark && tg < (unsigned)dark && tb < (unsigned)dark) {
        tr = 0;
        tg = 0;
        tb = 0;
      }
      out_rgb[i][0] = (unsigned char)tr;
      out_rgb[i][1] = (unsigned char)tg;
      out_rgb[i][2] = (unsigned char)tb;
    } else {
      unsigned long long sum_r = 0, sum_g = 0, sum_b = 0;
      int count = 0;
      for (int y = sy0; y < sy1; y += step_y) {
        for (int x = sx0; x < sx1; x += step_x) {
          const unsigned char *px = p + (UINT)y * stride + (UINT)x * (UINT)bpp;
          sum_r += px[2];
          sum_g += px[1];
          sum_b += px[0];
          ++count;
        }
      }
      unsigned tr = 0, tg = 0, tb = 0;
      if (count > 0) {
        tr = (unsigned)(sum_r / (unsigned long long)count);
        tg = (unsigned)(sum_g / (unsigned long long)count);
        tb = (unsigned)(sum_b / (unsigned long long)count);
      }
      if (tr < (unsigned)dark && tg < (unsigned)dark && tb < (unsigned)dark) {
        tr = 0;
        tg = 0;
        tb = 0;
      }
      out_rgb[i][0] = (unsigned char)tr;
      out_rgb[i][1] = (unsigned char)tg;
      out_rgb[i][2] = (unsigned char)tb;
    }
  }

  g_context->Unmap(g_staging, 0);
  g_duplication->ReleaseFrame();
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
}

bool dxgi_is_ready() { return g_device != nullptr && g_duplication != nullptr; }