// 强制包含（见 CMake /FI）：GUI 子系统下 freopen 后 printf 仍可能丢，
// 用宏把现有 printf 转到 g_helper_log，调用点无需逐个改。
#pragma once

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif
extern FILE *g_helper_log;
#ifdef __cplusplus
}
#endif

#undef printf
#define printf(...)                                                            \
  ((g_helper_log != nullptr) ? fprintf(g_helper_log, __VA_ARGS__) : (0))
