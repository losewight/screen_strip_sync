// 强制包含（见 CMake /FI）：GUI 子系统下原生 printf 无控制台，
// 用宏把现有 printf 转到带时间戳的 helper_log_printf，调用点无需逐个改。
#pragma once

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

extern FILE *g_helper_log;

/// 打开 [path] 追加写入；已超 2MB 则先滚成 helper.log.1。
void helper_log_open(const char *path);

/// 关闭日志文件。进程退出时调用。
void helper_log_close(void);

/// 持锁 fflush；诊断导出对齐尾部用。
void helper_log_flush(void);

/// 写 `[YYYY-MM-DD HH:MM:SS] ` + 格式化正文到 g_helper_log；未打开则无操作。
int helper_log_printf(const char *fmt, ...);

/// 同源限流：相同 [key] 在 [period_ms] 内只打首条；窗口后再打时附带
/// `(+%u similar since last)`。热路径重复错误用这个，避免刷爆 helper.log。
/// [key] 用字符串字面量地址即可（同字面量同指针）。
int helper_log_rate(const void *key, unsigned period_ms, const char *fmt, ...);

#ifdef __cplusplus
}
#endif

#undef printf
#define printf(...) helper_log_printf(__VA_ARGS__)
