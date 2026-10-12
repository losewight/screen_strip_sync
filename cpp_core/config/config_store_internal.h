#pragma once

#include "config_store.h"

#include <mutex>

// 同目录 TU 共享：g_mu/g_cfg 定义在 config_store.cpp；脏标记与 saver 在
// config_persist.cpp。

extern std::mutex g_mu;
extern HelperConfig g_cfg;

void mark_dirty_unlocked();
void ensure_saver_started();

bool read_config_file(const char *path, HelperConfig *out, bool *parsed_ok,
                      bool *saw_serial_configured);
bool write_config_file(const HelperConfig &c);
