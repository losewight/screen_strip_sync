// 必须先于 windows.h
#include <winsock2.h>
#include <ws2tcpip.h>

#include "config_clamp.h"
#include "config_store.h"
#include "ipc_internal.h"
#include "ipc_loop.h"
#include "letterbox_detect.h"
#include "light_engine.h"
#include "subtitle_detect.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// 解析 "full|linear lo,hi"；成功写 mode('f'|'l')/lo/hi 并返回 true。
static bool parse_brightness_arg(const char *p, char *mode, int *lo, int *hi) {
  if (!p || !mode || !lo || !hi)
    return false;
  while (*p == ' ' || *p == '\t')
    ++p;
  char word[16] = {};
  int wi = 0;
  while (*p && *p != ' ' && *p != '\t' && wi + 1 < (int)sizeof(word))
    word[wi++] = *p++;
  word[wi] = '\0';
  while (*p == ' ' || *p == '\t')
    ++p;
  if (strcmp(word, "linear") == 0)
    *mode = 'l';
  else if (strcmp(word, "full") == 0)
    *mode = 'f';
  else
    return false;
  char *end = nullptr;
  long a = strtol(p, &end, 10);
  if (end == p || *end != ',')
    return false;
  p = end + 1;
  long b = strtol(p, &end, 10);
  if (end == p)
    return false;
  while (*end == ' ' || *end == '\t')
    ++end;
  if (*end != '\0')
    return false;
  *lo = (int)a;
  *hi = (int)b;
  return true;
}

// 匹配并处理配置类 set 命令；未匹配返回 false，由 dispatch_line 继续。
bool try_dispatch_set(const char *line, HANDLE *serial, SOCKET client) {
  if (strncmp(line, "set alpha ", 10) == 0) {
    const char *p = line + 10;
    char *end = nullptr;
    float v = strtof(p, &end);
    if (end != p) {
      while (*end == ' ' || *end == '\t')
        ++end;
    }
    if (end == p || *end != '\0') {
      printf("bad set alpha: [%s]\n", p);
    } else {
      engine_set_alpha(v);
      config_set_ema_alpha(v);
      // 为什么：仅 clamp 纠偏才回推；UI 已乐观采纳合法值时不回声
      HelperConfig after{};
      config_copy(&after);
      if (fabsf(after.emaAlpha - v) > 0.0005f)
        ipc_push_config_snapshot();
      printf("cmd=set alpha\n");
    }
    return true;
  }
  if (strncmp(line, "set near_black ", 15) == 0) {
    const char *p = line + 15;
    char *end = nullptr;
    long v = strtol(p, &end, 10);
    if (end != p) {
      while (*end == ' ' || *end == '\t')
        ++end;
    }
    if (end == p || *end != '\0') {
      printf("bad set near_black: [%s]\n", p);
    } else {
      engine_set_near_black((int)v);
      config_set_near_black((int)v);
      HelperConfig after{};
      config_copy(&after);
      if (after.nearBlack != (int)v)
        ipc_push_config_snapshot();
      printf("cmd=set near_black\n");
    }
    return true;
  }
  if (strncmp(line, "set blur ", 9) == 0) {
    const char *p = line + 9;
    char *end = nullptr;
    long v = strtol(p, &end, 10);
    if (end != p) {
      while (*end == ' ' || *end == '\t')
        ++end;
    }
    if (end == p || *end != '\0') {
      printf("bad set blur: [%s]\n", p);
    } else {
      engine_set_blur((int)v);
      config_set_blur((int)v);
      HelperConfig after{};
      config_copy(&after);
      if (after.blurStep != (int)v)
        ipc_push_config_snapshot();
      printf("cmd=set blur\n");
    }
    return true;
  }
  if (strncmp(line, "set saturation ", 15) == 0) {
    const char *p = line + 15;
    char *end = nullptr;
    float v = strtof(p, &end);
    if (end != p) {
      while (*end == ' ' || *end == '\t')
        ++end;
    }
    if (end == p || *end != '\0') {
      printf("bad set saturation: [%s]\n", p);
    } else {
      engine_set_saturation(v);
      config_set_saturation(v);
      HelperConfig after{};
      config_copy(&after);
      if (fabsf(after.saturation - v) > 0.0005f)
        ipc_push_config_snapshot();
      printf("cmd=set saturation\n");
    }
    return true;
  }
  if (strncmp(line, "set brightness ", 15) == 0) {
    const char *p = line + 15;
    char mode = 'f';
    int lo = 0, hi = 0;
    if (!parse_brightness_arg(p, &mode, &lo, &hi)) {
      printf("bad set brightness: [%s]\n", p);
    } else {
      engine_set_brightness(mode, lo, hi);
      config_set_brightness(mode, lo, hi);
      HelperConfig after{};
      config_copy(&after);
      int clo = lo, chi = hi;
      clamp_brightness_range(&clo, &chi);
      if (after.brightnessMode != clamp_brightness_mode(mode) ||
          after.brightnessLo != clo || after.brightnessHi != chi)
        ipc_push_config_snapshot();
      printf("cmd=set brightness\n");
    }
    return true;
  }
  if (strncmp(line, "set region_brightness ", 22) == 0) {
    const char *p = line + 22;
    char mode = 'f';
    int lo = 0, hi = 0;
    if (!parse_brightness_arg(p, &mode, &lo, &hi)) {
      printf("bad set region_brightness: [%s]\n", p);
    } else {
      engine_set_region_brightness(mode, lo, hi);
      config_set_region_brightness(mode, lo, hi);
      HelperConfig after{};
      config_copy(&after);
      int clo = lo, chi = hi;
      clamp_brightness_range(&clo, &chi);
      if (after.regionBrightnessMode != clamp_brightness_mode(mode) ||
          after.regionBrightnessLo != clo || after.regionBrightnessHi != chi)
        ipc_push_config_snapshot();
      printf("cmd=set region_brightness\n");
    }
    return true;
  }
  if (strncmp(line, "set saturation_algo ", 20) == 0) {
    const char *p = line + 20;
    while (*p == ' ' || *p == '\t')
      ++p;
    char algo = 0;
    if (strcmp(p, "luma") == 0)
      algo = 'l';
    else if (strcmp(p, "neutral") == 0)
      algo = 'n';
    if (algo == 0) {
      printf("bad set saturation_algo: [%s]\n", p);
    } else {
      // 引擎侧算法已固定为 neutral；仅落盘配置供 UI 回读
      config_set_saturation_algo(algo);
      HelperConfig after{};
      config_copy(&after);
      if (after.saturationAlgo != algo)
        ipc_push_config_snapshot();
      printf("cmd=set saturation_algo\n");
    }
    return true;
  }
  if (strncmp(line, "set sample_algo ", 16) == 0) {
    const char *p = line + 16;
    while (*p == ' ' || *p == '\t')
      ++p;
    char algo = 0;
    if (strcmp(p, "rms") == 0)
      algo = 'r';
    else if (strcmp(p, "mean") == 0)
      algo = 'm';
    if (algo == 0) {
      printf("bad set sample_algo: [%s]\n", p);
    } else {
      engine_set_sample_algo(algo);
      config_set_sample_algo(algo);
      HelperConfig after{};
      config_copy(&after);
      if (after.sampleAlgo != algo)
        ipc_push_config_snapshot();
      printf("cmd=set sample_algo\n");
    }
    return true;
  }
  if (strncmp(line, "set near_black_luma ", 20) == 0) {
    const char *p = line + 20;
    while (*p == ' ' || *p == '\t')
      ++p;
    char mode = 0;
    if (strcmp(p, "rec601") == 0)
      mode = '6';
    else if (strcmp(p, "mean") == 0)
      mode = 'a';
    if (mode == 0) {
      printf("bad set near_black_luma: [%s]\n", p);
    } else {
      engine_set_near_black_luma(mode);
      config_set_near_black_luma(mode);
      HelperConfig after{};
      config_copy(&after);
      if (after.nearBlackLuma != mode)
        ipc_push_config_snapshot();
      printf("cmd=set near_black_luma\n");
    }
    return true;
  }
  if (strncmp(line, "set mode ", 9) == 0) {
    const char *p = line + 9;
    while (*p == ' ' || *p == '\t')
      ++p;
    char c = *p;
    char norm = 0;
    if (c == 'a' || c == 'A')
      norm = 'a';
    else if (c == 'b' || c == 'B')
      norm = 'b';
    if (norm != 0) {
      const char *rest = p + 1;
      while (*rest == ' ' || *rest == '\t')
        ++rest;
      if (*rest == '\0') {
        // 亮度方案已废弃；仅落盘防配置丢失，引擎不再读 mode
        config_set_mode(norm);
        printf("cmd=set mode %c\n", norm);
        return true;
      }
    }
    printf("bad set mode: [%s]\n", p);
    return true;
  }
  if (strncmp(line, "set com ", 8) == 0) {
    const char *p = line + 8;
    if (!engine_set_com(p)) {
      printf("bad set com: [%s]\n", p);
    } else {
      char norm[16];
      engine_get_com(norm, sizeof(norm));
      config_set_com(norm);
      // 为什么：仅规范化结果与请求字面不同才纠偏（大小写相同则不算）
      if (_stricmp(p, norm) != 0)
        ipc_push_config_snapshot();
      printf("cmd=set com\n");
    }
    return true;
  }
  if (strncmp(line, "set capture_output ", 19) == 0) {
    const char *p = line + 19;
    while (*p == ' ' || *p == '\t')
      ++p;
    if (*p == '\0') {
      printf("bad set capture_output: empty\n");
    } else {
      cmd_set_capture_output(p, serial, client);
    }
    return true;
  }
  if (strncmp(line, "set sleep_sync ", 15) == 0) {
    const char *p = line + 15;
    while (*p == ' ' || *p == '\t')
      ++p;
    if ((*p == '0' || *p == '1') && p[1] == '\0') {
      config_set_sleep_sync(*p == '1'); // 内含 helper_set_sleep_sync
      printf("cmd=set sleep_sync %c\n", *p);
    } else {
      printf("bad set sleep_sync: [%s]\n", p);
    }
    return true;
  }
  if (strncmp(line, "set screen_off_sync ", 20) == 0) {
    const char *p = line + 20;
    while (*p == ' ' || *p == '\t')
      ++p;
    if ((*p == '0' || *p == '1') && p[1] == '\0') {
      config_set_screen_off_sync(*p == '1');
      printf("cmd=set screen_off_sync %c\n", *p);
    } else {
      printf("bad set screen_off_sync: [%s]\n", p);
    }
    return true;
  }
  if (strncmp(line, "set shutdown_off ", 17) == 0) {
    const char *p = line + 17;
    while (*p == ' ' || *p == '\t')
      ++p;
    if ((*p == '0' || *p == '1') && p[1] == '\0') {
      config_set_shutdown_off(*p == '1');
      printf("cmd=set shutdown_off %c\n", *p);
    } else {
      printf("bad set shutdown_off: [%s]\n", p);
    }
    return true;
  }
  if (strncmp(line, "set autostart ", 14) == 0) {
    const char *p = line + 14;
    while (*p == ' ' || *p == '\t')
      ++p;
    if ((*p == '0' || *p == '1') && p[1] == '\0') {
      config_set_autostart(*p == '1');
      printf("cmd=set autostart %c\n", *p);
    } else {
      printf("bad set autostart: [%s]\n", p);
    }
    return true;
  }
  if (strcmp(line, "set map default") == 0) {
    engine_clear_map();
    config_clear_map();
    printf("cmd=set map default\n");
    return true;
  }
  if (strncmp(line, "set map ", 8) == 0) {
    const char *p = line + 8;
    if (!engine_set_map_from_ipc(p)) {
      printf("bad set map: [%s]\n", p);
    } else {
      config_sync_map_from_engine();
      printf("cmd=set map\n");
    }
    return true;
  }
  if (strncmp(line, "set region_algo ", 16) == 0) {
    const char *p = line + 16;
    while (*p == ' ' || *p == '\t')
      ++p;
    char algo = 0;
    if (strcmp(p, "mean") == 0)
      algo = 'm';
    else if (strcmp(p, "max") == 0)
      algo = 'x';
    if (algo == 0) {
      printf("bad set region_algo: [%s]\n", p);
    } else {
      engine_set_region_algo(algo);
      config_set_region_algo(algo);
      HelperConfig after{};
      config_copy(&after);
      if (after.regionAlgo != algo)
        ipc_push_config_snapshot();
      printf("cmd=set region_algo\n");
    }
    return true;
  }
  if (strncmp(line, "set region_blur ", 16) == 0) {
    const char *p = line + 16;
    char *end = nullptr;
    long v = strtol(p, &end, 10);
    if (end != p) {
      while (*end == ' ' || *end == '\t')
        ++end;
    }
    if (end == p || *end != '\0') {
      printf("bad set region_blur: [%s]\n", p);
    } else {
      engine_set_region_blur((int)v);
      config_set_region_blur((int)v);
      HelperConfig after{};
      config_copy(&after);
      if (after.regionBlur != (int)v)
        ipc_push_config_snapshot();
      printf("cmd=set region_blur\n");
    }
    return true;
  }
  if (strncmp(line, "set region_smooth ", 18) == 0) {
    const char *p = line + 18;
    char *end = nullptr;
    float v = strtof(p, &end);
    if (end != p) {
      while (*end == ' ' || *end == '\t')
        ++end;
    }
    if (end == p || *end != '\0') {
      printf("bad set region_smooth: [%s]\n", p);
    } else {
      engine_set_region_smooth(v);
      config_set_region_smooth(v);
      HelperConfig after{};
      config_copy(&after);
      if (fabsf(after.regionSmooth - v) > 0.0005f)
        ipc_push_config_snapshot();
      printf("cmd=set region_smooth\n");
    }
    return true;
  }
  if (strncmp(line, "set region_dark ", 16) == 0) {
    const char *p = line + 16;
    char *end = nullptr;
    long v = strtol(p, &end, 10);
    if (end != p) {
      while (*end == ' ' || *end == '\t')
        ++end;
    }
    if (end == p || *end != '\0') {
      printf("bad set region_dark: [%s]\n", p);
    } else {
      engine_set_region_dark((int)v);
      config_set_region_dark((int)v);
      HelperConfig after{};
      config_copy(&after);
      if (after.regionDark != (int)v)
        ipc_push_config_snapshot();
      printf("cmd=set region_dark\n");
    }
    return true;
  }
  if (strncmp(line, "set last_custom_solid ", 22) == 0) {
    const char *p = line + 22;
    if (!is_rrggbb(p)) {
      printf("bad set last_custom_solid: [%s]\n", p);
    } else if (!config_set_last_custom_solid(p)) {
      printf("bad set last_custom_solid: [%s]\n", p);
    } else {
      // 为什么：大小写纠偏才回推（存盘小写）；合法小写 UI 已乐观采纳
      HelperConfig after{};
      config_copy(&after);
      if (strcmp(after.lastCustomSolid, p) != 0)
        ipc_push_config_snapshot();
      printf("cmd=set last_custom_solid\n");
    }
    return true;
  }
  if (strncmp(line, "set wall_comp ", 14) == 0) {
    const char *p = line + 14;
    while (*p == ' ' || *p == '\t')
      ++p;
    if ((*p == '0' || *p == '1') && p[1] == '\0') {
      config_set_wall_comp(*p == '1');
      printf("cmd=set wall_comp %c\n", *p);
    } else {
      printf("bad set wall_comp: [%s]\n", p);
    }
    return true;
  }
  if (strncmp(line, "set letterbox_detect ", 21) == 0) {
    const char *p = line + 21;
    while (*p == ' ' || *p == '\t')
      ++p;
    if ((*p == '0' || *p == '1') && p[1] == '\0') {
      config_set_letterbox_detect(*p == '1');
      printf("cmd=set letterbox_detect %c\n", *p);
    } else {
      printf("bad set letterbox_detect: [%s]\n", p);
    }
    return true;
  }
  // 校准蒙版期间硬关；不落盘。退出校准后由 start 或 letterbox_hold 0 解除。
  if (strncmp(line, "set letterbox_hold ", 19) == 0) {
    const char *p = line + 19;
    while (*p == ' ' || *p == '\t')
      ++p;
    if ((*p == '0' || *p == '1') && p[1] == '\0') {
      letterbox_set_hard_disable(*p == '1');
      subtitle_set_hard_disable(*p == '1');
      printf("cmd=set letterbox_hold %c\n", *p);
    } else {
      printf("bad set letterbox_hold: [%s]\n", p);
    }
    return true;
  }
  if (strncmp(line, "set subtitle_detect ", 20) == 0) {
    const char *p = line + 20;
    while (*p == ' ' || *p == '\t')
      ++p;
    if ((*p == '0' || *p == '1') && p[1] == '\0') {
      config_set_subtitle_detect(*p == '1');
      printf("cmd=set subtitle_detect %c\n", *p);
    } else {
      printf("bad set subtitle_detect: [%s]\n", p);
    }
    return true;
  }
  if (strncmp(line, "set wall_color ", 15) == 0) {
    const char *p = line + 15;
    while (*p == ' ' || *p == '\t')
      ++p;
    if (p[0] == '\0' || strcmp(p, "clear") == 0) {
      if (!config_set_wall_color(""))
        printf("bad set wall_color: (empty)\n");
      else
        printf("cmd=set wall_color (cleared)\n");
    } else if (!is_rrggbb(p)) {
      printf("bad set wall_color: [%s]\n", p);
    } else if (!config_set_wall_color(p)) {
      printf("bad set wall_color: [%s]\n", p);
    } else {
      HelperConfig after{};
      config_copy(&after);
      if (strcmp(after.wallColor, p) != 0)
        ipc_push_config_snapshot();
      printf("cmd=set wall_color\n");
    }
    return true;
  }
  if (strncmp(line, "set region_bbox ", 16) == 0) {
    const char *p = line + 16;
    int l = 0, t = 0, w = 0, h = 0;
    char *end = nullptr;
    l = (int)strtol(p, &end, 10);
    if (end == p || *end != ',') {
      printf("bad set region_bbox: [%s]\n", p);
      return true;
    }
    p = end + 1;
    t = (int)strtol(p, &end, 10);
    if (end == p || *end != ',') {
      printf("bad set region_bbox: [%s]\n", line + 16);
      return true;
    }
    p = end + 1;
    w = (int)strtol(p, &end, 10);
    if (end == p || *end != ',') {
      printf("bad set region_bbox: [%s]\n", line + 16);
      return true;
    }
    p = end + 1;
    h = (int)strtol(p, &end, 10);
    if (end == p) {
      printf("bad set region_bbox: [%s]\n", line + 16);
      return true;
    }
    while (*end == ' ' || *end == '\t')
      ++end;
    if (*end != '\0') {
      printf("bad set region_bbox: [%s]\n", line + 16);
      return true;
    }
    if (!config_set_region_bbox(l, t, w, h)) {
      printf("bad set region_bbox: [%s]\n", line + 16);
    } else {
      HelperConfig after{};
      config_copy(&after);
      engine_set_region_bbox(after.regionBBox.l, after.regionBBox.t,
                             after.regionBBox.w, after.regionBBox.h);
      if (after.regionBBox.l != l || after.regionBBox.t != t ||
          after.regionBBox.w != w || after.regionBBox.h != h)
        ipc_push_config_snapshot();
      printf("cmd=set region_bbox\n");
    }
    return true;
  }
  return false;
}
