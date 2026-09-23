#include "dxgi_capture.h"

#include "dxgi_mapped.h"
#include "letterbox_detect.h"

// 屏幕氛围 region 采样：与 map 路径正交；抓帧走 dxgi_map_desktop。
DxgiErr dxgi_grab_and_sample_region(UINT timeout_ms, int l, int t, int w, int h,
                                    char algo, int blur, int dark,
                                    unsigned char out_rgb[10][3]) {
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

  DxgiMappedFrame frame{};
  DxgiErr e = dxgi_map_desktop(timeout_ms, &frame);
  if (e != DxgiErr::Ok)
    return e;

  if (frame.bpp <= 0 || frame.desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM) {
    // 为什么：当 Ok+全黑会让引擎当真帧去做 EMA，锁屏/HDR 会把灯慢慢拖黑；与 map 一样 skip
    dxgi_unmap_desktop();
    return DxgiErr::AcquireFailed;
  }

  const unsigned char *p = frame.pixels;
  const UINT stride = frame.stride;
  const int bpp = frame.bpp;
  const int screen_w = (int)frame.desc.Width;
  const int screen_h = (int)frame.desc.Height;

  letterbox_process_bgra(p, screen_w, screen_h, (int)stride, bpp);

  int x0 = (l * screen_w) / 100;
  int x1 = ((l + w) * screen_w) / 100;
  // bbox 竖向百分比按内容窗等比映射（与 map 校准框同语义）
  int y0 = 0, y1 = 0;
  letterbox_map_y_range((float)t / 100.f, (float)(t + h) / 100.f, screen_h,
                        &y0, &y1);
  if (x0 < 0)
    x0 = 0;
  if (x1 > screen_w)
    x1 = screen_w;
  if (x1 <= x0)
    x1 = x0 + 1;
  if (x1 > screen_w)
    x1 = screen_w;
  if (y1 > screen_h)
    y1 = screen_h;

  const int region_w = x1 - x0;

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

  dxgi_unmap_desktop();
  return DxgiErr::Ok;
}
