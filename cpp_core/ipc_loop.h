#pragma once

#include <windows.h>

// 本机回环 IPC：绑定 127.0.0.1:port，循环 accept，同时只服务一个客户端。
// 新连接踢掉旧连接；断连 / bye 只清 socket，不关灯、不退进程。
// 仅 quit 或 ipc_cancel 结束 ipc_run（随后 helper_main 走 helper_shutdown）。
// serial 传指针：重连时可替换句柄，调用方与 IPC 看到同一份最新值。
bool ipc_run(unsigned short port, HANDLE *serial);
// 从任意线程调用：关闭 socket + 置退出旗标，打断 select/accept/recv。
void ipc_cancel();
