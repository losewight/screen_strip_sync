#pragma once

#include <cstddef>
#include <windows.h>

// 为什么：休眠唤醒要完整恢复现场已改 Flutter；此处仅记账供 status display
enum class DisplayIntentKind { Idle, Engine, Solid, SoftOff };

struct DisplayIntent {
  DisplayIntentKind kind = DisplayIntentKind::Idle;
  char solid[7] = {}; // RRGGBB + '\0'；仅 kind==Solid 有意义
};

bool power_on(HANDLE h);
bool handshake(HANDLE h);
bool power_off(HANDLE h);
bool send_solid(HANDLE h, const char *rrggbb);
// 为什么：开端口成功还不够，握手通才算设备就绪；重连与启动共用
bool try_serial_ready(HANDLE *out_h);
// 为什么：IPC 热路径外写 α，发帧线程只 load；越界在此 clamp，调用方不必再夹
void engine_set_alpha(float alpha);
// 为什么：先存后用；阶段 C 前引擎不读，b 与 a 观感相同
void engine_set_mode(char mode);
// 为什么：只改配置；真正切口靠 reconnect → try_serial_ready
// 合法返回 true 并写入规范名 COMn；非法返回 false（调用方忽略）
bool engine_set_com(const char *name);
void engine_start(HANDLE h);
// 只置停止标志、不 join；休眠关灯前先喊停，避免 join 拖死写串口窗口
void engine_request_stop();
void engine_stop();
// 为什么：IPC 状态上报只读快照；热路径仍用 atomic/mutex 内已有数据
bool engine_is_running();
void engine_get_com(char *buf, size_t cap);

// 显示意图：IPC 用户命令写入，供 status display 对齐 UI 徽标
void engine_set_intent_idle();
void engine_set_intent_engine();
void engine_set_intent_solid(const char *rrggbb);
void engine_set_intent_soft_off();
DisplayIntent engine_get_display_intent();
