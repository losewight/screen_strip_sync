#pragma once

#include "segment_map.h"

#include <cstddef>

// 屏幕氛围（region）取色框：被抓那块屏的百分比整数 0..100
struct RegionBBox {
  int l = 10;
  int t = 20;
  int w = 80;
  int h = 60;
};

// 与 Dart AppConfig  JSON 字段对齐；helper 为唯一写方
struct HelperConfig {
  float emaAlpha = 1.f; // UI 平滑度 = 1−α；默认 0 → α=1（跟得最快）
  int nearBlack = 0;
  int blurStep = 0;
  float saturation = 1.2f; // 0.5..2；1=原色，默认 120%
  char mode = 'a';         // 'a' | 'b'；亮度方案已废弃，仅存盘兼容
  char comPort[16] = "COM10";
  // 空 / "auto" = 按主屏再序号 0；否则 DXGI DeviceName（如 \\.\DISPLAY1）
  char captureOutput[64] = "";
  char lastConnectedCom[16] = "";
  // 首启门闩：false=须 UI 点连接才开口；true=启动可自动 try_serial
  bool serialConfigured = false;
  bool autoSleepSync = true;
  bool screenOffSync = false;
  bool turnOffOnShutdown = true;
  bool startOnBoot = false;
  bool hasMap = false;
  SegmentRect map[kSegmentCount] = {};
  // 屏幕氛围（Python region 路径）；与 map 参数正交
  char regionAlgo = 'm';     // 'm'=mean 柔和融合；'x'=max 高亮追踪
  int regionBlur = 3;        // 0..20
  float regionSmooth = 0.8f; // 0..0.99；高=更钝
  int regionDark = 15;       // 0..50
  RegionBBox regionBBox{};
  // H8：冷启动按 lastScene 恢复；运行时由场景命令更新
  // 合法：engine|region|idle|off|solid RRGGBB
  char lastScene[32] = "idle";
  // 纯色 UI「自定义」色圈；6 位小写 hex，空=未设（UI 用默认紫）
  char lastCustomSolid[8] = "";
  // 墙面色彩补偿：开关 + 墙色；空 wallColor = 未校正（启用也 no-op）
  bool wallCompEnabled = false;
  char wallColor[8] = "";
};

bool config_path(char *out, size_t cap);

// 缺文件 / 解析失败 → 全默认，不阻塞启动
void config_load();

// 把内存配置打进引擎 / sleep_sync（开串口前调用）
void config_apply();

// 持锁拷贝；禁止对外无锁读内部引用
void config_copy(HelperConfig *out);

void config_set_ema_alpha(float v);
void config_set_near_black(int v);
void config_set_blur(int v);
void config_set_saturation(float v);
void config_set_mode(char mode);
void config_set_com(const char *com); // 已规范化的 COMn
void config_set_capture_output(const char *name); // 空/"auto"/DeviceName
void config_set_sleep_sync(bool on);
void config_set_screen_off_sync(bool on);
void config_set_shutdown_off(bool on);
void config_set_autostart(bool on); // JSON + HKCU Run
void config_set_last_scene(
    const char *scene); // engine|region|idle|off|solid RRGGBB
// 6 位 hex；非法返回 false（调用方忽略）
bool config_set_last_custom_solid(const char *rrggbb);
void config_set_wall_comp(bool on);
// 6 位 hex；非法返回 false；空串清除墙色
bool config_set_wall_color(const char *rrggbb);
void config_set_last_connected_com(const char *com);
void config_set_serial_configured(bool on);
void config_clear_map();
// 从引擎快照同步 map（set map 成功后调用）
void config_sync_map_from_engine();

void config_set_region_algo(char algo); // 'm'|'x'
void config_set_region_blur(int v);
void config_set_region_smooth(float v);
void config_set_region_dark(int v);
// L,T,W,H 百分比；非法返回 false（调用方忽略）
bool config_set_region_bbox(int l, int t, int w, int h);

// 约 1s debounce 写盘；热路径只标脏
void config_request_save();
// 同步落盘（须在 saver 已停后；退出请用 config_shutdown）
void config_flush();
void config_shutdown();
