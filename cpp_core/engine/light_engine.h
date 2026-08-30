#pragma once

#include "segment_map.h"

#include <cstddef>
#include <windows.h>

// 为什么：休眠记账 + 唤醒 / 冷启动按场景恢复；勿被临时黑帧冲掉
// Engine=屏幕跟色(map)；Region=屏幕氛围(整块区域)
enum class DisplayIntentKind { Idle, Engine, Region, Solid, SoftOff };

struct DisplayIntent {
  DisplayIntentKind kind = DisplayIntentKind::Idle;
  char solid[7] = {}; // RRGGBB + '\0'；仅 kind==Solid 有意义
};

// 追色热路径分派；与 IPC start / start_region 一一对应
enum class SyncPath { Map, Region };

bool power_on(HANDLE h);
bool handshake(HANDLE h);
bool power_off(HANDLE h);
bool send_solid(HANDLE h, const char *rrggbb);
// 校准向导：仅 seg 段白，其余黑；节流在 send_one_frame 内
bool send_highlight(HANDLE h, int seg);
bool try_serial_ready(HANDLE *out_h);
void engine_set_alpha(float alpha);
void engine_set_near_black(int v);
void engine_set_blur(int v);
void engine_set_saturation(float v); // 0.5..2；map 路径饱和度增益
void engine_set_mode(char mode);
bool engine_set_com(const char *name);

// 屏幕氛围参数（与 map 的 alpha/near_black/blur 正交）
void engine_set_region_algo(char algo); // 'm'|'x'
void engine_set_region_blur(int v);
void engine_set_region_smooth(float v);
void engine_set_region_dark(int v);
void engine_set_region_bbox(int l, int t, int w, int h);

// 映射与调色正交。payload = "x0,y0,x1,y1;..."（0..100 整数，10 段）
// 非法返回 false（IPC 忽略）；合法替换整表。
bool engine_set_map_from_ipc(const char *payload);
void engine_clear_map();
// 热路径短锁拷贝；*out_custom==false 时走 DXGI 默认顶边
void engine_copy_map_snapshot(bool *out_custom,
                              SegmentRect out_rects[kSegmentCount]);

// 休眠拆掉 DXGI 后，追色 / 唤醒恢复前必须再 init
bool engine_ensure_dxgi();
// ACCESS_LOST 后强制拆再建（指针仍非空时 ensure 不够）
bool engine_recover_dxgi();
// 按意图恢复画面（唤醒 / 冷启动）；h 必须已就绪
void apply_display_intent(HANDLE h, const DisplayIntent &intent);
// 解析 JSON / IPC lastScene 字符串；非法返回 false
bool parse_last_scene(const char *s, DisplayIntent *out);

void engine_start(HANDLE h);        // SyncPath::Map；lastScene=engine
void engine_start_region(HANDLE h); // SyncPath::Region；lastScene=region
void engine_request_stop();
void engine_stop();
bool engine_is_running();
SyncPath engine_sync_path();
void engine_get_com(char *buf, size_t cap);

void engine_set_intent_idle();
void engine_set_intent_engine();
void engine_set_intent_region();
void engine_set_intent_solid(const char *rrggbb);
void engine_set_intent_soft_off();
DisplayIntent engine_get_display_intent();
