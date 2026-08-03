#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

// 次实例 → 首实例托盘窗：打开界面（与 WM_TRAYICON 错开）
constexpr UINT WM_ZEERAY_OPEN_UI = WM_APP + 2;

// 托盘类名：次实例 FindWindow 与 tray_icon RegisterClass 必须一致
constexpr wchar_t kTrayWndClass[] = L"ZeerayHelperTray";

// 三级判定：有客户端 → ui show；子进程/冷却存活 → 不动；否则 CreateProcess
void ui_request_open();

// 正常启动拉一次 UI；--autostart / --no-ui 时 silent=true 跳过
void ui_maybe_launch_on_start(bool silent);

// 次实例：找到首实例托盘窗 PostMessage，然后调用方立刻退出
void ui_notify_running_instance();

// 只关子进程句柄，不杀 Flutter
void ui_shutdown();
