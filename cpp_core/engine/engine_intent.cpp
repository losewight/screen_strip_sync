#include "engine_internal.h"

#include <cstdio>
#include <cstring>
#include <mutex>

void engine_set_intent_idle() {
  std::lock_guard<std::mutex> lock(g_intent_mu);
  g_intent.kind = DisplayIntentKind::Idle;
  g_intent.solid[0] = '\0';
}

void engine_set_intent_engine() {
  std::lock_guard<std::mutex> lock(g_intent_mu);
  g_intent.kind = DisplayIntentKind::Engine;
  g_intent.solid[0] = '\0';
}

void engine_set_intent_region() {
  std::lock_guard<std::mutex> lock(g_intent_mu);
  g_intent.kind = DisplayIntentKind::Region;
  g_intent.solid[0] = '\0';
}

void engine_set_intent_solid(const char *rrggbb) {
  if (rrggbb == nullptr || strlen(rrggbb) != 6)
    return;
  std::lock_guard<std::mutex> lock(g_intent_mu);
  g_intent.kind = DisplayIntentKind::Solid;
  // 规范成小写 hex，恢复时直接组帧
  for (int i = 0; i < 6; ++i) {
    char c = rrggbb[i];
    if (c >= 'A' && c <= 'F')
      c = (char)(c - 'A' + 'a');
    g_intent.solid[i] = c;
  }
  g_intent.solid[6] = '\0';
}

void engine_set_intent_soft_off() {
  std::lock_guard<std::mutex> lock(g_intent_mu);
  g_intent.kind = DisplayIntentKind::SoftOff;
  g_intent.solid[0] = '\0';
}

DisplayIntent engine_get_display_intent() {
  std::lock_guard<std::mutex> lock(g_intent_mu);
  return g_intent;
}

void apply_display_intent(HANDLE h, const DisplayIntent &intent) {
  if (h == nullptr || h == INVALID_HANDLE_VALUE) {
    printf("apply_display_intent: no serial\n");
    return;
  }
  switch (intent.kind) {
  case DisplayIntentKind::Engine:
    if (!engine_ensure_dxgi())
      return;
    engine_start(h);
    engine_set_intent_engine();
    printf("apply_display_intent: engine\n");
    break;
  case DisplayIntentKind::Region:
    if (!engine_ensure_dxgi())
      return;
    engine_start_region(h);
    engine_set_intent_region();
    printf("apply_display_intent: region\n");
    break;
  case DisplayIntentKind::Solid:
    engine_stop();
    engine_set_intent_solid(intent.solid);
    send_solid(h, intent.solid);
    printf("apply_display_intent: solid %s\n", intent.solid);
    break;
  case DisplayIntentKind::SoftOff:
    engine_stop();
    engine_set_intent_soft_off();
    send_solid(h, "000000");
    printf("apply_display_intent: soft_off\n");
    break;
  case DisplayIntentKind::Idle:
  default:
    engine_stop();
    engine_set_intent_idle();
    printf("apply_display_intent: idle\n");
    break;
  }
}

bool parse_last_scene(const char *s, DisplayIntent *out) {
  if (!s || !out)
    return false;
  DisplayIntent intent{};
  if (strcmp(s, "engine") == 0) {
    intent.kind = DisplayIntentKind::Engine;
  } else if (strcmp(s, "region") == 0) {
    intent.kind = DisplayIntentKind::Region;
  } else if (strcmp(s, "idle") == 0) {
    intent.kind = DisplayIntentKind::Idle;
  } else if (strcmp(s, "off") == 0) {
    intent.kind = DisplayIntentKind::SoftOff;
  } else if (strncmp(s, "solid ", 6) == 0) {
    const char *hex = s + 6;
    if (strlen(hex) != 6)
      return false;
    for (int i = 0; i < 6; ++i) {
      char c = hex[i];
      if (c >= 'A' && c <= 'F')
        c = (char)(c - 'A' + 'a');
      else if (c >= 'a' && c <= 'f')
        ;
      else if (c >= '0' && c <= '9')
        ;
      else
        return false;
      intent.solid[i] = c;
    }
    intent.solid[6] = '\0';
    intent.kind = DisplayIntentKind::Solid;
  } else {
    return false;
  }
  *out = intent;
  return true;
}
