#include "ui_launcher.h"

#include "ipc_loop.h"

#include <atomic>
#include <cstdio>
#include <cstring>

static constexpr ULONGLONG kCooldownMs = 1500;

static HANDLE g_child = nullptr;
static ULONGLONG g_last_create_ms = 0;
static std::atomic_bool g_shutting{false};

static bool child_still_running() {
  if (!g_child)
    return false;
  DWORD wait = WaitForSingleObject(g_child, 0);
  if (wait == WAIT_TIMEOUT)
    return true; // 仍在跑
  // 已退出：清句柄，允许再次 CreateProcess
  CloseHandle(g_child);
  g_child = nullptr;
  return false;
}

static bool in_cooldown() {
  if (g_last_create_ms == 0)
    return false;
  return (GetTickCount64() - g_last_create_ms) < kCooldownMs;
}

// 对称 Flutter resolveHelperExecutable：同目录优先，再向上找开发路径
static bool resolve_flutter_exe(wchar_t *out, size_t out_cap) {
  wchar_t module[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, module, MAX_PATH);
  if (n == 0 || n >= MAX_PATH)
    return false;

  wchar_t *slash = wcsrchr(module, L'\\');
  if (!slash)
    return false;
  *slash = L'\0'; // module = helper 所在目录

  // 1) exe 同目录
  if (swprintf_s(out, out_cap, L"%s\\screen_strip_sync.exe", module) > 0) {
    if (GetFileAttributesW(out) != INVALID_FILE_ATTRIBUTES)
      return true;
  }

  // 2) 向上最多 10 层：build/windows/x64/runner/{Release,Debug}/
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

  // 工作目录 = exe 所在目录（Flutter 资源相对路径需要）
  wchar_t work_dir[MAX_PATH];
  wcsncpy_s(work_dir, exe, _TRUNCATE);
  wchar_t *slash = wcsrchr(work_dir, L'\\');
  if (slash)
    *slash = L'\0';

  // CreateProcessW 要求可写命令行缓冲
  wchar_t cmd[MAX_PATH + 4];
  swprintf_s(cmd, L"\"%s\"", exe);

  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};

  // 为什么：不设 CREATE_NO_WINDOW——Flutter 是 GUI 子系统
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

void ui_request_open() {
  if (g_shutting.load())
    return;

  // 1) 已有 IPC 客户端 → 推 ui show 置顶
  if (ipc_has_client()) {
    if (ipc_push_ui_show())
      printf("ui_launcher: client alive -> ui show\n");
    else
      printf("ui_launcher: has_client but push failed\n");
    return;
  }

  // 2) 子进程仍在 / 冷却窗 → 不动（防连点叠进程）
  if (child_still_running()) {
    printf("ui_launcher: child still running, skip\n");
    return;
  }
  if (in_cooldown()) {
    printf("ui_launcher: cooldown, skip\n");
    return;
  }

  // 3) CreateProcess
  create_flutter_process();
}

void ui_maybe_launch_on_start(bool silent) {
  if (silent) {
    printf("ui_launcher: silent start, skip UI\n");
    return;
  }
  ui_request_open();
}

void ui_notify_running_instance() {
  HWND hwnd = FindWindowW(kTrayWndClass, nullptr);
  if (!hwnd) {
    printf("ui_launcher: first instance tray not found\n");
    return;
  }
  if (!PostMessageW(hwnd, WM_SSS_OPEN_UI, 0, 0)) {
    printf("ui_launcher: PostMessage failed: %lu\n",
           (unsigned long)GetLastError());
    return;
  }
  printf("ui_launcher: notified running instance\n");
}

void ui_shutdown() {
  g_shutting.store(true);
  if (g_child) {
    CloseHandle(g_child);
    g_child = nullptr;
  }
}
