#pragma once

#include <windows.h>

// 为什么：Ctrl / 电源消息 / main 尾部共用同一套关灯顺序，防重复释放
// 串口 HANDLE 进程级属主；禁止放在 WinMain 栈上再让唤醒线程写
HANDLE *helper_serial();
void helper_shutdown(bool turn_off_lights = true);
bool helper_is_shutting_down();

// sleep_sync=0：休眠完全不插手（不拆 COM/DXGI、不关灯、唤醒也不恢复）
void helper_set_sleep_sync(bool on);
bool helper_get_sleep_sync();

void helper_on_suspend();
void helper_resume_from_sleep();
// reconnect / 唤醒成功后清除「已拆资源」旗标，允许下次再 suspend
void helper_note_resources_ready();
