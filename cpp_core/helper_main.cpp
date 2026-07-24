#include <winsock2.h>
#include <ws2tcpip.h>

#include "serial_port.h"
#include <atomic>
#include <cstdio>
#include <cstring>
#include <thread>

// 为什么：主线程改 false，发帧线程 while 退出；Day7 的停止标志。
static std::atomic<bool> g_running{false};

// 为什么：设备要先上电再握手，否则后续 set_rgb_pc 会被忽略。
static bool power_on(HANDLE h) {
  if (!send_one_frame(h, "set_power 1\r\n",
                      (DWORD)(strlen("set_power 1\r\n")))) {
    return false;
  }
  return read_response_ok(h, 500);
}

// 为什么：声明 PC 就绪 + 联动，串口才进入可发 RGB 帧的状态。
static bool handshake(HANDLE h) {
  if (!send_one_frame(h, "set_pc_available 1\r\n", 20))
    return false;
  if (!read_response_ok(h, 500))
    return false;
  if (!send_one_frame(h, "set_usb_dim_time 20\r\n", 21))
    return false;
  if (!read_response_ok(h, 500))
    return false;
  if (!send_one_frame(h, "set_pc_linkage 1\r\n", 18))
    return false;
  return read_response_ok(h, 500);
}

// 为什么：关串口前必须 set_power 0，否则灯可能一直亮着占着设备状态。
static bool power_off(HANDLE h) {
  if (!send_one_frame(h, "set_power 0\r\n",
                      (DWORD)(strlen("set_power 0\r\n")))) {
    return false;
  }
  return read_response_ok(h, 500);
}

// 为什么：10 段同色、Step=2，帧长可控在 <120，不触设备 128 上限。
static bool send_solid(HANDLE h, const char *rrggbb) {
  char frame[128];
  snprintf(frame, sizeof(frame),
           "set_rgb_pc %04x 00 63 %s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           1, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb,
           rrggbb, rrggbb);

  DWORD len = (DWORD)strlen(frame);
  if (len >= 120) { // 红线：拒绝 >=120
    printf("frame too long: %lu\n", (unsigned long)len);
    return false;
  }
  if (!send_one_frame(h, frame, len))
    return false;
  Sleep(50); // 红线：帧间隔 ≥50ms
  return true;
}

// 生产：红蓝 / 绿紫交替 10 段（与 DLL 同逻辑，helper 进程内自跑）。
static void produce_colors(int frame_index, char *out_frame, size_t out_cap) {
  const unsigned frame_id = (unsigned)frame_index & 0xFFFFu;
  if (frame_index % 2 != 0) {
    snprintf(
        out_frame, out_cap,
        "set_rgb_pc %04x 00 63 ff0000 2 0000ff 2 ff0000 2 0000ff 2 ff0000 2 "
        "0000ff 2 ff0000 2 0000ff 2 ff0000 2 0000ff 2\r\n",
        frame_id);
  } else {
    snprintf(
        out_frame, out_cap,
        "set_rgb_pc %04x 00 63 00ff00 2 ff00ff 2 00ff00 2 ff00ff 2 00ff00 2 "
        "ff00ff 2 00ff00 2 ff00ff 2 00ff00 2 ff00ff 2\r\n",
        frame_id);
  }
}

// 消费：写串口后 Sleep≥50，避免挤帧丢包。
static bool consumer_to_serial(HANDLE h, const char *frame, DWORD frame_len) {
  if (!send_one_frame(h, frame, frame_len))
    return false;
  Sleep(50);
  return true;
}

static void frame_loop(HANDLE h) {
  int i = 0;
  while (g_running.load()) {
    char frame_buf[128];
    produce_colors(i, frame_buf, sizeof(frame_buf));
    if (!consumer_to_serial(h, frame_buf, (DWORD)strlen(frame_buf)))
      break;
    i++;
  }
}

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

int main(int argc, char *argv[]) {

  /// 进程通信初始化
  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(9527);
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

  WSADATA wsa;
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
    printf("WSAStartup failed: %d\n", WSAGetLastError());
    return 1;
  }

  SOCKET listen_sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (listen_sock == INVALID_SOCKET) {
    printf("socket failed: %d\n", WSAGetLastError());
    WSACleanup();
    return 1;
  }

  if (bind(listen_sock, (SOCKADDR *)&addr, sizeof(addr)) == SOCKET_ERROR) {
    printf("bind failed: %d\n", WSAGetLastError());
    closesocket(listen_sock);
    WSACleanup();
    return 1;
  }

  printf("bind ok 127.0.0.1:9527\n");

  if (listen(listen_sock, 1) == SOCKET_ERROR) {
    printf("listen failed: %d\n", WSAGetLastError());
    closesocket(listen_sock);
    WSACleanup();
    return 1;
  }
  printf("listen ok 127.0.0.1:9527\n");

  SOCKET client = accept(listen_sock, NULL, NULL);
  if (client == INVALID_SOCKET) {
    printf("accept failed: %d\n", WSAGetLastError());
    closesocket(listen_sock);
    WSACleanup();
    return 1;
  }
  printf("client connected\n");

  // 串口初始化
  HANDLE h = INVALID_HANDLE_VALUE;
  if (!open_com("COM10", &h)) {
    printf("open_com failed\n");
    closesocket(client);
    closesocket(listen_sock);
    WSACleanup();
    return 1;
  }
  // 串口握手
  if (!power_on(h) || !handshake(h)) {
    printf("power_on/handshake failed\n");
    power_off(h);
    close_com(h);
    closesocket(client);
    closesocket(listen_sock);
    WSACleanup();
    return 1;
  }
  printf("serial ready\n");

  std::thread worker;

  // 命令处理
  bool running = true;
  while (running) {
    char line[256];
    int n = 0;
    bool got_line = false;
    bool peer_gone = false;

    // --- 读一行（和你现在一样）---
    while (n < 200) {
      char ch = 0;
      int r = recv(client, &ch, 1, 0);
      if (r <= 0) {
        printf("peer closed or recv err\n");
        peer_gone = true;
        break;
      }
      if (ch == '\r')
        continue;
      if (ch == '\n') {
        line[n] = '\0';
        got_line = true;
        break; // 注意：这里 break 只跳出「读字节」的内层 while
      }
      line[n++] = ch;
    }

    if (peer_gone)
      break; // 对端断开 → 结束外层
    if (!got_line && n >= 200) {
      printf("line too long, rejected\n");
      for (;;) {
        char ch = 0;
        int r = recv(client, &ch, 1, 0);
        if (r <= 0) {
          peer_gone = true;
          break;
        }
        if (ch == '\n')
          break;
      }
      if (peer_gone)
        break;
      continue;
    }
    if (!got_line)
      break;

    // --- 认命令 ---
    if (strcmp(line, "quit") == 0) {
      g_running.store(false);
      if (worker.joinable())
        worker.join();
      running = false;
      printf("cmd=quit\n");
      running = false; // 结束外层循环
    } else if (strcmp(line, "off") == 0) {
      g_running.store(false);
      if (worker.joinable())
        worker.join();
      printf("cmd=off\n");
      power_off(h);
    } else if (strcmp(line, "start") == 0) {
      if (!g_running.load()) { // 避免重复 start 起两个线程
        g_running.store(true);
        worker = std::thread(frame_loop, h);
      }
      printf("cmd=start\n");
    } else if (strcmp(line, "stop") == 0) {
      g_running.store(false);
      if (worker.joinable())
        worker.join();
      printf("cmd=stop\n");
    } else if (strncmp(line, "solid ", 6) == 0) {
      const char *color = line + 6;
      if (!is_rrggbb(color)) {
        printf("bad solid color: [%s]\n", color);
      } else {
        printf("cmd=solid color=%s\n", color);
        send_solid(h, color);
      }
    } else {
      printf("unknown cmd: [%s]\n", line);
    }
  }

  power_off(h);
  close_com(h);
  closesocket(client);
  closesocket(listen_sock);
  WSACleanup();
  return 0;
}
