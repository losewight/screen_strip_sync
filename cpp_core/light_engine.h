#pragma once

#include <windows.h>

bool power_on(HANDLE h);
bool handshake(HANDLE h);
bool power_off(HANDLE h);
bool send_solid(HANDLE h, const char *rrggbb);
// 为什么：开端口成功还不够，握手通才算设备就绪；重连与启动共用
bool try_serial_ready(HANDLE *out_h);
void engine_start(HANDLE h);
// 只置停止标志、不 join；休眠关灯前先喊停，避免 join 拖死写串口窗口
void engine_request_stop();
void engine_stop();
