// 必须先于 windows.h（ipc_loop.h / light_engine 会间接包含）
#include <winsock2.h>
#include <ws2tcpip.h>

#include "helper_lifecycle.h"
#include "ipc_loop.h"
#include "light_engine.h"
#include "serial_port.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

static SOCKET g_listen_sock = INVALID_SOCKET;
static SOCKET g_client_sock = INVALID_SOCKET;

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
// ---------------------------------------------------------------------------

enum class ReadLineResult { Ok, PeerGone, TooLong };

static ReadLineResult read_line(SOCKET client, char *line, int line_cap) {
  // 与拆前一致：有效内容最多 200，缓冲仍给 256
  const int max_payload = (line_cap > 200) ? 200 : (line_cap - 1);
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
// 3) 状态回推 + 执行一行命令；返回 false = 结束命令循环（quit）
// ---------------------------------------------------------------------------

// 为什么：状态走同一条 IPC，不另开通道；App 才能显示设备分配/回收结果
static void send_status(SOCKET client, const char *word) {
  char buf[64];
  int n = snprintf(buf, sizeof(buf), "status %s\n", word);
  if (n > 0 && n < (int)sizeof(buf))
    send(client, buf, n, 0);
}

static void send_status_kv(SOCKET client, const char *key, const char *value) {
  char buf[64];
  int n = snprintf(buf, sizeof(buf), "status %s %s\n", key, value);
  if (n > 0 && n < (int)sizeof(buf))
    send(client, buf, n, 0);
}

static void send_engine_status(SOCKET client) {
  send_status_kv(client, "engine", engine_is_running() ? "1" : "0");
}

// include_com=false：重连失败等无句柄情形，只报 engine 0
static void push_runtime_status(SOCKET client, bool include_com) {
  if (include_com) {
    char com[16];
    engine_get_com(com, sizeof(com));
    send_status_kv(client, "com", com);
  }
  send_engine_status(client);
}

static bool dispatch_line(const char *line, HANDLE *serial, SOCKET client) {
  if (strcmp(line, "quit") == 0) {
    engine_stop();
    printf("cmd=quit\n");
    return false;
  }
  if (strcmp(line, "off") == 0) {
    engine_stop();
    printf("cmd=off\n");
    power_off(*serial);
    return true;
  }
  // 为什么：UI「关灯」熄画面不掉电；黑帧走 send_solid，帧间隔 ≥50ms
  if (strcmp(line, "soft_off") == 0) {
    engine_stop();
    engine_set_intent_soft_off();
    printf("cmd=soft_off\n");
    send_solid(*serial, "000000");
    return true;
  }
  if (strcmp(line, "start") == 0) {
    engine_start(*serial);
    engine_set_intent_engine();
    printf("cmd=start\n");
    return true;
  }
  if (strcmp(line, "stop") == 0) {
    engine_stop();
    engine_set_intent_idle();
    printf("cmd=stop\n");
    return true;
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
    }
    return true;
  }
  // 为什么：缺参/非数字忽略（与 solid 非法同风格）；合法值交 engine_set_alpha
  // clamp
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
      printf("cmd=set alpha\n");
    }
    return true;
  }
  // 为什么：仅 a|b；非法忽略。引擎暂不分支（阶段 C）
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
        printf("cmd=set mode %c\n", norm);
        return true;
      }
    }
    printf("bad set mode: [%s]\n", p);
    return true;
  }
  // 为什么：只改配置，不自动开口；切口靠随后的 reconnect
  if (strncmp(line, "set com ", 8) == 0) {
    const char *p = line + 8;
    if (!engine_set_com(p)) {
      printf("bad set com: [%s]\n", p);
    } else {
      printf("cmd=set com\n");
    }
    return true;
  }
  // 为什么：0|1；非法忽略。控制休眠软关 vs 硬退
  if (strncmp(line, "set sleep_sync ", 15) == 0) {
    const char *p = line + 15;
    while (*p == ' ' || *p == '\t')
      ++p;
    if ((*p == '0' || *p == '1') && p[1] == '\0') {
      helper_set_sleep_sync(*p == '1');
      printf("cmd=set sleep_sync %c\n", *p);
    } else {
      printf("bad set sleep_sync: [%s]\n", p);
    }
    return true;
  }
  // 为什么：校准逐段点亮；越界忽略
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
    return true;
  }
  // 为什么：default 清表；否则 10 段百分比矩形
  if (strcmp(line, "set map default") == 0) {
    engine_clear_map();
    printf("cmd=set map default\n");
    return true;
  }
  if (strncmp(line, "set map ", 8) == 0) {
    const char *p = line + 8;
    if (!engine_set_map_from_ipc(p)) {
      printf("bad set map: [%s]\n", p);
    } else {
      printf("cmd=set map\n");
    }
    return true;
  }
  if (strcmp(line, "reconnect") == 0) {
    engine_stop();
    send_status(client, "reconnecting");
    // 为什么：旧句柄已失效，先归还再申请，避免占着坏句柄
    if (*serial != INVALID_HANDLE_VALUE) {
      close_com(*serial);
      *serial = INVALID_HANDLE_VALUE;
    }
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
      printf("cmd=reconnect ok\n");
      send_status(client, "reconnect_ok");
      push_runtime_status(client, true);
    } else {
      printf("cmd=reconnect failed\n");
      send_status(client, "reconnect_fail");
      send_engine_status(client);
    }
    return true;
  }
  printf("unknown cmd: [%s]\n", line);
  return true;
}

// ---------------------------------------------------------------------------
// 4) 对外：听端口 → accept → 命令循环 → 清理 Winsock
// ---------------------------------------------------------------------------

bool ipc_run(unsigned short port, HANDLE *serial) {
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

  if (listen(listen_sock, 1) == SOCKET_ERROR) {
    printf("listen failed: %d\n", WSAGetLastError());
    closesocket(listen_sock);
    WSACleanup();
    return false;
  }
  // 为什么：记住 listen_sock，才能在 ipc_cancel() 里关掉 accept 阻塞
  g_listen_sock = listen_sock;
  printf("listen ok 127.0.0.1:%u\n", (unsigned)port);

  SOCKET client = accept(listen_sock, NULL, NULL);
  if (client == INVALID_SOCKET) {
    printf("accept failed: %d\n", WSAGetLastError());
    g_listen_sock = INVALID_SOCKET;
    closesocket(listen_sock);
    WSACleanup();
    return false;
  }
  // 为什么：记住 client，才能在 ipc_cancel() 里关掉 recv 阻塞
  g_client_sock = client;
  printf("client connected\n");
  send_status(client, "ready"); // 串口在 main 里已就绪，IPC 接通即告 App
  push_runtime_status(client, true);

  for (;;) {
    char line[256];
    ReadLineResult rr = read_line(client, line, (int)sizeof(line));
    if (rr == ReadLineResult::PeerGone)
      break;
    if (rr == ReadLineResult::TooLong)
      continue;
    if (!dispatch_line(line, serial, client))
      break; // quit
  }

  closesocket(client);
  closesocket(listen_sock);
  g_client_sock = INVALID_SOCKET;
  g_listen_sock = INVALID_SOCKET;
  WSACleanup();
  return true;
}

// 为什么：从其他线程（Ctrl handler）关掉两个 socket，让 accept/recv 立即
// 失败返回，ipc_run 自然结束，从而回到 helper_main.cpp 的清理序列。
// 关 listen_sock 打断还在等 accept 的情形；关 client 打断正在 recv 的情形。
void ipc_cancel() {
  SOCKET ls = g_listen_sock;
  SOCKET cs = g_client_sock;
  if (ls != INVALID_SOCKET)
    closesocket(ls);
  if (cs != INVALID_SOCKET)
    closesocket(cs);
}
