#pragma once

#include <windows.h>

// 本机回环 IPC：绑定 127.0.0.1:port，accept 单连接，按行处理直到 quit/断连。
// 失败（listen/accept）返回 false（内部已 WSACleanup）；正常结束返回 true。
// serial 由调用方持有；本函数内会调
// engine_start/stop、send_solid、power_off(off)。
bool ipc_run(unsigned short port, HANDLE serial);
