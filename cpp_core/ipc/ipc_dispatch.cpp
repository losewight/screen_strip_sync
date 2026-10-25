// 必须先于 windows.h
#include <winsock2.h>
#include <ws2tcpip.h>

#include "config_store.h"
#include "helper_lifecycle.h"
#include "helper_log.h"
#include "ipc_internal.h"
#include "ipc_loop.h"
#include "letterbox_detect.h"
#include "light_engine.h"
#include "serial_port.h"
#include "subtitle_detect.h"

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

DispatchResult dispatch_line(const char *line, HANDLE *serial, SOCKET client) {
  if (strcmp(line, "quit") == 0) {
    // 为什么：关窗走 bye；quit 才关后台服务。先通知 UI，再让 ipc_run 收尾。
    ipc_push_ui_quit();
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
    letterbox_set_hard_disable(false);
    letterbox_reset();
    subtitle_set_hard_disable(false);
    subtitle_reset();
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
    letterbox_set_hard_disable(false);
    letterbox_reset();
    subtitle_set_hard_disable(false);
    subtitle_reset();
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
  if (try_dispatch_set(line, serial, client))
    return DispatchResult::Continue;
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
      letterbox_set_hard_disable(true);
      subtitle_set_hard_disable(true);
      engine_stop();
      send_highlight(*serial, (int)v);
    }
    return DispatchResult::Continue;
  }
  if (strcmp(line, "reconnect") == 0) {
    // 为什么：串口重试可堵十几秒；丢到 boot 同槽后台线程，IPC 立即返回
    if (helper_is_shutting_down())
      return DispatchResult::Continue;
    send_status(client, "reconnecting");
    helper_reconnect_serial_async();
    return DispatchResult::Continue;
  }
  printf("unknown cmd: [%s]\n", line);
  return DispatchResult::Continue;
}
