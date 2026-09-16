// 带时间戳的日志写入口；供 helper_log.h 的 printf 宏转发。
// 运行时保险丝：写完看大小，超 2MB 则关文件、滚成 .1、再打开。
#include "helper_log.h"

#include <mutex>
#include <share.h>
#include <stdarg.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#include <windows.h>

FILE *g_helper_log = nullptr;

static constexpr long long kHelperLogMaxBytes = 2LL * 1024 * 1024;
static constexpr ULONGLONG kRotateFailCooldownMs = 60ull * 1000;
static constexpr size_t kLineCap = 2048;

static std::mutex g_log_mu;
static char g_log_path[MAX_PATH] = {};
static ULONGLONG g_rotate_fail_ms = 0;

// 同目录 helper.log → helper.log.1。滚动过程禁止 printf（非递归锁会自死锁）。
static bool backup_path(char *bak, size_t cap) {
  if (g_log_path[0] == '\0' || bak == nullptr || cap < 8)
    return false;
  if (strcpy_s(bak, cap, g_log_path) != 0)
    return false;
  char *slash = strrchr(bak, '\\');
  if (!slash)
    return false;
  const size_t rest = cap - (size_t)(slash + 1 - bak);
  return strcpy_s(slash + 1, rest, "helper.log.1") == 0;
}

static bool reopen_append_unlocked() {
  if (g_log_path[0] == '\0')
    return false;
  // 为什么：_SH_DENYNO 允许验收时边跑边读；无缓冲避免日志晚到
  g_helper_log = _fsopen(g_log_path, "a", _SH_DENYNO);
  if (!g_helper_log)
    return false;
  setvbuf(g_helper_log, nullptr, _IONBF, 0);
  // 追加打开后 tell 可能还在 0；先落到末尾，运行时滚动才看得到真实大小
  _fseeki64(g_helper_log, 0, SEEK_END);
  return true;
}

static void rotate_existing_file_unlocked() {
  struct _stat64 st{};
  if (_stat64(g_log_path, &st) != 0 || st.st_size < kHelperLogMaxBytes)
    return;
  char bak[MAX_PATH];
  if (!backup_path(bak, sizeof(bak)))
    return;
  DeleteFileA(bak);
  MoveFileA(g_log_path, bak);
}

// 已持 g_log_mu。Windows 上开着的文件不能 MoveFile，必须先 fclose。
static void maybe_rotate_unlocked() {
  if (g_helper_log == nullptr)
    return;
  const long long sz = _ftelli64(g_helper_log);
  if (sz < kHelperLogMaxBytes)
    return;

  const ULONGLONG now = GetTickCount64();
  if (g_rotate_fail_ms != 0 &&
      (now - g_rotate_fail_ms) < kRotateFailCooldownMs) {
    return;
  }

  fclose(g_helper_log);
  g_helper_log = nullptr;

  char bak[MAX_PATH];
  if (!backup_path(bak, sizeof(bak))) {
    reopen_append_unlocked();
    return;
  }
  DeleteFileA(bak);
  if (!MoveFileA(g_log_path, bak)) {
    // 记事本 / 诊断导出正开着：别把指针留空，回退追加，60s 内别空转
    g_rotate_fail_ms = now;
    reopen_append_unlocked();
    return;
  }
  g_rotate_fail_ms = 0;
  reopen_append_unlocked();
}

void helper_log_open(const char *path) {
  std::lock_guard<std::mutex> lock(g_log_mu);
  if (g_helper_log != nullptr) {
    fclose(g_helper_log);
    g_helper_log = nullptr;
  }
  g_log_path[0] = '\0';
  g_rotate_fail_ms = 0;
  if (path == nullptr || path[0] == '\0')
    return;
  if (strcpy_s(g_log_path, path) != 0) {
    g_log_path[0] = '\0';
    return;
  }
  // 启动时文件还没打开，可以直接改名（保留原行为）
  rotate_existing_file_unlocked();
  reopen_append_unlocked();
}

void helper_log_close(void) {
  std::lock_guard<std::mutex> lock(g_log_mu);
  if (g_helper_log != nullptr) {
    fclose(g_helper_log);
    g_helper_log = nullptr;
  }
  g_log_path[0] = '\0';
}

void helper_log_flush(void) {
  std::lock_guard<std::mutex> lock(g_log_mu);
  if (g_helper_log != nullptr)
    fflush(g_helper_log);
}

static int format_timestamp(char *buf, size_t cap) {
  if (buf == nullptr || cap == 0)
    return 0;
  time_t now = time(nullptr);
  struct tm local{};
  if (localtime_s(&local, &now) != 0)
    return 0;
  const int n = snprintf(buf, cap, "[%04d-%02d-%02d %02d:%02d:%02d] ",
                         local.tm_year + 1900, local.tm_mon + 1, local.tm_mday,
                         local.tm_hour, local.tm_min, local.tm_sec);
  if (n < 0)
    return 0;
  if ((size_t)n >= cap)
    return (int)cap - 1;
  return n;
}

// 时间戳 + 正文拼成一行再写，避免两线程把「A 的时间戳 + B 的正文」拼在一起。
static int write_line_unlocked(const char *fmt, va_list ap) {
  if (g_helper_log == nullptr || fmt == nullptr)
    return 0;

  char buf[kLineCap];
  int n = format_timestamp(buf, sizeof(buf));
  const size_t rest = sizeof(buf) - (size_t)n;
  const int m = vsnprintf(buf + n, rest, fmt, ap);
  int total = n;
  if (m > 0) {
    if ((size_t)m >= rest) {
      total = (int)sizeof(buf) - 1;
      buf[total] = '\0';
    } else {
      total = n + m;
    }
  }

  const size_t w = fwrite(buf, 1, (size_t)total, g_helper_log);
  maybe_rotate_unlocked();
  return (int)w;
}

int helper_log_printf(const char *fmt, ...) {
  std::lock_guard<std::mutex> lock(g_log_mu);
  va_list ap;
  va_start(ap, fmt);
  const int n = write_line_unlocked(fmt, ap);
  va_end(ap);
  return n;
}

int helper_log_rate(const void *key, unsigned period_ms, const char *fmt, ...) {
  std::lock_guard<std::mutex> lock(g_log_mu);
  if (g_helper_log == nullptr || key == nullptr || fmt == nullptr)
    return 0;

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

  va_list ap;
  va_start(ap, fmt);
  int n = write_line_unlocked(fmt, ap);
  va_end(ap);

  if (similar > 0 && n > 0 && g_helper_log != nullptr) {
    char extra[kLineCap];
    const int ts = format_timestamp(extra, sizeof(extra));
    const int m =
        snprintf(extra + ts, sizeof(extra) - (size_t)ts,
                 "  (+%u similar since last)\n", similar);
    int total = ts;
    if (m > 0)
      total = ts + m;
    if (total > 0 && (size_t)total >= sizeof(extra))
      total = (int)sizeof(extra) - 1;
    if (total > 0)
      fwrite(extra, 1, (size_t)total, g_helper_log);
    maybe_rotate_unlocked();
  }
  return n;
}
