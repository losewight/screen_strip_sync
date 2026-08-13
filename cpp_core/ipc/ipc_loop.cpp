// 必须先于 windows.h（ipc_loop.h / light_engine 会间接包含）
#include <winsock2.h>
#include <ws2tcpip.h>

#include "ipc_internal.h"
#include "ipc_loop.h"
#include "ui_launcher.h"

#include <atomic>
#include <cstdio>
#include <cstring>

// 次实例连上后首包若是 open_ui，则只唤界面、不踢现有 Flutter 客户端
static bool try_handle_open_ui_probe(SOCKET neu) {
  fd_set rfds;
  FD_ZERO(&rfds);
  FD_SET(neu, &rfds);
  timeval tv{};
  tv.tv_sec = 0;
  tv.tv_usec = 300000;
  const int sel = select((int)neu + 1, &rfds, nullptr, nullptr, &tv);
  if (sel <= 0)
    return false;

  char buf[32] = {};
  const int n = recv(neu, buf, (int)sizeof(buf) - 1, 0);
  if (n <= 0) {
    closesocket(neu);
    return true;
  }
  buf[n] = '\0';
  char *nl = strchr(buf, '\n');
  if (nl)
    *nl = '\0';
  char *cr = strchr(buf, '\r');
  if (cr)
    *cr = '\0';

  if (strcmp(buf, "open_ui") == 0) {
    printf("ipc: open_ui probe\n");
    ui_request_open();
    closesocket(neu);
    return true;
  }

  printf("ipc: probe unexpected [%s], drop\n", buf);
  closesocket(neu);
  return true;
}

SOCKET g_listen_sock = INVALID_SOCKET;
SOCKET g_client_sock = INVALID_SOCKET;
std::atomic_bool g_ipc_quit{false};

// ---------------------------------------------------------------------------
// 读一行（到 \n；超长丢弃到行尾）
// 为什么：512 是 IPC 行上限，与串口帧长 <120 红线无关，禁止互相「对齐」
// ---------------------------------------------------------------------------

ReadLineResult read_line(SOCKET client, char *line, int line_cap) {
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

void drop_client() {
  SOCKET cs = g_client_sock;
  g_client_sock = INVALID_SOCKET;
  if (cs != INVALID_SOCKET) {
    closesocket(cs);
    printf("client dropped (lights stay)\n");
  }
}

void close_listen_sock() {
  SOCKET ls = g_listen_sock;
  g_listen_sock = INVALID_SOCKET;
  if (ls != INVALID_SOCKET)
    closesocket(ls);
}

// ---------------------------------------------------------------------------
// 对外：听端口 → 循环 accept（select）→ quit/cancel 才退出
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
      if (try_handle_open_ui_probe(neu))
        continue;

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
