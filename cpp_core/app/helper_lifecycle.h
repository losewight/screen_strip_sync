#pragma once

#include <windows.h>

// 为什么：Ctrl / 电源消息 / main 尾部共用同一套关灯顺序，防重复释放
void helper_set_serial(HANDLE *serial);
// 托盘/其它线程读同一串口指针；可能为 null，或 * 为 INVALID_HANDLE_VALUE
HANDLE *helper_serial();
void helper_shutdown();

// sleep_sync：只决定醒来是否恢复；休眠拆资源两边相同
void helper_set_sleep_sync(bool on);
bool helper_get_sleep_sync();

// 休眠：可选快照 + 统一软关灯/弃串口/idle/关 DXGI；进程与 IPC 存活
void helper_on_suspend();
// 唤醒：仅 sleep_sync 开且有快照时恢复；否则不动作
void helper_resume_from_sleep();
// reconnect / 唤醒成功后清除「已拆资源」旗标，允许下次再 suspend
void helper_note_resources_ready();
