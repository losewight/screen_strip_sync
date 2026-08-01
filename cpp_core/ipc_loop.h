#pragma once

#include <windows.h>

// 本机回环 IPC：绑定 127.0.0.1:port，accept 单连接，按行处理直到 quit/断连。
// 失败（listen/accept）返回 false（内部已 WSACleanup）；正常结束返回 true。
// serial 传指针：重连时可替换句柄，调用方与 IPC 看到同一份最新值。
bool ipc_run(unsigned short port, HANDLE *serial);
// 从任意线程调用：关闭 socket 打断 ipc_run 的阻塞，让它干净退出。
void ipc_cancel();
