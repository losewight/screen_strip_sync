#include "ui_launcher.h"

#include "app_paths.h"
#include "ipc_loop.h"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>

static constexpr ULONGLONG kCooldownMs = 1500;
static constexpr unsigned short kIpcPort = 9527;

static HANDLE g_child = nullptr;
static ULONGLONG g_last_create_ms = 0;
static std::atomic_bool g_shutting{false};
static std::mutex g_open_mu;

static void second_instance_log(const char *msg) {
  char path[MAX_PATH];
  if (!helper_log_path(path, sizeof(path)))
    return;
  wchar_t wide[MAX_PATH];
  if (!data_dir_wide(wide, MAX_PATH))
    return;
  FILE *fp = nullptr;
  if (fopen_s(&fp, path, "a") != 0 || !fp)
    return;
  fprintf(fp, "[second_instance] %s\n", msg);
  fclose(fp);
}

static bool child_still_running() {
  if (!g_child)
    return false;
  DWORD wait = WaitForSingleObject(g_child, 0);
  if (wait == WAIT_TIMEOUT)
    return true;
  CloseHandle(g_child);
  g_child = nullptr;
  return false;
}

static bool in_cooldown() {
  if (g_last_create_ms == 0)
    return false;
  return (GetTickCount64() - g_last_create_ms) < kCooldownMs;
}

static bool resolve_flutter_exe(wchar_t *out, size_t out_cap) {
  wchar_t module[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, module, MAX_PATH);
  if (n == 0 || n >= MAX_PATH)
    return false;

  wchar_t *slash = wcsrchr(module, L'\\');
  if (!slash)
    return false;
  *slash = L'\0';

  if (swprintf_s(out, out_cap, L"%s\\screen_strip_sync.exe", module) > 0) {
    if (GetFileAttributesW(out) != INVALID_FILE_ATTRIBUTES)
      return true;
  }

  wchar_t dir[MAX_PATH];
  wcsncpy_s(dir, module, _TRUNCATE);
  for (int i = 0; i < 10; ++i) {
    static const wchar_t *kConfigs[] = {L"Release", L"Debug"};
    for (const wchar_t *cfg : kConfigs) {
      if (swprintf_s(
              out, out_cap,
              L"%s\\build\\windows\\x64\\runner\\%s\\screen_strip_sync.exe", dir,
              cfg) > 0) {
        if (GetFileAttributesW(out) != INVALID_FILE_ATTRIBUTES)
          return true;
      }
    }
    wchar_t *p = wcsrchr(dir, L'\\');
    if (!p)
      break;
    *p = L'\0';
  }

  return false;
}

static bool create_flutter_process() {
  wchar_t exe[MAX_PATH];
  if (!resolve_flutter_exe(exe, MAX_PATH)) {
    printf("ui_launcher: screen_strip_sync.exe not found\n");
    return false;
  }

  wchar_t work_dir[MAX_PATH];
  wcsncpy_s(work_dir, exe, _TRUNCATE);
  wchar_t *slash = wcsrchr(work_dir, L'\\');
  if (slash)
    *slash = L'\0';

  wchar_t cmd[MAX_PATH + 4];
  swprintf_s(cmd, L"\"%s\"", exe);

  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};

  BOOL ok = CreateProcessW(exe, cmd, nullptr, nullptr, FALSE, 0, nullptr,
                           work_dir, &si, &pi);
  if (!ok) {
    printf("ui_launcher: CreateProcess failed: %lu\n",
           (unsigned long)GetLastError());
    return false;
  }

  if (g_child) {
    CloseHandle(g_child);
    g_child = nullptr;
  }
  g_child = pi.hProcess;
  CloseHandle(pi.hThread);
  g_last_create_ms = GetTickCount64();
  printf("ui_launcher: launched %ls\n", exe);
  return true;
}

// 为什么：PostMessage 跨提权会被 UIPI 拦；loopback TCP 不受限
static bool notify_via_tcp() {
  WSADATA wsa{};
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
    return false;

  SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (s == INVALID_SOCKET) {
    WSACleanup();
    return false;
  }

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(kIpcPort);
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

  bool ok = false;
  if (connect(s, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) == 0) {
    static const char kLine[] = "open_ui\n";
    const int sent = send(s, kLine, (int)(sizeof(kLine) - 1), 0);
    ok = sent == (int)(sizeof(kLine) - 1);
  }

  closesocket(s);
  WSACleanup();
  return ok;
}

void ui_request_open() {
  std::lock_guard<std::mutex> lock(g_open_mu);
  if (g_shutting.load())
    return;

  if (ipc_has_client()) {
    if (ipc_push_ui_show())
      printf("ui_launcher: client alive -> ui show\n");
    else
      printf("ui_launcher: has_client but push failed\n");
    return;
  }

  if (child_still_running()) {
    printf("ui_launcher: child still running, skip\n");
    return;
  }
  if (in_cooldown()) {
    printf("ui_launcher: cooldown, skip\n");
    return;
  }

  create_flutter_process();
}

void ui_post_request_open() {
  HWND hwnd = FindWindowW(kTrayWndClass, nullptr);
  if (hwnd && PostMessageW(hwnd, WM_SSS_OPEN_UI, 0, 0))
    return;
  // 托盘窗还没起来时退回加锁路径（启动瞬间）
  ui_request_open();
}

void ui_maybe_launch_on_start(bool silent) {
  if (silent) {
    printf("ui_launcher: silent start, skip UI\n");
    return;
  }
  ui_post_request_open();
}

void ui_notify_running_instance() {
  if (notify_via_tcp()) {
    second_instance_log("notify=tcp_ok");
    return;
  }

  HWND hwnd = FindWindowW(kTrayWndClass, nullptr);
  if (!hwnd) {
    second_instance_log("notify=tcp_fail tray_not_found");
    return;
  }
  if (!PostMessageW(hwnd, WM_SSS_OPEN_UI, 0, 0)) {
    second_instance_log("notify=postmessage_fail");
    printf("ui_launcher: PostMessage failed: %lu\n",
           (unsigned long)GetLastError());
    return;
  }
  second_instance_log("notify=postmessage_ok");
  printf("ui_launcher: notified running instance\n");
}

void ui_shutdown() {
  g_shutting.store(true);
  if (g_child) {
    CloseHandle(g_child);
    g_child = nullptr;
  }
}
