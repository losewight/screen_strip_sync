#pragma once

#include "segment_map.h"

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
// 校准向导：仅 seg 段白，其余黑；走 send_one_frame + ≥50ms
bool send_highlight(HANDLE h, int seg);
bool try_serial_ready(HANDLE *out_h);
void engine_set_alpha(float alpha);
void engine_set_near_black(int v);
void engine_set_blur(int v);
void engine_set_mode(char mode);
bool engine_set_com(const char *name);

// 映射与调色正交。payload = "x0,y0,x1,y1;..."（0..100 整数，10 段）
// 非法返回 false（IPC 忽略）；合法替换整表。
bool engine_set_map_from_ipc(const char *payload);
void engine_clear_map();
// 热路径短锁拷贝；*out_custom==false 时走 DXGI 默认顶边
void engine_copy_map_snapshot(bool *out_custom,
                              SegmentRect out_rects[kSegmentCount]);

void engine_start(HANDLE h);
void engine_request_stop();
void engine_stop();
bool engine_is_running();
void engine_get_com(char *buf, size_t cap);

void engine_set_intent_idle();
void engine_set_intent_engine();
void engine_set_intent_solid(const char *rrggbb);
void engine_set_intent_soft_off();
DisplayIntent engine_get_display_intent();
