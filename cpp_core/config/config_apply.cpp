#include "config_store_internal.h"

#include "config_clamp.h"
#include "dxgi_capture.h"
#include "helper_lifecycle.h"
#include "letterbox_detect.h"
#include "light_engine.h"
#include "subtitle_detect.h"
#include "wall_comp.h"

#include <cstdio>
#include <mutex>

void config_apply() {
  HelperConfig c;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    c = g_cfg;
  }

  engine_set_alpha(c.emaAlpha);
  engine_set_near_black(c.nearBlack);
  engine_set_blur(c.blurStep);
  engine_set_saturation(c.saturation);
  engine_set_brightness(c.brightnessMode, c.brightnessLo, c.brightnessHi);
  engine_set_sample_algo(c.sampleAlgo);
  engine_set_near_black_luma(c.nearBlackLuma);
  engine_set_region_algo(c.regionAlgo);
  engine_set_region_blur(c.regionBlur);
  engine_set_region_smooth(c.regionSmooth);
  engine_set_region_dark(c.regionDark);
  engine_set_region_brightness(c.regionBrightnessMode, c.regionBrightnessLo,
                               c.regionBrightnessHi);
  engine_set_region_bbox(c.regionBBox.l, c.regionBBox.t, c.regionBBox.w,
                         c.regionBBox.h);
  engine_set_wall_comp(c.wallCompEnabled);
  if (c.wallColor[0] != '\0')
    engine_set_wall_color(c.wallColor);
  else
    engine_clear_wall_color();
  letterbox_set_enabled(c.letterboxDetect);
  subtitle_set_enabled(c.subtitleDetect);
  // 为什么：必须在 dxgi_init 之前生效；ACCESS_LOST 重建读的是这份 wanted
  {
    char capture[64];
    clamp_capture_output(c.captureOutput, capture, (int)sizeof(capture));
    dxgi_set_capture_output(capture);
    std::lock_guard<std::mutex> lock(g_mu);
    snprintf(g_cfg.captureOutput, sizeof(g_cfg.captureOutput), "%s", capture);
  }
  if (!engine_set_com(c.comPort)) {
    printf("config_apply: bad com [%s], fallback COM10\n", c.comPort);
    engine_set_com("COM10");
    std::lock_guard<std::mutex> lock(g_mu);
    snprintf(g_cfg.comPort, sizeof(g_cfg.comPort), "COM10");
  } else {
    char norm[16];
    engine_get_com(norm, sizeof(norm));
    std::lock_guard<std::mutex> lock(g_mu);
    snprintf(g_cfg.comPort, sizeof(g_cfg.comPort), "%s", norm);
  }
  helper_set_sleep_sync(c.autoSleepSync);
  helper_set_screen_off_sync(c.screenOffSync);

  if (c.hasMap) {
    char payload[512];
    int n = 0;
    bool map_ok = true;
    for (int i = 0; i < kSegmentCount; ++i) {
      int x0 = (int)(c.map[i].x0 * 100.f + 0.5f);
      int y0 = (int)(c.map[i].y0 * 100.f + 0.5f);
      int x1 = (int)(c.map[i].x1 * 100.f + 0.5f);
      int y1 = (int)(c.map[i].y1 * 100.f + 0.5f);
      if (x0 < 0)
        x0 = 0;
      if (y0 < 0)
        y0 = 0;
      if (x1 > 100)
        x1 = 100;
      if (y1 > 100)
        y1 = 100;
      int w = snprintf(payload + n, sizeof(payload) - (size_t)n,
                       "%s%d,%d,%d,%d", (i == 0 ? "" : ";"), x0, y0, x1, y1);
      if (w < 0 || n + w >= (int)sizeof(payload)) {
        printf("config_apply: map payload overflow\n");
        map_ok = false;
        break;
      }
      n += w;
    }
    if (map_ok && !engine_set_map_from_ipc(payload)) {
      printf("config_apply: map reject, clear\n");
      map_ok = false;
    }
    if (!map_ok) {
      // 为什么：引擎已回退顶边均分；内存/磁盘若仍 hasMap，会双真相并写回毒表
      engine_clear_map();
      {
        std::lock_guard<std::mutex> lock(g_mu);
        g_cfg.hasMap = false;
        mark_dirty_unlocked();
      }
      ensure_saver_started();
    }
  } else {
    engine_clear_map();
  }
  printf("config_apply done\n");
}
