#pragma once

#include "dxgi_capture.h"
#include "segment_map.h"

#include <cstddef>
#include <windows.h>

// 为什么：休眠记账 + 唤醒 / 冷启动按场景恢复；勿被临时黑帧冲掉
// Engine=屏幕跟色(map)；Region=屏幕氛围(整块区域)；Music=音乐动态
enum class DisplayIntentKind { Idle, Engine, Region, Music, Solid, SoftOff };

struct DisplayIntent {
  DisplayIntentKind kind = DisplayIntentKind::Idle;
  char solid[7] = {}; // RRGGBB + '\0'；仅 kind==Solid 有意义
};

// 追色热路径分派；与 IPC start / start_region / start_music 一一对应
enum class SyncPath { Map, Region, Music };

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
// 亮度模式：mode 'f'|'l'；lo/hi 0..100（BRT 原值）；map / region 各一份
void engine_set_brightness(char mode, int lo, int hi);
void engine_set_region_brightness(char mode, int lo, int hi);
void engine_set_sample_algo(char algo); // 'r'=rms, 'm'=mean
void engine_set_near_black_luma(char mode); // '6'=rec601, 'a'=avg
bool engine_set_com(const char *name);

// 屏幕氛围参数（与 map 的 alpha/near_black/blur 正交）
void engine_set_region_algo(char algo); // 'm'|'x'
void engine_set_region_blur(int v);
void engine_set_region_smooth(float v);
void engine_set_region_dark(int v);
void engine_set_region_bbox(int l, int t, int w, int h);

// 音乐动态参数（与 map / region 正交）
void engine_set_music_source(char src); // 's'|system 'i'|mic 'b'|both
void engine_set_music_layout(char layout); // 'l'|linear 'm'|mirror
void engine_set_music_reverse(bool on);
void engine_set_music_sensitivity(int v); // 0..100
void engine_set_music_decay(int v);       // 0..100
void engine_set_music_silence(char mode); // 'o'|off 'm'|min
// 镜像端点；非法返回 false。clear 用 engine_clear_music_mirror。
bool engine_set_music_mirror(const int ends[4]);
void engine_clear_music_mirror();
void engine_set_music_rest(char mode); // 'o'|off 'p'|peak 'b'|base
void engine_set_music_palette(char p); // 'v'|vu 'r'|rainbow 'f'|fixed 'l'|level 's'|screen
// RRGGBB；非法 / 000000 返回 false
bool engine_set_music_color(const char *rrggbb);

// 映射与调色正交。payload = "x0,y0,x1,y1;..."（0..100 整数，10 段）

// 非法返回 false（IPC 忽略）；合法替换整表。
bool engine_set_map_from_ipc(const char *payload);
void engine_clear_map();
// 热路径短锁拷贝；*out_custom==false 时走 DXGI 默认顶边
void engine_copy_map_snapshot(bool *out_custom,
                              SegmentRect out_rects[kSegmentCount]);

// map 共享采样：抓屏 → EMA → 饱和度 → seg_gate → out_rgb[10][3]
// timeout_ms 传给 DXGI；Music Screen 用 5，map 路径用 50。
// out_level：可选；EMA 后 / sat 前的 max(R,G,B)，暗门灭时为 0（供线性 BRT）。
DxgiErr map_sample_step(int timeout_ms, unsigned char out_rgb[10][3],
                        float out_level[10] = nullptr);

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
void engine_start_music(HANDLE h);  // SyncPath::Music；lastScene=music
void engine_request_stop();
void engine_stop();
// 停发帧 + 拆 DXGI 同一把 g_engine_mu，避免 stop 与 shutdown 之间被 start 插队
void engine_stop_and_release_dxgi();
// 换屏：停发帧 → set wanted → shutdown → init；失败回退 auto 再试
DxgiErr engine_switch_capture_output(const char *name);
bool engine_is_running();
SyncPath engine_sync_path();
void engine_get_com(char *buf, size_t cap);

void engine_set_intent_idle();
void engine_set_intent_engine();
void engine_set_intent_region();
void engine_set_intent_music();
void engine_set_intent_solid(const char *rrggbb);
void engine_set_intent_soft_off();
DisplayIntent engine_get_display_intent();
