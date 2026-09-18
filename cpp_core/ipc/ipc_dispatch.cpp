// 必须先于 windows.h
#include <winsock2.h>
#include <ws2tcpip.h>

#include "config_clamp.h"
#include "config_store.h"
#include "dxgi_capture.h"
#include "helper_lifecycle.h"
#include "helper_log.h"
#include "ipc_internal.h"
#include "ipc_loop.h"
#include "light_engine.h"
#include "serial_port.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

bool is_rrggbb(const char *s) {
  if (s == nullptr || strlen(s) != 6)
    return false;
  for (int i = 0; i < 6; ++i) {
    char c = s[i];
    bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F');
    if (!ok)
      return false;
  }
  return true;
}

// 为什么：无 COM 时常驻；控灯命令短路并告知 UI，避免 WriteFile(INVALID) 刷屏
static bool require_serial(HANDLE *serial, SOCKET client, const char *cmd) {
  if (serial != nullptr && *serial != INVALID_HANDLE_VALUE)
    return true;
  printf("cmd=%s skipped: no serial\n", cmd);
  send_status(client, "reconnect_fail");
  return false;
}

// 换屏：停引擎 → 拆 DXGI → 按新名 init → 用实际选中的名字落盘 → 按意图恢复。
// 不动串口。失败回退 auto 再试一次，并把真实值推回 UI。
static void cmd_set_capture_output(const char *wanted, HANDLE *serial,
                                   SOCKET client) {
  char clamped[64];
  clamp_capture_output(wanted, clamped, (int)sizeof(clamped));
  printf("cmd=set capture_output [%s]\n", clamped);

  engine_stop();
  dxgi_set_capture_output(clamped);
  dxgi_shutdown();
  DxgiErr e = dxgi_init();
  if (e != DxgiErr::Ok) {
    printf("set capture_output: init failed %d, retry auto\n", (int)e);
    dxgi_set_capture_output("auto");
    dxgi_shutdown();
    e = dxgi_init();
  }

  if (e != DxgiErr::Ok) {
    printf("set capture_output: auto also failed %d\n", (int)e);
    config_set_capture_output("auto");
    ipc_push_config_snapshot();
    push_runtime_status(client, false);
    return;
  }

  CaptureOutputInfo cur{};
  const char *persist = "auto";
  if (dxgi_current_output(&cur) && cur.device_name[0] != '\0')
    persist = cur.device_name;
  config_set_capture_output(persist);

  DisplayIntent intent = engine_get_display_intent();
  if (intent.kind == DisplayIntentKind::Idle) {
    HelperConfig c{};
    config_copy(&c);
    parse_last_scene(c.lastScene, &intent);
  }
  if (serial != nullptr && *serial != INVALID_HANDLE_VALUE)
    apply_display_intent(*serial, intent);

  // 为什么：auto / 不存在的名字都会被纠成真实 DeviceName，UI 必须立刻看到
  ipc_push_config_snapshot();
  push_runtime_status(client, false);
}

DispatchResult dispatch_line(const char *line, HANDLE *serial, SOCKET client) {
  if (strcmp(line, "quit") == 0) {
    // 为什么：关窗走 bye；quit 才关后台服务
    engine_stop();
    printf("cmd=quit\n");
    return DispatchResult::ShutdownService;
  }
  if (strcmp(line, "bye") == 0) {
    printf("cmd=bye\n");
    return DispatchResult::DropClient;
  }
  if (strcmp(line, "sync") == 0) {
    printf("cmd=sync\n");
    push_config_snapshot(client);
    return DispatchResult::Continue;
  }
  // 为什么：开源诊断导出前打标记，便于对齐 helper.log 尾部与导出时刻
  if (strcmp(line, "diag_mark") == 0) {
    printf("=== diag export ===\n");
    helper_log_flush();
    return DispatchResult::Continue;
  }
  if (strcmp(line, "off") == 0) {
    if (!require_serial(serial, client, "off"))
      return DispatchResult::Continue;
    engine_stop();
    printf("cmd=off\n");
    power_off(*serial);
    return DispatchResult::Continue;
  }
  // 为什么：UI「关灯」熄画面不掉电；黑帧走 send_solid，帧间隔 ≥50ms
  if (strcmp(line, "soft_off") == 0) {
    if (!require_serial(serial, client, "soft_off"))
      return DispatchResult::Continue;
    engine_stop();
    engine_set_intent_soft_off();
    config_set_last_scene("off");
    printf("cmd=soft_off\n");
    send_solid(*serial, "000000");
    return DispatchResult::Continue;
  }
  if (strcmp(line, "start") == 0) {
    if (!require_serial(serial, client, "start"))
      return DispatchResult::Continue;
    engine_start(*serial);
    engine_set_intent_engine();
    config_set_last_scene("engine");
    printf("cmd=start\n");
    return DispatchResult::Continue;
  }
  // 屏幕氛围：与 start（map）正交；共用 stop/soft_off
  if (strcmp(line, "start_region") == 0) {
    if (!require_serial(serial, client, "start_region"))
      return DispatchResult::Continue;
    engine_start_region(*serial);
    engine_set_intent_region();
    config_set_last_scene("region");
    printf("cmd=start_region\n");
    return DispatchResult::Continue;
  }
  if (strcmp(line, "stop") == 0) {
    engine_stop();
    engine_set_intent_idle();
    config_set_last_scene("idle");
    printf("cmd=stop\n");
    return DispatchResult::Continue;
  }
  if (strncmp(line, "solid ", 6) == 0) {
    const char *color = line + 6;
    if (!is_rrggbb(color)) {
      printf("bad solid color: [%s]\n", color);
    } else if (!require_serial(serial, client, "solid")) {
      // 已回推 reconnect_fail
    } else {
      printf("cmd=solid color=%s\n", color);
      engine_stop();
      engine_set_intent_solid(color);
      send_solid(*serial, color);
      char scene[32];
      snprintf(scene, sizeof(scene), "solid %s", color);
      config_set_last_scene(scene);
    }
    return DispatchResult::Continue;
  }
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
        engine_set_mode(norm);
        config_set_mode(norm);
        printf("cmd=set mode %c\n", norm);
        return DispatchResult::Continue;
      }
    }
    printf("bad set mode: [%s]\n", p);
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
  }
  if (strncmp(line, "highlight ", 10) == 0) {
    const char *p = line + 10;
    char *end = nullptr;
    long v = strtol(p, &end, 10);
    if (end == p || *end != '\0' || v < 0 || v >= kSegmentCount) {
      printf("bad highlight: [%s]\n", p);
    } else if (!require_serial(serial, client, "highlight")) {
      // 已回推 reconnect_fail
    } else {
      printf("cmd=highlight %ld\n", v);
      // 为什么：worker 仍跑时高亮会与 RGB 帧 0ms 连写，校准段会被下一帧冲掉
      engine_stop();
      send_highlight(*serial, (int)v);
    }
    return DispatchResult::Continue;
  }
  if (strcmp(line, "set map default") == 0) {
    engine_clear_map();
    config_clear_map();
    printf("cmd=set map default\n");
    return DispatchResult::Continue;
  }
  if (strncmp(line, "set map ", 8) == 0) {
    const char *p = line + 8;
    if (!engine_set_map_from_ipc(p)) {
      printf("bad set map: [%s]\n", p);
    } else {
      config_sync_map_from_engine();
      printf("cmd=set map\n");
    }
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
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
    return DispatchResult::Continue;
  }
  if (strncmp(line, "set wall_color ", 15) == 0) {
    const char *p = line + 15;
    while (*p == ' ' || *p == '\t')
      ++p;
    if (p[0] == '\0') {
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
    return DispatchResult::Continue;
  }
  if (strncmp(line, "set region_bbox ", 16) == 0) {
    const char *p = line + 16;
    int l = 0, t = 0, w = 0, h = 0;
    char *end = nullptr;
    l = (int)strtol(p, &end, 10);
    if (end == p || *end != ',') {
      printf("bad set region_bbox: [%s]\n", p);
      return DispatchResult::Continue;
    }
    p = end + 1;
    t = (int)strtol(p, &end, 10);
    if (end == p || *end != ',') {
      printf("bad set region_bbox: [%s]\n", line + 16);
      return DispatchResult::Continue;
    }
    p = end + 1;
    w = (int)strtol(p, &end, 10);
    if (end == p || *end != ',') {
      printf("bad set region_bbox: [%s]\n", line + 16);
      return DispatchResult::Continue;
    }
    p = end + 1;
    h = (int)strtol(p, &end, 10);
    if (end == p) {
      printf("bad set region_bbox: [%s]\n", line + 16);
      return DispatchResult::Continue;
    }
    while (*end == ' ' || *end == '\t')
      ++end;
    if (*end != '\0') {
      printf("bad set region_bbox: [%s]\n", line + 16);
      return DispatchResult::Continue;
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
    return DispatchResult::Continue;
  }
  if (strcmp(line, "reconnect") == 0) {
    engine_stop();
    send_status(client, "reconnecting");
    if (*serial != INVALID_HANDLE_VALUE) {
      close_com(*serial);
      *serial = INVALID_HANDLE_VALUE;
    }
    // 为什么：休眠 teardown 关过 DXGI；重连后追色要能抓屏
    engine_ensure_dxgi();
    HANDLE neu = INVALID_HANDLE_VALUE;
    bool ok = false;
    for (int i = 1; i <= 10; ++i) {
      if (try_serial_ready(&neu)) {
        ok = true;
        printf("reconnect try %d ok\n", i);
        break;
      }
      printf("reconnect try %d failed\n", i);
      Sleep(500);
    }
    if (ok) {
      *serial = neu;
      helper_note_resources_ready();
      printf("cmd=reconnect ok\n");
      char com[16];
      engine_get_com(com, sizeof(com));
      config_set_last_connected_com(com);
      config_set_serial_configured(true);
      DisplayIntent intent = engine_get_display_intent();
      if (intent.kind == DisplayIntentKind::Idle) {
        HelperConfig c{};
        config_copy(&c);
        parse_last_scene(c.lastScene, &intent);
      }
      apply_display_intent(*serial, intent);
      send_status(client, "reconnect_ok");
      push_runtime_status(client, true);
      ipc_push_config_snapshot();
    } else {
      printf("cmd=reconnect failed\n");
      engine_set_intent_idle();
      send_status(client, "reconnect_fail");
      send_engine_status(client);
      send_display_status(client);
    }
    return DispatchResult::Continue;
  }
  printf("unknown cmd: [%s]\n", line);
  return DispatchResult::Continue;
}
