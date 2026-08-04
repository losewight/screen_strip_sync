// 必须先于 windows.h（ipc_loop.h / light_engine 会间接包含）
#include <winsock2.h>
#include <ws2tcpip.h>

#include "config_store.h"
#include "helper_lifecycle.h"
#include "ipc_loop.h"
#include "light_engine.h"
#include "serial_port.h"
#include "ui_launcher.h"

#include <atomic>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>


static SOCKET g_listen_sock = INVALID_SOCKET;
static SOCKET g_client_sock = INVALID_SOCKET;
static std::atomic_bool g_ipc_quit{false};

// ---------------------------------------------------------------------------
// 1) 校验
// ---------------------------------------------------------------------------

static bool is_rrggbb(const char *s) {
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

// ---------------------------------------------------------------------------
// 2) 读一行（到 \n；超长丢弃到行尾）
// 为什么：512 是 IPC 行上限，与串口帧长 <120 红线无关，禁止互相「对齐」
// ---------------------------------------------------------------------------

enum class ReadLineResult { Ok, PeerGone, TooLong };

static ReadLineResult read_line(SOCKET client, char *line, int line_cap) {
  const int kMaxPayload = 512;
  const int max_payload =
      (line_cap - 1 < kMaxPayload) ? (line_cap - 1) : kMaxPayload;
  int n = 0;

  while (n < max_payload) {
    char ch = 0;
    int r = recv(client, &ch, 1, 0);
    if (r <= 0) {
      printf("peer closed or recv err\n");
      return ReadLineResult::PeerGone;
    }
    if (ch == '\r')
      continue;
    if (ch == '\n') {
      line[n] = '\0';
      return ReadLineResult::Ok;
    }
    line[n++] = ch;
  }

  printf("line too long, rejected\n");
  for (;;) {
    char ch = 0;
    int r = recv(client, &ch, 1, 0);
    if (r <= 0)
      return ReadLineResult::PeerGone;
    if (ch == '\n')
      break;
  }
  return ReadLineResult::TooLong;
}

// ---------------------------------------------------------------------------
// 3) 状态 / 配置快照回推
// ---------------------------------------------------------------------------

static void send_raw(SOCKET client, const char *buf, int n) {
  if (n > 0 && client != INVALID_SOCKET)
    send(client, buf, n, 0);
}

static void send_line(SOCKET client, const char *fmt, ...) {
  char buf[640];
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);
  if (n > 0 && n < (int)sizeof(buf))
    send_raw(client, buf, n);
}

static void send_status(SOCKET client, const char *word) {
  send_line(client, "status %s\n", word);
}

static void send_status_kv(SOCKET client, const char *key, const char *value) {
  send_line(client, "status %s %s\n", key, value);
}

static void send_engine_status(SOCKET client) {
  send_status_kv(client, "engine", engine_is_running() ? "1" : "0");
}

static void send_display_status(SOCKET client) {
  DisplayIntent intent = engine_get_display_intent();
  switch (intent.kind) {
  case DisplayIntentKind::Engine:
    send_status_kv(client, "display", "engine");
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

// include_com=false：重连失败等无句柄情形，只报 engine
static void push_runtime_status(SOCKET client, bool include_com) {
  if (include_com) {
    char com[16];
    engine_get_com(com, sizeof(com));
    send_status_kv(client, "com", com);
  }
  send_engine_status(client);
  send_display_status(client);
}

static void format_scene(char *out, size_t cap) {
  DisplayIntent intent = engine_get_display_intent();
  switch (intent.kind) {
  case DisplayIntentKind::Engine:
    snprintf(out, cap, "engine");
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

// 连接建立 / sync：全量 cfg + cfg end + status
static void push_config_lines(SOCKET client) {
  HelperConfig c{};
  config_copy(&c);

  send_line(client, "cfg alpha %.2f\n", (double)c.emaAlpha);
  send_line(client, "cfg near_black %d\n", c.nearBlack);
  send_line(client, "cfg blur %d\n", c.blurStep);
  send_line(client, "cfg mode %c\n", c.mode);
  send_line(client, "cfg com %s\n", c.comPort);
  send_line(client, "cfg last_com %s\n", c.lastConnectedCom);
  send_line(client, "cfg sleep_sync %d\n", c.autoSleepSync ? 1 : 0);
  send_line(client, "cfg shutdown_off %d\n", c.turnOffOnShutdown ? 1 : 0);
  send_line(client, "cfg autostart %d\n", c.startOnBoot ? 1 : 0);

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

static void push_config_snapshot(SOCKET client) {
  push_config_lines(client);
  send_status(client, "ready");
  push_runtime_status(client, true);
}

// ---------------------------------------------------------------------------
// 4) 执行一行命令
// ---------------------------------------------------------------------------

enum class DispatchResult {
  Continue,
  DropClient,      // bye：只关本连接
  ShutdownService, // quit：结束 ipc_run
};

static DispatchResult dispatch_line(const char *line, HANDLE *serial,
                                    SOCKET client) {
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
  if (strcmp(line, "off") == 0) {
    engine_stop();
    printf("cmd=off\n");
    power_off(*serial);
    return DispatchResult::Continue;
  }
  // 为什么：UI「关灯」熄画面不掉电；黑帧走 send_solid，帧间隔 ≥50ms
  if (strcmp(line, "soft_off") == 0) {
    engine_stop();
    engine_set_intent_soft_off();
    config_set_last_scene("off");
    printf("cmd=soft_off\n");
    send_solid(*serial, "000000");
    return DispatchResult::Continue;
  }
  if (strcmp(line, "start") == 0) {
    engine_start(*serial);
    engine_set_intent_engine();
    config_set_last_scene("engine");
    printf("cmd=start\n");
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
    } else {
      printf("cmd=highlight %ld\n", v);
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
      send_status(client, "reconnect_ok");
      push_runtime_status(client, true);
      char com[16];
      engine_get_com(com, sizeof(com));
      config_set_last_connected_com(com);
    } else {
      printf("cmd=reconnect failed\n");
      send_status(client, "reconnect_fail");
      send_engine_status(client);
    }
    return DispatchResult::Continue;
  }
  printf("unknown cmd: [%s]\n", line);
  return DispatchResult::Continue;
}

static void drop_client() {
  SOCKET cs = g_client_sock;
  g_client_sock = INVALID_SOCKET;
  if (cs != INVALID_SOCKET) {
    closesocket(cs);
    printf("client dropped (lights stay)\n");
  }
}

static void close_listen_sock() {
  SOCKET ls = g_listen_sock;
  g_listen_sock = INVALID_SOCKET;
  if (ls != INVALID_SOCKET)
    closesocket(ls);
}

// ---------------------------------------------------------------------------
// 5) 对外：听端口 → 循环 accept（select）→ quit/cancel 才退出
// ---------------------------------------------------------------------------

bool ipc_run(unsigned short port, HANDLE *serial, bool launch_ui) {
  g_ipc_quit.store(false);

  WSADATA wsa;
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
    printf("WSAStartup failed: %d\n", WSAGetLastError());
    return false;
  }

  SOCKET listen_sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (listen_sock == INVALID_SOCKET) {
    printf("socket failed: %d\n", WSAGetLastError());
    WSACleanup();
    return false;
  }

  BOOL yes = 1;
  setsockopt(listen_sock, SOL_SOCKET, SO_REUSEADDR, (const char *)&yes,
             sizeof(yes));

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(port);
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

  if (bind(listen_sock, (SOCKADDR *)&addr, sizeof(addr)) == SOCKET_ERROR) {
    printf("bind failed: %d\n", WSAGetLastError());
    closesocket(listen_sock);
    WSACleanup();
    return false;
  }
  printf("bind ok 127.0.0.1:%u\n", (unsigned)port);

  // backlog>1：踢旧时新连接已在队列，不必丢
  if (listen(listen_sock, 4) == SOCKET_ERROR) {
    printf("listen failed: %d\n", WSAGetLastError());
    closesocket(listen_sock);
    WSACleanup();
    return false;
  }
  g_listen_sock = listen_sock;
  printf("listen ok 127.0.0.1:%u\n", (unsigned)port);

  // 为什么：必须在 listen 之后再拉 UI，否则 Flutter 试连失败会误起次实例
  ui_maybe_launch_on_start(!launch_ui);

  while (!g_ipc_quit.load()) {
    fd_set readfds;
    FD_ZERO(&readfds);
    FD_SET(listen_sock, &readfds);
    SOCKET client = g_client_sock;
    if (client != INVALID_SOCKET)
      FD_SET(client, &readfds);

    SOCKET maxfd = listen_sock;
    if (client != INVALID_SOCKET && client > maxfd)
      maxfd = client;

    timeval tv{};
    tv.tv_sec = 1;
    tv.tv_usec = 0;
    int sel = select((int)maxfd + 1, &readfds, nullptr, nullptr, &tv);
    if (g_ipc_quit.load())
      break;
    if (sel == SOCKET_ERROR) {
      int err = WSAGetLastError();
      if (err == WSAEINTR)
        continue;
      printf("select failed: %d\n", err);
      break;
    }
    if (sel == 0)
      continue;

    // 新连接：踢旧（灯不动）→ 推快照
    if (FD_ISSET(listen_sock, &readfds)) {
      SOCKET neu = accept(listen_sock, nullptr, nullptr);
      if (neu == INVALID_SOCKET) {
        if (!g_ipc_quit.load())
          printf("accept failed: %d\n", WSAGetLastError());
        continue;
      }
      if (g_client_sock != INVALID_SOCKET) {
        printf("kick old client\n");
        drop_client();
      }
      g_client_sock = neu;
      printf("client connected\n");
      push_config_snapshot(neu);
      continue;
    }

    client = g_client_sock;
    if (client == INVALID_SOCKET || !FD_ISSET(client, &readfds))
      continue;

    char line[520];
    ReadLineResult rr = read_line(client, line, (int)sizeof(line));
    if (rr == ReadLineResult::PeerGone) {
      drop_client();
      continue;
    }
    if (rr == ReadLineResult::TooLong)
      continue;

    DispatchResult dr = dispatch_line(line, serial, client);
    if (dr == DispatchResult::DropClient) {
      drop_client();
      continue;
    }
    if (dr == DispatchResult::ShutdownService) {
      g_ipc_quit.store(true);
      break;
    }
  }

  drop_client();
  close_listen_sock();
  WSACleanup();
  return true;
}

// 为什么：从其他线程关掉 socket + 置旗标，打断 select，ipc_run 返回后
// helper_main 走 helper_shutdown。必须清空全局句柄，避免 ipc_run 尾部
// double-close。
void ipc_cancel() {
  g_ipc_quit.store(true);
  close_listen_sock();
  drop_client();
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

bool ipc_push_config_snapshot() {
  // 为什么：只推 cfg，不带 status ready，避免托盘改自启时重置 UI 相位
  SOCKET cs = g_client_sock;
  if (cs == INVALID_SOCKET)
    return false;
  push_config_lines(cs);
  printf("ipc: pushed config snapshot\n");
  return true;
}
