#include "dxgi_capture.h"

#include "dxgi_mapped.h"
#include "helper_log.h"
#include "letterbox_detect.h"
#include "pixel_reader.h"
#include "subtitle_detect.h"

#include <atomic>
#include <cmath>
#include <d3d11.h>

// 为什么：IPC 写、采样热路径只 load；与 Flutter AppConfig 对齐
static std::atomic<int> g_near_black{30}; // 0..64；默认与 HelperConfig 对齐
static std::atomic<int> g_blur_step{0};  // 0..8
static std::atomic<char> g_sample_algo{'m'}; // 固定 mean；'r'=rms 保留接口兼容
// 近黑亮度：'6'=Rec.601（默认），'a'=(R+G+B)/3
static std::atomic<char> g_near_black_luma{'6'};

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
    int lb_top = 0, lb_bottom = 0;
    letterbox_get_inset(&lb_top, &lb_bottom);
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
      const int h_orig = y1 - y0;
      if (y1 > y_limit)
        y1 = y_limit;
      if (y1 <= y0) {
        // 完全裁切：均分拓回原高；下沿不够的余量补到上沿
        int cy0 = y_limit;
        int cy1 = y_limit;
        int need = h_orig;
        if (need < 1)
          need = 1;
        int down = need / 2;
        int up = need - down;
        const int room_down = y_limit - cy1;
        if (down > room_down) {
          up += down - room_down;
          down = room_down;
        }
        cy1 += down;
        cy0 -= up;
        if (cy0 < lb_top)
          cy0 = lb_top;
        y0 = cy0;
        y1 = cy1;
        if (y1 > y_limit)
          y1 = y_limit;
        if (y1 <= y0) {
          out_rgb[i][0] = 0;
          out_rgb[i][1] = 0;
          out_rgb[i][2] = 0;
          continue;
        }
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
    const int hdr =
        fmt == (unsigned)DXGI_FORMAT_R16G16B16A16_FLOAT ? 1 : 0;
    static const char kKeySampleMs[] = "dxgi.sample.ms";
    helper_log_rate(kKeySampleMs, 5000,
                    "sample %.2fms format=%u blur=%d hdr=%d\n", ms,
                    (unsigned)fmt, g_blur_step.load(), hdr);
  }

  dxgi_unmap_desktop();
  return DxgiErr::Ok;
}
