// 带时间戳的日志写入口；供 helper_log.h 的 printf 宏转发。
#include "helper_log.h"

#include <stdarg.h>
#include <time.h>

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

FILE *g_helper_log = nullptr;

static void write_timestamp() {
  if (g_helper_log == nullptr) {
    return;
  }
  time_t now = time(nullptr);
  struct tm local{};
  if (localtime_s(&local, &now) == 0) {
    fprintf(g_helper_log, "[%04d-%02d-%02d %02d:%02d:%02d] ",
            local.tm_year + 1900, local.tm_mon + 1, local.tm_mday,
            local.tm_hour, local.tm_min, local.tm_sec);
  }
}

int helper_log_printf(const char *fmt, ...) {
  if (g_helper_log == nullptr) {
    return 0;
  }

  write_timestamp();

  va_list ap;
  va_start(ap, fmt);
  const int n = vfprintf(g_helper_log, fmt, ap);
  va_end(ap);
  return n;
}

int helper_log_rate(const void *key, unsigned period_ms, const char *fmt, ...) {
  if (g_helper_log == nullptr || key == nullptr || fmt == nullptr) {
    return 0;
  }

  // 少量槽位够热路径用；满了则退化成直接打（不丢诊断）
  struct Slot {
    const void *key;
    ULONGLONG last_ms;
    unsigned suppressed;
  };
  static Slot slots[8] = {};

  const ULONGLONG now = GetTickCount64();
  Slot *slot = nullptr;
  for (int i = 0; i < 8; ++i) {
    if (slots[i].key == key) {
      slot = &slots[i];
      break;
    }
  }
  if (slot == nullptr) {
    for (int i = 0; i < 8; ++i) {
      if (slots[i].key == nullptr) {
        slot = &slots[i];
        slot->key = key;
        slot->last_ms = 0;
        slot->suppressed = 0;
        break;
      }
    }
  }

  if (slot != nullptr && slot->last_ms != 0 &&
      (now - slot->last_ms) < (ULONGLONG)period_ms) {
    ++slot->suppressed;
    return 0;
  }

  unsigned similar = 0;
  if (slot != nullptr) {
    similar = slot->suppressed;
    slot->suppressed = 0;
    slot->last_ms = now;
  }

  write_timestamp();

  va_list ap;
  va_start(ap, fmt);
  int n = vfprintf(g_helper_log, fmt, ap);
  va_end(ap);

  // 为什么：正文多半以 \n 结尾；把汇总插在换行前
  if (similar > 0 && n > 0 && g_helper_log != nullptr) {
    // 回退一个 '\n'（若有），写汇总再换行
    // 简单做法：再打一行汇总，避免改已写出的缓冲
    write_timestamp();
    fprintf(g_helper_log, "  (+%u similar since last)\n", similar);
  }
  return n;
}
