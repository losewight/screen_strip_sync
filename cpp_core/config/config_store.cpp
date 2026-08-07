#include "config_store.h"

#include "config_clamp.h"
#include "config_json.h"

#include "autostart.h"
#include "helper_lifecycle.h"
#include "light_engine.h"
#include "wall_comp.h"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <windows.h>

static std::mutex g_mu;
static HelperConfig g_cfg{};
static std::atomic<bool> g_dirty{false};
static std::atomic<ULONGLONG> g_last_change_ms{0};
static std::atomic<bool> g_saver_stop{false};
static std::atomic<bool> g_saver_started{false};
static std::thread g_saver;

// ---------------------------------------------------------------------------
// path
// ---------------------------------------------------------------------------

bool config_path(char *out, size_t cap) {
  if (!out || cap < 8)
    return false;
  char path[MAX_PATH];
  DWORD n = GetModuleFileNameA(nullptr, path, MAX_PATH);
  if (n == 0 || n >= MAX_PATH)
    return false;
  char *slash = strrchr(path, '\\');
  if (!slash)
    return false;
  // 为什么：先算最终长度再拼，避免长路径下 strcpy_s
  // 截断/失败后仍把坏路径交给调用方
  static constexpr char kName[] = "screen_strip_sync_config.json";
  const size_t dir_len = (size_t)(slash + 1 - path); // 含末尾 '\'
  const size_t name_len = sizeof(kName) - 1;
  const size_t need = dir_len + name_len + 1; // 含 '\0'
  if (need > MAX_PATH || need > cap)
    return false;
  if (strcpy_s(slash + 1, MAX_PATH - dir_len, kName) != 0)
    return false;
  if (strcpy_s(out, cap, path) != 0)
    return false;
  return true;
}

static bool read_config_file(const char *path, HelperConfig *out,
                             bool *parsed_ok) {
  *parsed_ok = false;
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
  if (!config_parse_json(buf.data(), out)) {
    *out = HelperConfig{};
    return true; // 文件在，但解析失败 → 默认
  }
  *parsed_ok = true;
  return true;
}

static bool write_config_file(const HelperConfig &c) {
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

static void mark_dirty_unlocked() {
  g_dirty.store(true);
  g_last_change_ms.store(GetTickCount64());
}

static void ensure_saver_started() {
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

// ---------------------------------------------------------------------------
// public API
// ---------------------------------------------------------------------------

void config_load() {
  HelperConfig fresh{};
  char path[MAX_PATH];
  if (!config_path(path, sizeof(path))) {
    printf("config_load: path fail, defaults\n");
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg = fresh;
    return;
  }

  bool parsed = false;
  if (!read_config_file(path, &fresh, &parsed)) {
    printf("config_load: no file, defaults\n");
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg = fresh;
    return;
  }

  if (parsed) {
    printf("config_load: ok com=%s alpha=%.3f\n", fresh.comPort,
           (double)fresh.emaAlpha);
  } else {
    printf("config_load: parse fail, defaults\n");
    fresh = HelperConfig{};
  }

  // 为什么：load 只改内存；规范化留给 config_apply 里的 engine_set_com
  std::lock_guard<std::mutex> lock(g_mu);
  g_cfg = fresh;
}

void config_apply() {
  HelperConfig c;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    c = g_cfg;
  }

  engine_set_alpha(c.emaAlpha);
  engine_set_near_black(c.nearBlack);
  engine_set_blur(c.blurStep);
  engine_set_saturation(c.saturation);
  engine_set_mode(c.mode);
  engine_set_region_algo(c.regionAlgo);
  engine_set_region_blur(c.regionBlur);
  engine_set_region_smooth(c.regionSmooth);
  engine_set_region_dark(c.regionDark);
  engine_set_region_bbox(c.regionBBox.l, c.regionBBox.t, c.regionBBox.w,
                         c.regionBBox.h);
  engine_set_wall_comp(c.wallCompEnabled);
  if (c.wallColor[0] != '\0')
    engine_set_wall_color(c.wallColor);
  else
    engine_clear_wall_color();
  if (!engine_set_com(c.comPort)) {
    printf("config_apply: bad com [%s], fallback COM10\n", c.comPort);
    engine_set_com("COM10");
    std::lock_guard<std::mutex> lock(g_mu);
    snprintf(g_cfg.comPort, sizeof(g_cfg.comPort), "COM10");
  } else {
    char norm[16];
    engine_get_com(norm, sizeof(norm));
    std::lock_guard<std::mutex> lock(g_mu);
    snprintf(g_cfg.comPort, sizeof(g_cfg.comPort), "%s", norm);
  }
  helper_set_sleep_sync(c.autoSleepSync);

  if (c.hasMap) {
    char payload[512];
    int n = 0;
    bool map_ok = true;
    for (int i = 0; i < kSegmentCount; ++i) {
      int x0 = (int)(c.map[i].x0 * 100.f + 0.5f);
      int y0 = (int)(c.map[i].y0 * 100.f + 0.5f);
      int x1 = (int)(c.map[i].x1 * 100.f + 0.5f);
      int y1 = (int)(c.map[i].y1 * 100.f + 0.5f);
      if (x0 < 0)
        x0 = 0;
      if (y0 < 0)
        y0 = 0;
      if (x1 > 100)
        x1 = 100;
      if (y1 > 100)
        y1 = 100;
      int w = snprintf(payload + n, sizeof(payload) - (size_t)n,
                       "%s%d,%d,%d,%d", (i == 0 ? "" : ";"), x0, y0, x1, y1);
      if (w < 0 || n + w >= (int)sizeof(payload)) {
        printf("config_apply: map payload overflow\n");
        map_ok = false;
        break;
      }
      n += w;
    }
    if (map_ok && !engine_set_map_from_ipc(payload)) {
      printf("config_apply: map reject, clear\n");
      map_ok = false;
    }
    if (!map_ok) {
      // 为什么：引擎已回退顶边均分；内存/磁盘若仍 hasMap，会双真相并写回毒表
      engine_clear_map();
      {
        std::lock_guard<std::mutex> lock(g_mu);
        g_cfg.hasMap = false;
        mark_dirty_unlocked();
      }
      ensure_saver_started();
    }
  } else {
    engine_clear_map();
  }
  printf("config_apply done\n");
}

const HelperConfig &config_get() { return g_cfg; }

void config_copy(HelperConfig *out) {
  if (!out)
    return;
  std::lock_guard<std::mutex> lock(g_mu);
  *out = g_cfg;
}

void config_set_ema_alpha(float v) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.emaAlpha = clamp_alpha(v);
    mark_dirty_unlocked();
  }
  // 为什么：建线程在锁外，避免 CreateThread 拉长 g_mu 持有时间
  ensure_saver_started();
}

void config_set_near_black(int v) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.nearBlack = clamp_near_black(v);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_blur(int v) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.blurStep = clamp_blur(v);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_saturation(float v) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.saturation = clamp_saturation(v);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_mode(char mode) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.mode = (mode == 'b' || mode == 'B') ? 'b' : 'a';
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_com(const char *com) {
  if (!com)
    return;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    snprintf(g_cfg.comPort, sizeof(g_cfg.comPort), "%s", com);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_sleep_sync(bool on) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.autoSleepSync = on;
    mark_dirty_unlocked();
  }
  ensure_saver_started();
  // 为什么：JSON 与运行时旗标必须一起改，否则只落盘、休眠仍读旧 g_sleep_sync
  helper_set_sleep_sync(on);
}

void config_set_shutdown_off(bool on) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.turnOffOnShutdown = on;
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_autostart(bool on) {
  // 为什么：JSON 是逻辑真源；注册表在锁外写，避免 Reg* 阻塞 saver
  // IPC 回推由调用方决定（托盘推；UI set 不推，避免回声）
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.startOnBoot = on;
    mark_dirty_unlocked();
  }
  ensure_saver_started();
  autostart_apply(on);
}

void config_set_region_algo(char algo) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.regionAlgo = (algo == 'x' || algo == 'X') ? 'x' : 'm';
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_region_blur(int v) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.regionBlur = clamp_region_blur(v);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_region_smooth(float v) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.regionSmooth = clamp_region_smooth(v);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_region_dark(int v) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.regionDark = clamp_region_dark(v);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

bool config_set_region_bbox(int l, int t, int w, int h) {
  if (!valid_region_bbox(l, t, w, h))
    return false;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.regionBBox.l = clamp_pct(l);
    g_cfg.regionBBox.t = clamp_pct(t);
    g_cfg.regionBBox.w = clamp_pct(w);
    g_cfg.regionBBox.h = clamp_pct(h);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
  return true;
}

bool config_set_last_custom_solid(const char *rrggbb) {
  if (!rrggbb || strlen(rrggbb) != 6)
    return false;
  char norm[8];
  for (int i = 0; i < 6; ++i) {
    char c = rrggbb[i];
    bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F');
    if (!ok)
      return false;
    if (c >= 'A' && c <= 'F')
      c = (char)(c - 'A' + 'a');
    norm[i] = c;
  }
  norm[6] = '\0';
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (strcmp(g_cfg.lastCustomSolid, norm) == 0)
      return true;
    snprintf(g_cfg.lastCustomSolid, sizeof(g_cfg.lastCustomSolid), "%s", norm);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
  printf("config_set_last_custom_solid: %s\n", norm);
  return true;
}

void config_set_wall_comp(bool on) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (g_cfg.wallCompEnabled == on)
      return;
    g_cfg.wallCompEnabled = on;
    mark_dirty_unlocked();
  }
  engine_set_wall_comp(on);
  ensure_saver_started();
  printf("config_set_wall_comp: %d\n", on ? 1 : 0);
}

bool config_set_wall_color(const char *rrggbb) {
  if (!rrggbb)
    return false;
  while (*rrggbb == ' ' || *rrggbb == '\t')
    ++rrggbb;
  if (rrggbb[0] == '\0') {
    {
      std::lock_guard<std::mutex> lock(g_mu);
      if (g_cfg.wallColor[0] == '\0')
        return true;
      g_cfg.wallColor[0] = '\0';
      mark_dirty_unlocked();
    }
    engine_clear_wall_color();
    ensure_saver_started();
    printf("config_set_wall_color: (cleared)\n");
    return true;
  }
  if (strlen(rrggbb) != 6)
    return false;
  char norm[8];
  for (int i = 0; i < 6; ++i) {
    char c = rrggbb[i];
    bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F');
    if (!ok)
      return false;
    if (c >= 'A' && c <= 'F')
      c = (char)(c - 'A' + 'a');
    norm[i] = c;
  }
  norm[6] = '\0';
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (strcmp(g_cfg.wallColor, norm) == 0)
      return true;
    snprintf(g_cfg.wallColor, sizeof(g_cfg.wallColor), "%s", norm);
    mark_dirty_unlocked();
  }
  if (!engine_set_wall_color(norm))
    return false;
  ensure_saver_started();
  printf("config_set_wall_color: %s\n", norm);
  return true;
}

void config_set_last_scene(const char *scene) {
  if (!scene)
    return;
  // 为什么：先 parse 校验+规范化 solid hex，再落盘，避免脏字符串进 JSON
  DisplayIntent parsed{};
  if (!parse_last_scene(scene, &parsed)) {
    printf("config_set_last_scene: reject [%s]\n", scene);
    return;
  }
  char normalized[32];
  switch (parsed.kind) {
  case DisplayIntentKind::Engine:
    snprintf(normalized, sizeof(normalized), "engine");
    break;
  case DisplayIntentKind::Region:
    snprintf(normalized, sizeof(normalized), "region");
    break;
  case DisplayIntentKind::SoftOff:
    snprintf(normalized, sizeof(normalized), "off");
    break;
  case DisplayIntentKind::Solid:
    snprintf(normalized, sizeof(normalized), "solid %s", parsed.solid);
    break;
  case DisplayIntentKind::Idle:
  default:
    snprintf(normalized, sizeof(normalized), "idle");
    break;
  }
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (strcmp(g_cfg.lastScene, normalized) == 0)
      return;
    snprintf(g_cfg.lastScene, sizeof(g_cfg.lastScene), "%s", normalized);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
  printf("config_set_last_scene: %s\n", normalized);
}

void config_set_last_connected_com(const char *com) {
  if (!com)
    return;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    snprintf(g_cfg.lastConnectedCom, sizeof(g_cfg.lastConnectedCom), "%s", com);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_clear_map() {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.hasMap = false;
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_sync_map_from_engine() {
  bool custom = false;
  SegmentRect rects[kSegmentCount];
  engine_copy_map_snapshot(&custom, rects);
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.hasMap = custom;
    if (custom) {
      for (int i = 0; i < kSegmentCount; ++i)
        g_cfg.map[i] = rects[i];
    }
    mark_dirty_unlocked();
  }
  ensure_saver_started();
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
