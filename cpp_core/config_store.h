#pragma once

#include "segment_map.h"

#include <cstddef>

// 与 Dart AppConfig JSON 字段对齐；helper 为唯一写方（F2 前 Flutter
// 仍可能双写）
struct HelperConfig {
  float emaAlpha = 0.3f;
  int nearBlack = 12;
  int blurStep = 2;
  char mode = 'a'; // 'a' | 'b'
  char comPort[16] = "COM10";
  char lastConnectedCom[16] = "";
  bool autoSleepSync = true;
  bool turnOffOnShutdown = true;
  bool startOnBoot = false;
  bool hasMap = false;
  SegmentRect map[kSegmentCount] = {};
  // H8 才按场景恢复；本步只读写
  char lastScene[32] = "idle";
};

bool config_path(char *out, size_t cap);

// 缺文件 / 解析失败 → 全默认，不阻塞启动
void config_load();

// 把内存配置打进引擎 / sleep_sync（开串口前调用）
void config_apply();

const HelperConfig &config_get();
// 持锁拷贝，供 IPC 组 cfg 快照
void config_copy(HelperConfig *out);

void config_set_ema_alpha(float v);
void config_set_near_black(int v);
void config_set_blur(int v);
void config_set_mode(char mode);
void config_set_com(const char *com); // 已规范化的 COMn
void config_set_sleep_sync(bool on);
void config_set_shutdown_off(bool on);
void config_set_autostart(bool on); // 本步只落 JSON；注册表 H7
void config_set_last_connected_com(const char *com);
void config_clear_map();
// 从引擎快照同步 map（set map 成功后调用）
void config_sync_map_from_engine();

// 约 1s debounce 写盘；热路径只标脏
void config_request_save();
// 同步落盘（须在 saver 已停后；退出请用 config_shutdown）
void config_flush();
void config_shutdown();
