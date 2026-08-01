#include "power_watch.h"

#include "helper_lifecycle.h"

#include <atomic>
#include <cstdio>
#include <thread>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

static std::atomic_bool g_started{false};
static HPOWERNOTIFY g_suspend_notify = nullptr;

static LRESULT CALLBACK power_wnd_proc(HWND hwnd, UINT msg, WPARAM wParam,
                                       LPARAM lParam) {
  switch (msg) {
  case WM_POWERBROADCAST:
    // 方案三：开=硬关进程；关=不插手；恢复由 Flutter 拉起新 helper
    if (wParam == PBT_APMSUSPEND || wParam == PBT_APMQUERYSUSPEND) {
      if (helper_get_sleep_sync()) {
        printf("power: suspend (wParam=0x%Ix) -> helper_shutdown\n", wParam);
        helper_shutdown();
      } else {
        printf("power: suspend (wParam=0x%Ix) sleep_sync off, skip\n", wParam);
      }
      return TRUE;
    }
    if (wParam == PBT_APMRESUMESUSPEND || wParam == PBT_APMRESUMEAUTOMATIC ||
        wParam == PBT_APMRESUMECRITICAL) {
      printf("power: resume (wParam=0x%Ix) ignored (Flutter reconnects)\n",
             wParam);
      return TRUE;
    }
    break;
  case WM_QUERYENDSESSION:
    printf("power: query end session -> helper_shutdown\n");
    helper_shutdown();
    return TRUE;
  case WM_ENDSESSION:
    if (wParam) {
      printf("power: end session -> helper_shutdown\n");
      helper_shutdown();
    }
    return 0;
  default:
    break;
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static void power_watch_thread() {
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = power_wnd_proc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"ZeerayHelperPowerWatch";
  if (!RegisterClassExW(&wc)) {
    // 为什么：重复启动时类可能已注册；仅首次失败才放弃
    if (GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      printf("power_watch RegisterClassEx failed: %lu\n",
             (unsigned long)GetLastError());
      return;
    }
  }

  // 为什么：HWND_MESSAGE 收不到电源广播；必须用隐藏顶层窗（与旧版 wndproc
  // 一致）
  HWND hwnd = CreateWindowExW(WS_EX_TOOLWINDOW, wc.lpszClassName,
                              L"ZeerayPowerWatch", WS_POPUP, 0, 0, 0, 0,
                              nullptr, nullptr, wc.hInstance, nullptr);
  if (!hwnd) {
    printf("power_watch CreateWindowEx failed: %lu\n",
           (unsigned long)GetLastError());
    return;
  }
  ShowWindow(hwnd, SW_HIDE);

  // 为什么：现代 Windows / Modern Standby 上，注册后才稳定收到挂起通知
  g_suspend_notify =
      RegisterSuspendResumeNotification(hwnd, DEVICE_NOTIFY_WINDOW_HANDLE);
  if (!g_suspend_notify) {
    printf("RegisterSuspendResumeNotification failed: %lu\n",
           (unsigned long)GetLastError());
  } else {
    printf("power_watch suspend notify ok\n");
  }
  printf("power_watch window ok\n");

  MSG msg;
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }

  if (g_suspend_notify) {
    UnregisterSuspendResumeNotification(g_suspend_notify);
    g_suspend_notify = nullptr;
  }
}

void power_watch_start() {
  bool expected = false;
  if (!g_started.compare_exchange_strong(expected, true))
    return;
  // 为什么：detach —— 硬关时随 helper_shutdown→ipc_cancel→main 退出
  std::thread(power_watch_thread).detach();
}
