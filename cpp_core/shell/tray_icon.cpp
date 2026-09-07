#include "tray_icon.h"

#include "config_store.h"
#include "helper_lifecycle.h"
#include "ipc_loop.h"
#include "light_engine.h"
#include "resource.h"
#include "ui_launcher.h"

#include <atomic>
#include <cstdio>
#include <thread>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <powrprof.h>
#include <shellapi.h>

#pragma comment(lib, "PowrProf.lib")

static constexpr UINT WM_TRAYICON = WM_APP + 1;
static constexpr UINT kTrayId = 1;

// NOTIFYICON_VERSION_4 下悬停 tip 需要 NIF_SHOWTIP，否则部分 shell 不显示
#ifndef NIF_SHOWTIP
#define NIF_SHOWTIP 0x00000080
#endif

static std::atomic_bool g_started{false};
static std::atomic_bool g_stop_requested{false};
static HWND g_hwnd = nullptr;
static HPOWERNOTIFY g_suspend_notify = nullptr;
static HPOWERNOTIFY g_monitor_notify = nullptr;
static UINT g_taskbar_created = 0;
static NOTIFYICONDATAW g_nid{};
static bool g_nid_added = false;
static DWORD g_tray_tid = 0;

static HANDLE serial_or_invalid() {
  HANDLE *p = helper_serial();
  if (!p || *p == INVALID_HANDLE_VALUE)
    return INVALID_HANDLE_VALUE;
  return *p;
}

// 为什么：经典 TrackPopupMenu 默认跟系统浅色；uxtheme
// 未文档化入口可强制暗色菜单
static void tray_enable_dark_menus() {
  static bool done = false;
  if (done)
    return;
  done = true;

  HMODULE ux =
      LoadLibraryExW(L"uxtheme.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!ux)
    return;

  // ordinal 135 = SetPreferredAppMode (Win10 1903+)；ForceDark = 2
  using SetPreferredAppModeFn = int(WINAPI *)(int);
  auto set_mode = reinterpret_cast<SetPreferredAppModeFn>(
      GetProcAddress(ux, MAKEINTRESOURCEA(135)));
  if (set_mode)
    set_mode(2);

  // ordinal 136 = FlushMenuThemes：立刻刷新，否则下次右键才变暗
  using FlushMenuThemesFn = void(WINAPI *)();
  auto flush = reinterpret_cast<FlushMenuThemesFn>(
      GetProcAddress(ux, MAKEINTRESOURCEA(136)));
  if (flush)
    flush();
}

static void tray_add_icon(HWND hwnd) {
  HINSTANCE inst = GetModuleHandleW(nullptr);
  ZeroMemory(&g_nid, sizeof(g_nid));
  g_nid.cbSize = sizeof(g_nid);
  g_nid.hWnd = hwnd;
  g_nid.uID = kTrayId;
  g_nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  g_nid.uCallbackMessage = WM_TRAYICON;
  g_nid.hIcon = LoadIconW(inst, MAKEINTRESOURCEW(IDI_HELPER_TRAY));
  if (!g_nid.hIcon)
    g_nid.hIcon =
        LoadIconW(nullptr, MAKEINTRESOURCEW(32512)); // IDI_APPLICATION
  wcsncpy_s(g_nid.szTip, L"Screen Strip Sync", _TRUNCATE);

  if (g_nid_added) {
    Shell_NotifyIconW(NIM_MODIFY, &g_nid);
  } else if (Shell_NotifyIconW(NIM_ADD, &g_nid)) {
    g_nid_added = true;
    // 为什么：Win10+ 建议设版本，避免部分 shell 行为异常
    g_nid.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &g_nid);
    printf("tray icon added\n");
  } else {
    printf("tray NIM_ADD failed: %lu\n", (unsigned long)GetLastError());
  }
}

static void tray_remove_icon() {
  if (!g_nid_added)
    return;
  Shell_NotifyIconW(NIM_DELETE, &g_nid);
  g_nid_added = false;
  printf("tray icon removed\n");
}

static void tray_soft_off() {
  HANDLE h = serial_or_invalid();
  if (h == INVALID_HANDLE_VALUE) {
    printf("tray soft_off: no serial\n");
    return;
  }
  engine_stop();
  engine_set_intent_soft_off();
  send_solid(h, "000000");
  config_set_last_scene("off");
  // 为什么：托盘改灯 UI 不知情；有客户端才推 engine/display，不回声整包 cfg
  ipc_push_runtime_status();
  printf("tray soft_off\n");
}

static void tray_start_engine() {
  HANDLE h = serial_or_invalid();
  if (h == INVALID_HANDLE_VALUE) {
    printf("tray start engine: no serial\n");
    return;
  }
  engine_start(h);
  engine_set_intent_engine();
  config_set_last_scene("engine");
  ipc_push_runtime_status();
  printf("tray start engine (map)\n");
}

static void tray_start_region() {
  HANDLE h = serial_or_invalid();
  if (h == INVALID_HANDLE_VALUE) {
    printf("tray start region: no serial\n");
    return;
  }
  engine_start_region(h);
  engine_set_intent_region();
  config_set_last_scene("region");
  ipc_push_runtime_status();
  printf("tray start region\n");
}

static void tray_toggle_autostart() {
  HelperConfig c{};
  config_copy(&c);
  bool next = !c.startOnBoot;
  config_set_autostart(next);
  // 为什么：托盘改自启，界面开着要看到 cfg；UI 自己 set 不走这里故无回声
  ipc_push_config_snapshot();
  printf("tray autostart -> %d\n", next ? 1 : 0);
}

static void tray_show_menu(HWND hwnd) {
  POINT pt;
  GetCursorPos(&pt);
  HMENU menu = CreatePopupMenu();
  if (!menu)
    return;

  // 打开界面 | 流光溢彩 屏幕氛围 关灯 | 开机自启 | 退出并关灯
  AppendMenuW(menu, MF_STRING, IDM_TRAY_OPEN_UI, L"打开界面");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

  // 为什么：无灯带时控灯项灰显；打开界面 / 自启 / 退出仍可用
  const bool has_serial = serial_or_invalid() != INVALID_HANDLE_VALUE;
  const UINT light_flags =
      MF_STRING | (has_serial ? 0u : (MF_GRAYED | MF_DISABLED));
  // 对勾读运行时 intent（与 UI display 状态同源），非 lastScene：
  // 后者是冷启动恢复用的持久化场景，suspend/断连期间与实际灯态不同步
  const DisplayIntent intent = engine_get_display_intent();
  AppendMenuW(menu,
              light_flags |
                  (intent.kind == DisplayIntentKind::Engine ? MF_CHECKED : 0),
              IDM_TRAY_START_ENGINE, L"流光溢彩");
  AppendMenuW(menu,
              light_flags |
                  (intent.kind == DisplayIntentKind::Region ? MF_CHECKED : 0),
              IDM_TRAY_START_REGION, L"屏幕氛围");
  AppendMenuW(menu,
              light_flags |
                  (intent.kind == DisplayIntentKind::SoftOff ? MF_CHECKED : 0),
              IDM_TRAY_SOFT_OFF, L"关灯");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

  HelperConfig c{};
  config_copy(&c);
  AppendMenuW(menu, MF_STRING | (c.startOnBoot ? MF_CHECKED : 0),
              IDM_TRAY_AUTOSTART, L"开机自启");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, IDM_TRAY_EXIT,
              has_serial ? L"退出并关灯" : L"退出");

  // 为什么：否则点菜单外不收起
  SetForegroundWindow(hwnd);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, pt.x, pt.y, 0, hwnd,
                 nullptr);
  PostMessageW(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);
}

static void tray_on_exit() {
  printf("tray exit\n");
  helper_shutdown();
  tray_remove_icon();
  if (g_hwnd)
    PostMessageW(g_hwnd, WM_QUIT, 0, 0);
}

static LRESULT CALLBACK tray_wnd_proc(HWND hwnd, UINT msg, WPARAM wParam,
                                      LPARAM lParam) {
  if (msg == g_taskbar_created && g_taskbar_created != 0) {
    // 为什么：explorer 重启后托盘图标丢失，必须 NIM_ADD 重挂
    g_nid_added = false;
    tray_add_icon(hwnd);
    return 0;
  }

  switch (msg) {
  case WM_SSS_OPEN_UI:
    // 次实例 PostMessage：与托盘双击同一条打开逻辑
    ui_request_open();
    return 0;

  case WM_TRAYICON: {
    // 为什么：NIM_SETVERSION(NOTIFYICON_VERSION_4) 后事件在 LOWORD(lParam)，
    // HIWORD 是图标 ID；整 lParam 去比永远对不上，右键会像“没反应”
    const UINT ev = LOWORD(lParam);
    // VERSION_4：单击优先 NIN_SELECT；兼容旧路径保留 WM_LBUTTONUP
    if (ev == NIN_SELECT || ev == NIN_KEYSELECT || ev == WM_LBUTTONUP) {
      ui_request_open();
    } else if (ev == WM_RBUTTONUP || ev == WM_CONTEXTMENU) {
      tray_show_menu(hwnd);
    }
    return 0;
  }

  case WM_COMMAND:
    switch (LOWORD(wParam)) {
    case IDM_TRAY_OPEN_UI:
      ui_request_open();
      break;
    case IDM_TRAY_START_ENGINE:
      tray_start_engine();
      break;
    case IDM_TRAY_START_REGION:
      tray_start_region();
      break;
    case IDM_TRAY_SOFT_OFF:
      tray_soft_off();
      break;
    case IDM_TRAY_AUTOSTART:
      tray_toggle_autostart();
      break;
    case IDM_TRAY_EXIT:
      tray_on_exit();
      break;
    default:
      break;
    }
    return 0;

  case WM_POWERBROADCAST:
    // sleep_sync=0 时 helper_on_suspend / resume 立刻 return
    if (wParam == PBT_APMSUSPEND || wParam == PBT_APMQUERYSUSPEND) {
      printf("power: suspend (wParam=0x%Ix) -> on_suspend\n", wParam);
      helper_on_suspend();
      return TRUE;
    }
    if (wParam == PBT_APMRESUMESUSPEND || wParam == PBT_APMRESUMEAUTOMATIC ||
        wParam == PBT_APMRESUMECRITICAL) {
      printf("power: resume (wParam=0x%Ix) -> resume_from_sleep\n", wParam);
      helper_resume_from_sleep();
      return TRUE;
    }
    break;

  case WM_QUERYENDSESSION:
    // 为什么：这里 shutdown 的话用户取消关机进程已经死了；只答应可以关
    printf("power: query end session -> allow\n");
    return TRUE;

  case WM_ENDSESSION:
    if (wParam) {
      HelperConfig c{};
      config_copy(&c);
      printf("power: end session lights=%d -> helper_shutdown\n",
             c.turnOffOnShutdown ? 1 : 0);
      helper_shutdown(c.turnOffOnShutdown);
    }
    return 0;

  case WM_DESTROY:
    tray_remove_icon();
    if (g_suspend_notify) {
      UnregisterSuspendResumeNotification(g_suspend_notify);
      g_suspend_notify = nullptr;
    }
    PostQuitMessage(0);
    return 0;

  default:
    break;
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static void tray_thread_main() {
  g_tray_tid = GetCurrentThreadId();
  g_taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");

  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = tray_wnd_proc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kTrayWndClass;
  wc.hIcon = LoadIconW(wc.hInstance, MAKEINTRESOURCEW(IDI_HELPER_TRAY));
  if (!RegisterClassExW(&wc)) {
    if (GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      printf("tray RegisterClassEx failed: %lu\n",
             (unsigned long)GetLastError());
      return;
    }
  }

  // 为什么：HWND_MESSAGE 收不到电源广播；必须用隐藏顶层窗
  HWND hwnd = CreateWindowExW(WS_EX_TOOLWINDOW, kTrayWndClass,
                              L"ScreenStripSyncTray", WS_POPUP, 0, 0, 0, 0,
                              nullptr, nullptr, wc.hInstance, nullptr);
  if (!hwnd) {
    printf("tray CreateWindowEx failed: %lu\n", (unsigned long)GetLastError());
    return;
  }
  g_hwnd = hwnd;
  ShowWindow(hwnd, SW_HIDE);

  g_suspend_notify =
      RegisterSuspendResumeNotification(hwnd, DEVICE_NOTIFY_WINDOW_HANDLE);
  if (!g_suspend_notify) {
    printf("RegisterSuspendResumeNotification failed: %lu\n",
           (unsigned long)GetLastError());
  } else {
    printf("tray suspend notify ok\n");
  }
  g_monitor_notify = RegisterPowerSettingNotification(
      hwnd, &GUID_MONITOR_POWER_ON, DEVICE_NOTIFY_WINDOW_HANDLE);
  if (!g_monitor_notify) {
    printf("RegisterPowerSettingNotification failed: %lu\n",
           (unsigned long)GetLastError());
  } else {
    printf("tray monitor notify ok\n");
  }

  tray_enable_dark_menus();
  tray_add_icon(hwnd);
  printf("tray window ok\n");

  MSG msg;
  while (!g_stop_requested.load() && GetMessageW(&msg, nullptr, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }

  tray_remove_icon();
  if (g_suspend_notify) {
    UnregisterSuspendResumeNotification(g_suspend_notify);
    g_suspend_notify = nullptr;
  }
  if (g_hwnd) {
    DestroyWindow(g_hwnd);
    g_hwnd = nullptr;
  }
  g_tray_tid = 0;
  printf("tray thread exit\n");
}

void tray_start() {
  bool expected = false;
  if (!g_started.compare_exchange_strong(expected, true))
    return;
  g_stop_requested.store(false);
  // 为什么：detach —— 主线程被 ipc_run 占用；退出靠 tray_stop / 进程结束
  std::thread(tray_thread_main).detach();
}

void tray_stop() {
  g_stop_requested.store(true);
  HWND hwnd = g_hwnd;
  if (hwnd) {
    PostMessageW(hwnd, WM_CLOSE, 0, 0);
  }
  // 短暂等待线程摘图标（进程马上退出时 OS 也会清）
  for (int i = 0; i < 50 && g_tray_tid != 0; ++i)
    Sleep(20);
  tray_remove_icon();
}
