#pragma once

#include "config_store.h"

#include <string>

// 解析 / 格式化 screen_strip_sync_config.json；与落盘路径、debounce 正交。
// saw_serial_configured：非空时，若 JSON 含 serialConfigured 键则置 true。
bool config_parse_json(const char *json, HelperConfig *out,
                       bool *saw_serial_configured = nullptr);
std::string config_format_json(const HelperConfig &c);
