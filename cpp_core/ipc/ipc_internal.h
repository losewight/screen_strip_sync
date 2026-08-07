#pragma once

// IPC 模块内部共享声明；对外仍只暴露 ipc_loop.h。
// 必须先于 windows.h 包含 winsock2（并挡住 winsock.h）。

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _WINSOCKAPI_
#define _WINSOCKAPI_
#endif
#include <windows.h>
#include <winsock2.h>


#include <atomic>
#include <cstdarg>

extern SOCKET g_listen_sock;
extern SOCKET g_client_sock;
extern std::atomic_bool g_ipc_quit;

enum class ReadLineResult { Ok, PeerGone, TooLong };

enum class DispatchResult {
  Continue,
  DropClient,      // bye：只关本连接
  ShutdownService, // quit：结束 ipc_run
};

bool is_rrggbb(const char *s);
ReadLineResult read_line(SOCKET client, char *line, int line_cap);

void send_raw(SOCKET client, const char *buf, int n);
void send_line(SOCKET client, const char *fmt, ...);
void send_status(SOCKET client, const char *word);
void send_status_kv(SOCKET client, const char *key, const char *value);
void send_engine_status(SOCKET client);
void send_display_status(SOCKET client);
void push_runtime_status(SOCKET client, bool include_com);
void push_config_lines(SOCKET client);
void push_config_snapshot(SOCKET client);

DispatchResult dispatch_line(const char *line, HANDLE *serial, SOCKET client);

void drop_client();
void close_listen_sock();
