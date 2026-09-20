#pragma once

#include "config_store.h"

#include <windows.h>

// 为什么：Ctrl / 电源消息 / main 尾部共用同一套关灯顺序，防重复释放
// 串口 HANDLE 进程级属主；禁止放在 WinMain 栈上再让唤醒线程写
HANDLE *helper_serial();
void helper_shutdown(bool turn_off_lights = true);
bool helper_is_shutting_down();

// sleep_sync=0：休眠完全不插手（不拆 COM/DXGI、不关灯、唤醒也不恢复）
void helper_set_sleep_sync(bool on);
bool helper_get_sleep_sync();

// screen_off_sync: 控制显示器息屏时是否关灯（与 sleep_sync 独立）
void helper_set_screen_off_sync(bool on);
bool helper_get_screen_off_sync();

// 显示器息屏：停引擎 + 发黑帧，不污染 g_intent / lastScene
void helper_on_monitor_off();
// 显示器亮屏：按 g_intent 恢复
void helper_on_monitor_on();

void helper_on_suspend();
void helper_resume_from_sleep();
// reconnect / 唤醒成功后清除「已拆资源」旗标，允许下次再 suspend
void helper_note_resources_ready();

// 启动期：串口开口 + lastScene 丢到短命线程，主路径可先 listen 拉 UI
void helper_boot_serial_async(const HelperConfig &boot_cfg);
// reconnect / shutdown：等 boot 结束，禁止与开口并行
void helper_boot_serial_wait();
// 连接快照：boot 仍在开口时推 reconnecting，勿当失败
bool helper_boot_serial_busy();
