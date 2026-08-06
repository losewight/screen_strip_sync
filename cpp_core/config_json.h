#pragma once

#include "config_store.h"

#include <string>

// 解析 / 格式化 screen_strip_sync_config.json；与落盘路径、debounce 正交。
bool config_parse_json(const char *json, HelperConfig *out);
std::string config_format_json(const HelperConfig &c);
