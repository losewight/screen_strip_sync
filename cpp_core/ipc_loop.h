#pragma once

#include <windows.h>

// 本机回环 IPC：绑定 127.0.0.1:port，循环 accept，同时只服务一个客户端。
// 新连接踢掉旧连接；断连 / bye 只清 socket，不关灯、不退进程。
// 仅 quit 或 ipc_cancel 结束 ipc_run（随后 helper_main 走 helper_shutdown）。
// serial 传指针：重连时可替换句柄，调用方与 IPC 看到同一份最新值。
// launch_ui：listen 就绪后拉一次 Flutter（静默启动传 false）。
bool ipc_run(unsigned short port, HANDLE *serial, bool launch_ui = false);
// 从任意线程调用：关闭 socket + 置退出旗标，打断 select/accept/recv。
void ipc_cancel();

// 非热路径：托盘 / ui_launcher 查询是否有活跃 Flutter 客户端。
bool ipc_has_client();
// 有客户端则推 `ui show\n` 置顶窗口；无则返回 false。可从托盘线程调用。
bool ipc_push_ui_show();
// 有客户端则推 status com/engine/display；休眠末 / 唤醒后调用。
bool ipc_push_runtime_status();
