#include "config_store_internal.h"

#include "config_clamp.h"

#include "autostart.h"
#include "helper_lifecycle.h"
#include "letterbox_detect.h"
#include "light_engine.h"
#include "music_layout.h"
#include "subtitle_detect.h"
#include "wall_comp.h"

#include <cstdio>
#include <cstring>
#include <mutex>

#include <windows.h>

std::mutex g_mu;
HelperConfig g_cfg{};

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
  bool saw_serial = false;
  if (!read_config_file(path, &fresh, &parsed, &saw_serial)) {
    printf("config_load: no file, defaults\n");
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg = fresh;
    return;
  }

  bool inferred = false;
  bool map_defaults = false;
  if (parsed) {
    // 为什么：旧 JSON 无 serialConfigured 时，有 lastConnectedCom 视为已配备
    if (!saw_serial) {
      fresh.serialConfigured = fresh.lastConnectedCom[0] != '\0';
      inferred = true;
      printf("config_load: serialConfigured inferred=%d from lastCom\n",
             fresh.serialConfigured ? 1 : 0);
    }
    // 为什么：1.1.0 跟色推荐默认；只改这几项，COM/map/氛围等不动
    if (fresh.mapDefaultsRev < 1) {
      fresh.emaAlpha = 1.f;
      fresh.blurStep = 0;
      fresh.nearBlack = 30;
      fresh.saturation = 1.f;
      fresh.saturationAlgo = 'n';
      fresh.letterboxDetect = true;
      fresh.mapDefaultsRev = 1;
      map_defaults = true;
      printf("config_load: mapDefaultsRev bump → nearBlack=30 sat=1 letterbox=1\n");
    }
    printf("config_load: ok com=%s serialConfigured=%d alpha=%.3f capture=%s\n",
           fresh.comPort, fresh.serialConfigured ? 1 : 0,
           (double)fresh.emaAlpha,
           fresh.captureOutput[0] ? fresh.captureOutput : "(auto)");
  } else {
    printf("config_load: parse fail, defaults\n");
    fresh = HelperConfig{};
  }

  // 为什么：load 只改内存；规范化留给 config_apply 里的 engine_set_com
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg = fresh;
    if (inferred || map_defaults)
      mark_dirty_unlocked();
  }
  if (inferred || map_defaults)
    ensure_saver_started();
}

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
  // 为什么：开串口前必须把内存配置打进引擎；否则串口已开，UI set alpha 也不推
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

void config_set_saturation_algo(char algo) {
  (void)algo;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    // UI 已撤；固定减去中性色，忽略 IPC/旧调用传入的 luma
    g_cfg.saturationAlgo = 'n';
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_sample_algo(char algo) {
  (void)algo;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    // UI 已撤；固定 mean，忽略 IPC/旧调用传入的 rms。
    g_cfg.sampleAlgo = 'm';
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_near_black_luma(char mode) {
  (void)mode;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    // UI 已撤；固定 Rec.601，忽略 IPC/旧调用传入的 mean。
    g_cfg.nearBlackLuma = '6';
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

void config_set_capture_output(const char *name) {
  char clamped[64];
  clamp_capture_output(name, clamped, (int)sizeof(clamped));
  {
    std::lock_guard<std::mutex> lock(g_mu);
    snprintf(g_cfg.captureOutput, sizeof(g_cfg.captureOutput), "%s", clamped);
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

void config_set_screen_off_sync(bool on) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.screenOffSync = on;
    mark_dirty_unlocked();
  }
  ensure_saver_started();
  helper_set_screen_off_sync(on);
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

void config_set_music_source(char src) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.musicSource = clamp_music_source(src);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_music_layout(char layout) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.musicLayout = clamp_music_layout(layout);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_music_reverse(bool on) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.musicReverse = on;
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_music_sensitivity(int v) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.musicSensitivity = clamp_music_pct(v);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_music_decay(int v) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.musicDecay = clamp_music_pct(v);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_music_silence(char mode) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.musicSilence = clamp_music_silence(mode);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

bool config_set_music_mirror(const int ends[4]) {
  if (!ends)
    return false;
  const bool clear =
      ends[0] < 0 && ends[1] < 0 && ends[2] < 0 && ends[3] < 0;
  if (!clear) {
    // 相交 / 越界：与 IPC 一致，拒写
    MusicLayout lay{};
    if (!music_layout_mirror(ends, &lay))
      return false;
  }
  {
    std::lock_guard<std::mutex> lock(g_mu);
    for (int i = 0; i < 4; ++i)
      g_cfg.musicMirror[i] = clear ? -1 : ends[i];
    mark_dirty_unlocked();
  }
  ensure_saver_started();
  return true;
}

void config_clear_music_mirror() {
  const int cleared[4] = {-1, -1, -1, -1};
  (void)config_set_music_mirror(cleared);
}

void config_set_music_rest(char mode) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.musicRest = clamp_music_rest(mode);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

void config_set_music_palette(char p) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_cfg.musicPalette = clamp_music_palette(p);
    mark_dirty_unlocked();
  }
  ensure_saver_started();
}

bool config_set_music_color(const char *rrggbb) {
  char norm[8];
  if (!clamp_music_color(rrggbb, norm, (int)sizeof(norm)))
    return false;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (strcmp(g_cfg.musicColor, norm) == 0)
      return true;
    snprintf(g_cfg.musicColor, sizeof(g_cfg.musicColor), "%s", norm);
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

void config_set_letterbox_detect(bool on) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (g_cfg.letterboxDetect == on)
      return;
    g_cfg.letterboxDetect = on;
    mark_dirty_unlocked();
  }
  // enable/inset 日志在 letterbox_set_enabled
  letterbox_set_enabled(on);
  ensure_saver_started();
}

void config_set_subtitle_detect(bool on) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (g_cfg.subtitleDetect == on)
      return;
    g_cfg.subtitleDetect = on;
    mark_dirty_unlocked();
  }
  subtitle_set_enabled(on);
  ensure_saver_started();
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
  case DisplayIntentKind::Music:
    snprintf(normalized, sizeof(normalized), "music");
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

void config_set_serial_configured(bool on) {
  {
    std::lock_guard<std::mutex> lock(g_mu);
    if (g_cfg.serialConfigured == on)
      return;
    g_cfg.serialConfigured = on;
    mark_dirty_unlocked();
  }
  ensure_saver_started();
  printf("config_set_serial_configured: %d\n", on ? 1 : 0);
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
