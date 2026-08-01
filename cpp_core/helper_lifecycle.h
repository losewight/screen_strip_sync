#pragma once

#include <windows.h>

// 为什么：Ctrl / 电源消息 / main 尾部共用同一套关灯顺序，防重复释放
void helper_set_serial(HANDLE *serial);
void helper_shutdown();

// 开=休眠硬关进程；关=休眠不插手。唤醒是否自动连由 Flutter autoSleepSync 决定。
void helper_set_sleep_sync(bool on);
bool helper_get_sleep_sync();
