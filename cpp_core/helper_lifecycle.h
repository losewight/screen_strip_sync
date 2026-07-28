#pragma once

#include <windows.h>

// 为什么：Ctrl / 电源消息 / main 尾部共用同一套关灯顺序，防重复释放
void helper_set_serial(HANDLE *serial);
void helper_shutdown();
