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
// 有客户端则推 `ui quit\n`：后台完全退出，前端立刻 exit(0) 且不得再拉 helper。
bool ipc_push_ui_quit();
// 有客户端则推 status engine/display；无客户端不读 intent、不组包。
// include_com 仅连接快照 / reconnect / 口变更；托盘·电源默认 false。
// 与串口 120 字节帧长红线无关，本门禁只管 IPC。
bool ipc_push_runtime_status(bool include_com = false);
// 有客户端则推全量 cfg … + cfg end（不含 status ready）；托盘改自启 / clamp
// 纠偏用。
bool ipc_push_config_snapshot();
// boot 线程成功 / 放弃：对齐连接快照的 status 相位（ready / reconnect_fail）
bool ipc_push_serial_ready();
bool ipc_push_serial_fail();
