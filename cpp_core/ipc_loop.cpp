// 必须先于 windows.h（ipc_loop.h / light_engine 会间接包含）
#include <winsock2.h>
#include <ws2tcpip.h>

#include "ipc_loop.h"
#include "light_engine.h"

#include <cstdio>
#include <cstring>

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
// 3) 执行一行命令；返回 false = 结束命令循环（quit）
// ---------------------------------------------------------------------------

static bool dispatch_line(const char *line, HANDLE serial) {
  if (strcmp(line, "quit") == 0) {
    engine_stop();
    printf("cmd=quit\n");
    return false;
  }
  if (strcmp(line, "off") == 0) {
    engine_stop();
    printf("cmd=off\n");
    power_off(serial);
    return true;
  }
  if (strcmp(line, "start") == 0) {
    engine_start(serial);
    printf("cmd=start\n");
    return true;
  }
  if (strcmp(line, "stop") == 0) {
    engine_stop();
    printf("cmd=stop\n");
    return true;
  }
  if (strncmp(line, "solid ", 6) == 0) {
    const char *color = line + 6;
    if (!is_rrggbb(color)) {
      printf("bad solid color: [%s]\n", color);
    } else {
      printf("cmd=solid color=%s\n", color);
      send_solid(serial, color);
    }
    return true;
  }
  printf("unknown cmd: [%s]\n", line);
  return true;
}

// ---------------------------------------------------------------------------
// 4) 对外：听端口 → accept → 命令循环 → 清理 Winsock
// ---------------------------------------------------------------------------

bool ipc_run(unsigned short port, HANDLE serial) {
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
  printf("listen ok 127.0.0.1:%u\n", (unsigned)port);

  SOCKET client = accept(listen_sock, NULL, NULL);
  if (client == INVALID_SOCKET) {
    printf("accept failed: %d\n", WSAGetLastError());
    closesocket(listen_sock);
    WSACleanup();
    return false;
  }
  printf("client connected\n");

  for (;;) {
    char line[256];
    ReadLineResult rr = read_line(client, line, (int)sizeof(line));
    if (rr == ReadLineResult::PeerGone)
      break;
    if (rr == ReadLineResult::TooLong)
      continue;
    if (!dispatch_line(line, serial))
      break; // quit
  }

  closesocket(client);
  closesocket(listen_sock);
  WSACleanup();
  return true;
}
