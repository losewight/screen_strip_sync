#include "config_store.h"

#include "autostart.h"
#include "helper_lifecycle.h"
#include "light_engine.h"

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
  static constexpr char kName[] = "zeeray_config.json";
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

// ---------------------------------------------------------------------------
// clamp helpers（与 engine / Dart 对齐）
// ---------------------------------------------------------------------------

static float clamp_alpha(float v) {
  if (v < 0.05f)
    return 0.05f;
  if (v > 1.f)
    return 1.f;
  return v;
}

static int clamp_near_black(int v) {
  if (v < 0)
    return 0;
  if (v > 64)
    return 64;
  return v;
}

static int clamp_blur(int v) {
  if (v < 0)
    return 0;
  if (v > 8)
    return 8;
  return v;
}

static bool valid_rect(float x0, float y0, float x1, float y1) {
  return x0 >= 0.f && y0 >= 0.f && x1 <= 1.f && y1 <= 1.f && x0 < x1 && y0 < y1;
}

// ---------------------------------------------------------------------------
// minimal JSON helpers
// ---------------------------------------------------------------------------

static void skip_ws(const char *&p) {
  while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')
    ++p;
}

static bool match_lit(const char *&p, const char *lit) {
  size_t n = strlen(lit);
  if (strncmp(p, lit, n) != 0)
    return false;
  p += n;
  return true;
}

static bool parse_string(const char *&p, char *out, size_t cap) {
  skip_ws(p);
  if (*p != '"')
    return false;
  ++p;
  size_t n = 0;
  while (*p && *p != '"') {
    char c = *p++;
    if (c == '\\' && *p) {
      char e = *p++;
      switch (e) {
      case '"':
      case '\\':
      case '/':
        c = e;
        break;
      case 'n':
        c = '\n';
        break;
      case 't':
        c = '\t';
        break;
      case 'r':
        c = '\r';
        break;
      default:
        c = e;
        break;
      }
    }
    if (n + 1 >= cap)
      return false;
    out[n++] = c;
  }
  if (*p != '"')
    return false;
  ++p;
  out[n] = '\0';
  return true;
}

static bool parse_number(const char *&p, double *out) {
  skip_ws(p);
  char *end = nullptr;
  double v = strtod(p, &end);
  if (end == p)
    return false;
  p = end;
  *out = v;
  return true;
}

static bool parse_bool(const char *&p, bool *out) {
  skip_ws(p);
  if (match_lit(p, "true")) {
    *out = true;
    return true;
  }
  if (match_lit(p, "false")) {
    *out = false;
    return true;
  }
  return false;
}

static bool skip_value(const char *&p);

static bool skip_object(const char *&p) {
  skip_ws(p);
  if (*p != '{')
    return false;
  ++p;
  skip_ws(p);
  if (*p == '}') {
    ++p;
    return true;
  }
  for (;;) {
    char key[64];
    if (!parse_string(p, key, sizeof(key)))
      return false;
    skip_ws(p);
    if (*p != ':')
      return false;
    ++p;
    if (!skip_value(p))
      return false;
    skip_ws(p);
    if (*p == ',') {
      ++p;
      continue;
    }
    if (*p == '}') {
      ++p;
      return true;
    }
    return false;
  }
}

static bool skip_array(const char *&p) {
  skip_ws(p);
  if (*p != '[')
    return false;
  ++p;
  skip_ws(p);
  if (*p == ']') {
    ++p;
    return true;
  }
  for (;;) {
    if (!skip_value(p))
      return false;
    skip_ws(p);
    if (*p == ',') {
      ++p;
      continue;
    }
    if (*p == ']') {
      ++p;
      return true;
    }
    return false;
  }
}

static bool skip_value(const char *&p) {
  skip_ws(p);
  if (*p == '"') {
    char tmp[256];
    return parse_string(p, tmp, sizeof(tmp));
  }
  if (*p == '{')
    return skip_object(p);
  if (*p == '[')
    return skip_array(p);
  if (match_lit(p, "null") || match_lit(p, "true") || match_lit(p, "false"))
    return true;
  double dummy = 0;
  return parse_number(p, &dummy);
}

static bool parse_segment_rect(const char *&p, SegmentRect *out) {
  skip_ws(p);
  if (*p != '{')
    return false;
  ++p;
  float x0 = 0, y0 = 0, x1 = 0, y1 = 0;
  bool got[4] = {};
  skip_ws(p);
  if (*p == '}')
    return false;
  for (;;) {
    char key[16];
    if (!parse_string(p, key, sizeof(key)))
      return false;
    skip_ws(p);
    if (*p != ':')
      return false;
    ++p;
    double v = 0;
    if (!parse_number(p, &v))
      return false;
    if (strcmp(key, "x0") == 0) {
      x0 = (float)v;
      got[0] = true;
    } else if (strcmp(key, "y0") == 0) {
      y0 = (float)v;
      got[1] = true;
    } else if (strcmp(key, "x1") == 0) {
      x1 = (float)v;
      got[2] = true;
    } else if (strcmp(key, "y1") == 0) {
      y1 = (float)v;
      got[3] = true;
    }
    skip_ws(p);
    if (*p == ',') {
      ++p;
      continue;
    }
    if (*p == '}') {
      ++p;
      break;
    }
    return false;
  }
  if (!(got[0] && got[1] && got[2] && got[3]))
    return false;
  if (!valid_rect(x0, y0, x1, y1))
    return false;
  out->x0 = x0;
  out->y0 = y0;
  out->x1 = x1;
  out->y1 = y1;
  return true;
}

static bool parse_segment_map(const char *&p, HelperConfig *cfg) {
  skip_ws(p);
  if (match_lit(p, "null")) {
    cfg->hasMap = false;
    return true;
  }
  if (*p != '[')
    return false;
  ++p;
  SegmentRect rects[kSegmentCount];
  int count = 0;
  skip_ws(p);
  if (*p == ']') {
    ++p;
    cfg->hasMap = false;
    return true;
  }
  for (;;) {
    if (count >= kSegmentCount)
      return false;
    if (!parse_segment_rect(p, &rects[count]))
      return false;
    ++count;
    skip_ws(p);
    if (*p == ',') {
      ++p;
      continue;
    }
    if (*p == ']') {
      ++p;
      break;
    }
    return false;
  }
  if (count != kSegmentCount) {
    cfg->hasMap = false;
    return true; // 整表丢弃，不失败整文件
  }
  for (int i = 0; i < kSegmentCount; ++i)
    cfg->map[i] = rects[i];
  cfg->hasMap = true;
  return true;
}

static bool parse_root(const char *json, HelperConfig *cfg) {
  const char *p = json;
  // UTF-8 BOM
  if ((unsigned char)p[0] == 0xEF && (unsigned char)p[1] == 0xBB &&
      (unsigned char)p[2] == 0xBF)
    p += 3;
  skip_ws(p);
  if (*p != '{')
    return false;
  ++p;
  skip_ws(p);
  if (*p == '}')
    return true;

  for (;;) {
    char key[64];
    if (!parse_string(p, key, sizeof(key)))
      return false;
    skip_ws(p);
    if (*p != ':')
      return false;
    ++p;
    skip_ws(p);

    if (strcmp(key, "emaAlpha") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->emaAlpha = clamp_alpha((float)v);
    } else if (strcmp(key, "nearBlack") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->nearBlack = clamp_near_black((int)(v + (v >= 0 ? 0.5 : -0.5)));
    } else if (strcmp(key, "blurStep") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->blurStep = clamp_blur((int)(v + (v >= 0 ? 0.5 : -0.5)));
    } else if (strcmp(key, "mode") == 0) {
      char s[8];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (s[0] == 'b' || s[0] == 'B')
        cfg->mode = 'b';
      else
        cfg->mode = 'a';
    } else if (strcmp(key, "comPort") == 0) {
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (s[0] != '\0')
        snprintf(cfg->comPort, sizeof(cfg->comPort), "%s", s);
    } else if (strcmp(key, "lastConnectedCom") == 0) {
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      snprintf(cfg->lastConnectedCom, sizeof(cfg->lastConnectedCom), "%s", s);
    } else if (strcmp(key, "autoSleepSync") == 0) {
      bool b = true;
      if (!parse_bool(p, &b))
        return false;
      cfg->autoSleepSync = b;
    } else if (strcmp(key, "turnOffOnShutdown") == 0) {
      bool b = true;
      if (!parse_bool(p, &b))
        return false;
      cfg->turnOffOnShutdown = b;
    } else if (strcmp(key, "startOnBoot") == 0) {
      bool b = false;
      if (!parse_bool(p, &b))
        return false;
      cfg->startOnBoot = b;
    } else if (strcmp(key, "lastScene") == 0) {
      char s[32];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (s[0] != '\0')
        snprintf(cfg->lastScene, sizeof(cfg->lastScene), "%s", s);
    } else if (strcmp(key, "segmentMap") == 0) {
      if (!parse_segment_map(p, cfg))
        return false;
    } else {
      if (!skip_value(p))
        return false;
    }

    skip_ws(p);
    if (*p == ',') {
      ++p;
      continue;
    }
    if (*p == '}') {
      ++p;
      skip_ws(p);
      return *p == '\0';
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// write
// ---------------------------------------------------------------------------

static void append_escaped(std::string *o, const char *s) {
  o->push_back('"');
  for (const char *p = s; *p; ++p) {
    char c = *p;
    if (c == '"' || c == '\\') {
      o->push_back('\\');
      o->push_back(c);
    } else if (c == '\n') {
      o->append("\\n");
    } else if (c == '\r') {
      o->append("\\r");
    } else if (c == '\t') {
      o->append("\\t");
    } else {
      o->push_back(c);
    }
  }
  o->push_back('"');
}

static std::string config_to_json(const HelperConfig &c) {
  char num[64];
  std::string o;
  o.reserve(1024);
  o.append("{\n");

  snprintf(num, sizeof(num), "  \"emaAlpha\": %.4g,\n", (double)c.emaAlpha);
  o.append(num);
  snprintf(num, sizeof(num), "  \"nearBlack\": %d,\n", c.nearBlack);
  o.append(num);
  snprintf(num, sizeof(num), "  \"blurStep\": %d,\n", c.blurStep);
  o.append(num);
  o.append("  \"mode\": \"");
  o.push_back(c.mode);
  o.append("\",\n");

  o.append("  \"comPort\": ");
  append_escaped(&o, c.comPort);
  o.append(",\n");
  o.append("  \"lastConnectedCom\": ");
  append_escaped(&o, c.lastConnectedCom);
  o.append(",\n");

  o.append("  \"autoSleepSync\": ");
  o.append(c.autoSleepSync ? "true" : "false");
  o.append(",\n");
  o.append("  \"turnOffOnShutdown\": ");
  o.append(c.turnOffOnShutdown ? "true" : "false");
  o.append(",\n");
  o.append("  \"startOnBoot\": ");
  o.append(c.startOnBoot ? "true" : "false");
  o.append(",\n");

  o.append("  \"lastScene\": ");
  append_escaped(&o, c.lastScene);

  if (c.hasMap) {
    o.append(",\n  \"segmentMap\": [\n");
    for (int i = 0; i < kSegmentCount; ++i) {
      const SegmentRect &r = c.map[i];
      snprintf(num, sizeof(num),
               "    {\"x0\": %.6g, \"y0\": %.6g, \"x1\": %.6g, \"y1\": %.6g}",
               (double)r.x0, (double)r.y0, (double)r.x1, (double)r.y1);
      o.append(num);
      if (i + 1 < kSegmentCount)
        o.append(",");
      o.append("\n");
    }
    o.append("  ]\n");
  } else {
    o.append("\n");
  }
  o.append("}\n");
  return o;
}

static bool write_config_file(const HelperConfig &c) {
  char path[MAX_PATH];
  if (!config_path(path, sizeof(path))) {
    printf("config_path failed\n");
    return false;
  }
  std::string json = config_to_json(c);
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

  FILE *fp = nullptr;
  if (fopen_s(&fp, path, "rb") != 0 || !fp) {
    printf("config_load: no file, defaults\n");
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg = fresh;
    return;
  }
  if (fseek(fp, 0, SEEK_END) != 0) {
    fclose(fp);
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg = fresh;
    return;
  }
  long sz = ftell(fp);
  if (sz < 0 || sz > 256 * 1024) {
    fclose(fp);
    printf("config_load: bad size, defaults\n");
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg = fresh;
    return;
  }
  rewind(fp);
  std::vector<char> buf((size_t)sz + 1);
  size_t rd = fread(buf.data(), 1, (size_t)sz, fp);
  fclose(fp);
  buf[rd] = '\0';

  if (!parse_root(buf.data(), &fresh)) {
    printf("config_load: parse fail, defaults\n");
    fresh = HelperConfig{};
  } else {
    printf("config_load: ok com=%s alpha=%.3f\n", fresh.comPort,
           (double)fresh.emaAlpha);
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
  engine_set_mode(c.mode);
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
