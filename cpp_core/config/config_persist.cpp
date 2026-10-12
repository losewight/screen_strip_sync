#include "config_store_internal.h"

#include "app_paths.h"
#include "config_json.h"

#include <atomic>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>

#include <windows.h>

static std::atomic<bool> g_dirty{false};
static std::atomic<ULONGLONG> g_last_change_ms{0};
static std::atomic<bool> g_saver_stop{false};
static std::atomic<bool> g_saver_started{false};
static std::thread g_saver;

bool config_path(char *out, size_t cap) { return config_file_path(out, cap); }

bool read_config_file(const char *path, HelperConfig *out, bool *parsed_ok,
                      bool *saw_serial_configured) {
  *parsed_ok = false;
  if (saw_serial_configured)
    *saw_serial_configured = false;
  FILE *fp = nullptr;
  if (fopen_s(&fp, path, "rb") != 0 || !fp)
    return false;
  if (fseek(fp, 0, SEEK_END) != 0) {
    fclose(fp);
    return false;
  }
  long sz = ftell(fp);
  if (sz < 0 || sz > 256 * 1024) {
    fclose(fp);
    return false;
  }
  rewind(fp);
  std::vector<char> buf((size_t)sz + 1);
  size_t rd = fread(buf.data(), 1, (size_t)sz, fp);
  fclose(fp);
  buf[rd] = '\0';
  if (!config_parse_json(buf.data(), out, saw_serial_configured)) {
    *out = HelperConfig{};
    if (saw_serial_configured)
      *saw_serial_configured = false;
    return true; // 文件在，但解析失败 → 默认
  }
  *parsed_ok = true;
  return true;
}

bool write_config_file(const HelperConfig &c) {
  char path[MAX_PATH];
  if (!config_path(path, sizeof(path))) {
    printf("config_path failed\n");
    return false;
  }
  std::string json = config_format_json(c);
  // 为什么：先写临时文件再替换，避免写到一半崩溃留下半截 JSON
  char tmp[MAX_PATH];
  snprintf(tmp, sizeof(tmp), "%s.tmp", path);
  FILE *fp = nullptr;
  if (fopen_s(&fp, tmp, "wb") != 0 || !fp) {
    printf("config write open failed\n");
    return false;
  }
  size_t n = fwrite(json.data(), 1, json.size(), fp);
  fclose(fp);
  if (n != json.size()) {
    DeleteFileA(tmp);
    printf("config write short\n");
    return false;
  }
  if (!MoveFileExA(tmp, path, MOVEFILE_REPLACE_EXISTING)) {
    // 回退：直接覆盖
    if (fopen_s(&fp, path, "wb") != 0 || !fp) {
      DeleteFileA(tmp);
      printf("config replace failed\n");
      return false;
    }
    fwrite(json.data(), 1, json.size(), fp);
    fclose(fp);
    DeleteFileA(tmp);
  }
  printf("config saved\n");
  return true;
}

void mark_dirty_unlocked() {
  g_dirty.store(true);
  g_last_change_ms.store(GetTickCount64());
}

void ensure_saver_started() {
  bool expected = false;
  if (!g_saver_started.compare_exchange_strong(expected, true))
    return;
  g_saver_stop.store(false);
  g_saver = std::thread([] {
    while (!g_saver_stop.load()) {
      Sleep(200);
      if (!g_dirty.load())
        continue;
      ULONGLONG last = g_last_change_ms.load();
      if (GetTickCount64() - last < 1000)
        continue;
      HelperConfig snap;
      {
        std::lock_guard<std::mutex> lock(g_mu);
        if (!g_dirty.load())
          continue;
        snap = g_cfg;
        // 为什么：先清脏再写；失败必须挂回，否则丢盘且不再重试
        g_dirty.store(false);
      }
      if (!write_config_file(snap)) {
        std::lock_guard<std::mutex> lock(g_mu);
        g_dirty.store(true);
        // 为什么：推迟下一轮，避免磁盘满时 200ms 空转打满日志
        g_last_change_ms.store(GetTickCount64());
      }
    }
  });
}

void config_request_save() {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_flush() {
  // 调用约定：saver 已停（见 config_shutdown），否则可能与 debounce 写竞态
  HelperConfig snap;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    snap = g_cfg;
    g_dirty.store(false);
  }
  if (!write_config_file(snap)) {
    std::lock_guard<std::mutex> lock(g_mu);
    g_dirty.store(true);
  }
}

void config_shutdown() {
  // 为什么：必须先停 saver 再 flush，否则旧快照可能盖掉最新落盘
  g_saver_stop.store(true);
  if (g_saver_started.load() && g_saver.joinable())
    g_saver.join();
  g_saver_started.store(false);
  if (g_dirty.load())
    config_flush();
}
