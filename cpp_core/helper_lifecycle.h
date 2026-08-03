#pragma once

#include <windows.h>

// 为什么：Ctrl / 电源消息 / main 尾部共用同一套关灯顺序，防重复释放
void helper_set_serial(HANDLE *serial);
// 托盘/其它线程读同一串口指针；可能为 null，或 * 为 INVALID_HANDLE_VALUE
HANDLE *helper_serial();
void helper_shutdown();

// 开=休眠硬关进程；关=休眠不插手。唤醒是否自动连由 Flutter autoSleepSync 决定。
void helper_set_sleep_sync(bool on);
bool helper_get_sleep_sync();
