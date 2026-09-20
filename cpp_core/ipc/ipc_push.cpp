// 必须先于 windows.h
#include <winsock2.h>
#include <ws2tcpip.h>

#include "config_store.h"
#include "dxgi_capture.h"
#include "helper_lifecycle.h"
#include "ipc_internal.h"
#include "ipc_loop.h"
#include "light_engine.h"

#include <cstdarg>
#include <cstdio>
#include <cstring>

void send_raw(SOCKET client, const char *buf, int n) {
  if (n > 0 && client != INVALID_SOCKET)
    send(client, buf, n, 0);
}

void send_line(SOCKET client, const char *fmt, ...) {
  char buf[640];
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);
  if (n > 0 && n < (int)sizeof(buf))
    send_raw(client, buf, n);
}

void send_status(SOCKET client, const char *word) {
  send_line(client, "status %s\n", word);
}

void send_status_kv(SOCKET client, const char *key, const char *value) {
  send_line(client, "status %s %s\n", key, value);
}

void send_engine_status(SOCKET client) {
  send_status_kv(client, "engine", engine_is_running() ? "1" : "0");
}

void send_display_status(SOCKET client) {
  DisplayIntent intent = engine_get_display_intent();
  switch (intent.kind) {
  case DisplayIntentKind::Engine:
    send_status_kv(client, "display", "engine");
    break;
  case DisplayIntentKind::Region:
    send_status_kv(client, "display", "region");
    break;
  case DisplayIntentKind::Solid:
    send_status_kv(client, "display", "solid");
    break;
  case DisplayIntentKind::SoftOff:
    send_status_kv(client, "display", "soft_off");
    break;
  case DisplayIntentKind::Idle:
  default:
    send_status_kv(client, "display", "idle");
    break;
  }
}

static void send_capture_status(SOCKET client) {
  CaptureOutputInfo cur{};
  const bool has_cur = dxgi_current_output(&cur);
  if (has_cur) {
    const int w = cur.desktop.right - cur.desktop.left;
    const int h = cur.desktop.bottom - cur.desktop.top;
    if (cur.friendly_name[0])
      send_line(client, "status capture_output %s %dx%d %d,%d %s\n",
                cur.device_name, w, h, (int)cur.desktop.left,
                (int)cur.desktop.top, cur.friendly_name);
    else
      send_line(client, "status capture_output %s %dx%d %d,%d\n",
                cur.device_name, w, h, (int)cur.desktop.left,
                (int)cur.desktop.top);
  }

  CaptureOutputInfo list[16];
  const UINT n = dxgi_enum_outputs(list, 16);
  send_line(client, "status outputs %u\n", n);
  for (UINT i = 0; i < n; ++i) {
    const RECT &r = list[i].desktop;
    const int w = r.right - r.left;
    const int h = r.bottom - r.top;
    const int is_cur =
        (has_cur && std::strcmp(list[i].device_name, cur.device_name) == 0) ? 1
                                                                           : 0;
    if (list[i].friendly_name[0])
      send_line(client, "status output %u %s %dx%d %d,%d %d %d %s\n",
                list[i].index, list[i].device_name, w, h, (int)r.left,
                (int)r.top, list[i].is_primary ? 1 : 0, is_cur,
                list[i].friendly_name);
    else
      send_line(client, "status output %u %s %dx%d %d,%d %d %d\n",
                list[i].index, list[i].device_name, w, h, (int)r.left,
                (int)r.top, list[i].is_primary ? 1 : 0, is_cur);
  }
  printf("ipc: capture_output %s outputs=%u\n",
         has_cur ? cur.device_name : "(none)", n);
}

void push_runtime_status(SOCKET client, bool include_com) {
  if (include_com) {
    char com[16];
    engine_get_com(com, sizeof(com));
    send_status_kv(client, "com", com);
  }
  send_engine_status(client);
  send_display_status(client);
  send_capture_status(client);
}

static void format_scene(char *out, size_t cap) {
  DisplayIntent intent = engine_get_display_intent();
  switch (intent.kind) {
  case DisplayIntentKind::Engine:
    snprintf(out, cap, "engine");
    break;
  case DisplayIntentKind::Region:
    snprintf(out, cap, "region");
    break;
  case DisplayIntentKind::Solid:
    snprintf(out, cap, "solid %s", intent.solid);
    break;
  case DisplayIntentKind::SoftOff:
    snprintf(out, cap, "off");
    break;
  case DisplayIntentKind::Idle:
  default:
    snprintf(out, cap, "idle");
    break;
  }
}

void push_config_lines(SOCKET client) {
  HelperConfig c{};
  config_copy(&c);

  send_line(client, "cfg alpha %.2f\n", (double)c.emaAlpha);
  send_line(client, "cfg near_black %d\n", c.nearBlack);
  send_line(client, "cfg blur %d\n", c.blurStep);
  send_line(client, "cfg saturation %.2f\n", (double)c.saturation);
  send_line(client, "cfg mode %c\n", c.mode);
  send_line(client, "cfg com %s\n", c.comPort);
  send_line(client, "cfg capture_output %s\n",
            c.captureOutput[0] ? c.captureOutput : "auto");
  send_line(client, "cfg last_com %s\n", c.lastConnectedCom);
  send_line(client, "cfg serial_configured %d\n", c.serialConfigured ? 1 : 0);
  send_line(client, "cfg sleep_sync %d\n", c.autoSleepSync ? 1 : 0);
  send_line(client, "cfg screen_off_sync %d\n", c.screenOffSync ? 1 : 0);
  send_line(client, "cfg shutdown_off %d\n", c.turnOffOnShutdown ? 1 : 0);
  send_line(client, "cfg autostart %d\n", c.startOnBoot ? 1 : 0);
  send_line(client, "cfg region_algo %s\n",
            c.regionAlgo == 'x' ? "max" : "mean");
  send_line(client, "cfg region_blur %d\n", c.regionBlur);
  send_line(client, "cfg region_smooth %.2f\n", (double)c.regionSmooth);
  send_line(client, "cfg region_dark %d\n", c.regionDark);
  send_line(client, "cfg region_bbox %d,%d,%d,%d\n", c.regionBBox.l,
            c.regionBBox.t, c.regionBBox.w, c.regionBBox.h);
  // 空串也推，便于 UI 区分「未设」与缺字段
  send_line(client, "cfg last_custom_solid %s\n", c.lastCustomSolid);
  send_line(client, "cfg wall_comp %d\n", c.wallCompEnabled ? 1 : 0);
  send_line(client, "cfg wall_color %s\n", c.wallColor);

  if (!c.hasMap) {
    send_line(client, "cfg map default\n");
  } else {
    char map_line[560];
    int n = snprintf(map_line, sizeof(map_line), "cfg map ");
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
      int w = snprintf(map_line + n, sizeof(map_line) - (size_t)n,
                       "%s%d,%d,%d,%d", (i == 0 ? "" : ";"), x0, y0, x1, y1);
      if (w < 0 || n + w >= (int)sizeof(map_line)) {
        send_line(client, "cfg map default\n");
        n = -1;
        break;
      }
      n += w;
    }
    if (n > 0) {
      if (n + 1 < (int)sizeof(map_line)) {
        map_line[n++] = '\n';
        map_line[n] = '\0';
      }
      send_raw(client, map_line, n);
    }
  }

  char scene[40];
  format_scene(scene, sizeof(scene));
  send_line(client, "cfg scene %s\n", scene);
  send_line(client, "cfg end\n");
}

void push_config_snapshot(SOCKET client) {
  push_config_lines(client);
  HANDLE *sp = helper_serial();
  const bool has_serial = sp != nullptr && *sp != INVALID_HANDLE_VALUE;
  if (has_serial) {
    send_status(client, "ready");
    push_runtime_status(client, true);
  } else if (helper_boot_serial_busy()) {
    // 为什么：boot 异步开口中；推 reconnecting=未就绪，勿 reconnect_fail 误报打开失败
    send_status(client, "reconnecting");
    send_engine_status(client);
    send_display_status(client);
    send_capture_status(client);
  } else {
    // 为什么：无 COM 时勿推 ready/com，否则 UI 会当成有设备
    send_status(client, "reconnect_fail");
    send_engine_status(client);
    send_display_status(client);
    send_capture_status(client);
  }
}

bool ipc_has_client() { return g_client_sock != INVALID_SOCKET; }

// 为什么：托盘线程可能调用；先拷贝句柄再 send，避免与 drop_client
// 竞态 double-close。非热路径，偶发失败可接受（下次再点）。
bool ipc_push_ui_show() {
  SOCKET cs = g_client_sock;
  if (cs == INVALID_SOCKET)
    return false;
  send_line(cs, "ui show\n");
  printf("ipc: pushed ui show\n");
  return true;
}

bool ipc_push_runtime_status(bool include_com) {
  // 为什么：无 UI 时托盘/电源仍可能调用；先看 socket，再读 intent，避免无谓组包
  SOCKET cs = g_client_sock;
  if (cs == INVALID_SOCKET)
    return false;
  push_runtime_status(cs, include_com);
  printf("ipc: pushed runtime status (com=%d)\n", include_com ? 1 : 0);
  return true;
}

bool ipc_push_serial_ready() {
  SOCKET cs = g_client_sock;
  if (cs == INVALID_SOCKET)
    return false;
  send_status(cs, "ready");
  push_runtime_status(cs, true);
  printf("ipc: pushed serial ready\n");
  return true;
}

bool ipc_push_serial_fail() {
  SOCKET cs = g_client_sock;
  if (cs == INVALID_SOCKET)
    return false;
  send_status(cs, "reconnect_fail");
  send_engine_status(cs);
  send_display_status(cs);
  send_capture_status(cs);
  printf("ipc: pushed serial fail\n");
  return true;
}

bool ipc_push_config_snapshot() {
  // 为什么：只推 cfg，不带 status ready，避免托盘改自启时重置 UI 相位
  SOCKET cs = g_client_sock;
  if (cs == INVALID_SOCKET)
    return false;
  push_config_lines(cs);
  printf("ipc: pushed config snapshot\n");
  return true;
}
