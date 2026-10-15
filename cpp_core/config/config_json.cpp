#include "config_json.h"

#include "config_clamp.h"
#include "music_layout.h"

#include <cstdio>
#include <cstring>
#include <string>

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

static bool parse_region_bbox_obj(const char *&p, RegionBBox *out) {
  skip_ws(p);
  if (*p != '{')
    return false;
  ++p;
  int l = 10, t = 20, w = 80, h = 60;
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
    const int iv = (int)(v + (v >= 0 ? 0.5 : -0.5));
    if (strcmp(key, "l") == 0) {
      l = iv;
      got[0] = true;
    } else if (strcmp(key, "t") == 0) {
      t = iv;
      got[1] = true;
    } else if (strcmp(key, "w") == 0) {
      w = iv;
      got[2] = true;
    } else if (strcmp(key, "h") == 0) {
      h = iv;
      got[3] = true;
    }
    skip_ws(p);
    if (*p == ',') {
      ++p;
      continue;
    }
    if (*p == '}') {
      ++p;
      if (!(got[0] && got[1] && got[2] && got[3]))
        return false;
      if (!valid_region_bbox(l, t, w, h))
        return false;
      out->l = clamp_pct(l);
      out->t = clamp_pct(t);
      out->w = clamp_pct(w);
      out->h = clamp_pct(h);
      return true;
    }
    return false;
  }
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

bool config_parse_json(const char *json, HelperConfig *cfg,
                       bool *saw_serial_configured) {
  if (saw_serial_configured)
    *saw_serial_configured = false;
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
  // 为什么：旧 JSON 无此字段时视为 0，config_load 套用跟色推荐默认一次
  cfg->mapDefaultsRev = 0;
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
    } else if (strcmp(key, "saturation") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->saturation = clamp_saturation((float)v);
    } else if (strcmp(key, "brightnessMode") == 0) {
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (strcmp(s, "linear") == 0 || s[0] == 'l' || s[0] == 'L')
        cfg->brightnessMode = 'l';
      else
        cfg->brightnessMode = 'f';
    } else if (strcmp(key, "brightnessLo") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->brightnessLo = clamp_pct((int)(v + (v >= 0 ? 0.5 : -0.5)));
    } else if (strcmp(key, "brightnessHi") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->brightnessHi = clamp_pct((int)(v + (v >= 0 ? 0.5 : -0.5)));
    } else if (strcmp(key, "regionBrightnessMode") == 0) {
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (strcmp(s, "linear") == 0 || s[0] == 'l' || s[0] == 'L')
        cfg->regionBrightnessMode = 'l';
      else
        cfg->regionBrightnessMode = 'f';
    } else if (strcmp(key, "regionBrightnessLo") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->regionBrightnessLo = clamp_pct((int)(v + (v >= 0 ? 0.5 : -0.5)));
    } else if (strcmp(key, "regionBrightnessHi") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->regionBrightnessHi = clamp_pct((int)(v + (v >= 0 ? 0.5 : -0.5)));
    } else if (strcmp(key, "saturationAlgo") == 0) {
      // 固定减去中性色；旧 JSON 的 luma 读入后钳为 neutral
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      cfg->saturationAlgo = 'n';
    } else if (strcmp(key, "sampleAlgo") == 0) {
      // 固定算术平均；旧 JSON 的 rms 读入后钳为 mean。
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      cfg->sampleAlgo = 'm';
    } else if (strcmp(key, "nearBlackLuma") == 0) {
      // 固定 Rec.601；旧 JSON 的 mean 读入后钳为 rec601。
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      cfg->nearBlackLuma = '6';
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
    } else if (strcmp(key, "captureOutput") == 0) {
      // 大缓冲再截断：超长名字不能让整份 JSON 解析失败
      char s[256];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      clamp_capture_output(s, cfg->captureOutput, (int)sizeof(cfg->captureOutput));
    } else if (strcmp(key, "lastConnectedCom") == 0) {
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      snprintf(cfg->lastConnectedCom, sizeof(cfg->lastConnectedCom), "%s", s);
    } else if (strcmp(key, "serialConfigured") == 0) {
      bool b = false;
      if (!parse_bool(p, &b))
        return false;
      cfg->serialConfigured = b;
      if (saw_serial_configured)
        *saw_serial_configured = true;
    } else if (strcmp(key, "autoSleepSync") == 0) {
      bool b = true;
      if (!parse_bool(p, &b))
        return false;
      cfg->autoSleepSync = b;
    } else if (strcmp(key, "screenOffSync") == 0) {
      bool b = false;
      if (!parse_bool(p, &b))
        return false;
      cfg->screenOffSync = b;
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
    } else if (strcmp(key, "lastCustomSolid") == 0) {
      char s[8];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      // 缺/非法保持默认空串；合法则小写落内存
      if (strlen(s) == 6) {
        bool ok = true;
        for (int i = 0; i < 6; ++i) {
          char c = s[i];
          if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
                (c >= 'A' && c <= 'F'))) {
            ok = false;
            break;
          }
          if (c >= 'A' && c <= 'F')
            s[i] = (char)(c - 'A' + 'a');
        }
        if (ok)
          snprintf(cfg->lastCustomSolid, sizeof(cfg->lastCustomSolid), "%s", s);
      }
    } else if (strcmp(key, "wallCompEnabled") == 0) {
      bool b = false;
      if (!parse_bool(p, &b))
        return false;
      cfg->wallCompEnabled = b;
    } else if (strcmp(key, "letterboxDetect") == 0) {
      bool b = false;
      if (!parse_bool(p, &b))
        return false;
      cfg->letterboxDetect = b;
    } else if (strcmp(key, "subtitleDetect") == 0) {
      bool b = false;
      if (!parse_bool(p, &b))
        return false;
      cfg->subtitleDetect = b;
    } else if (strcmp(key, "mapDefaultsRev") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->mapDefaultsRev = (int)(v + (v >= 0 ? 0.5 : -0.5));
    } else if (strcmp(key, "wallColor") == 0) {
      char s[8];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (s[0] == '\0') {
        cfg->wallColor[0] = '\0';
      } else if (strlen(s) == 6) {
        bool ok = true;
        for (int i = 0; i < 6; ++i) {
          char c = s[i];
          if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
                (c >= 'A' && c <= 'F'))) {
            ok = false;
            break;
          }
          if (c >= 'A' && c <= 'F')
            s[i] = (char)(c - 'A' + 'a');
        }
        if (ok)
          snprintf(cfg->wallColor, sizeof(cfg->wallColor), "%s", s);
      }
    } else if (strcmp(key, "regionAlgo") == 0) {
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (strcmp(s, "max") == 0 || s[0] == 'x' || s[0] == 'X')
        cfg->regionAlgo = 'x';
      else
        cfg->regionAlgo = 'm';
    } else if (strcmp(key, "regionBlur") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->regionBlur = clamp_region_blur((int)(v + (v >= 0 ? 0.5 : -0.5)));
    } else if (strcmp(key, "regionSmooth") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->regionSmooth = clamp_region_smooth((float)v);
    } else if (strcmp(key, "regionDark") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->regionDark = clamp_region_dark((int)(v + (v >= 0 ? 0.5 : -0.5)));
    } else if (strcmp(key, "regionBBox") == 0) {
      RegionBBox box{};
      if (!parse_region_bbox_obj(p, &box))
        return false;
      cfg->regionBBox = box;
    } else if (strcmp(key, "musicSource") == 0) {
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (strcmp(s, "mic") == 0 || s[0] == 'i' || s[0] == 'I')
        cfg->musicSource = 'i';
      else if (strcmp(s, "both") == 0 || s[0] == 'b' || s[0] == 'B')
        cfg->musicSource = 'b';
      else
        cfg->musicSource = 's';
    } else if (strcmp(key, "musicLayout") == 0) {
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (strcmp(s, "mirror") == 0 || s[0] == 'm' || s[0] == 'M')
        cfg->musicLayout = 'm';
      else
        cfg->musicLayout = 'l';
    } else if (strcmp(key, "musicReverse") == 0) {
      bool v = false;
      if (!parse_bool(p, &v))
        return false;
      cfg->musicReverse = v;
    } else if (strcmp(key, "musicSensitivity") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->musicSensitivity =
          clamp_music_pct((int)(v + (v >= 0 ? 0.5 : -0.5)));
    } else if (strcmp(key, "musicDecay") == 0) {
      double v = 0;
      if (!parse_number(p, &v))
        return false;
      cfg->musicDecay = clamp_music_pct((int)(v + (v >= 0 ? 0.5 : -0.5)));
    } else if (strcmp(key, "musicSilence") == 0) {
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (strcmp(s, "min") == 0 || s[0] == 'm' || s[0] == 'M')
        cfg->musicSilence = 'm';
      else
        cfg->musicSilence = 'o';
    } else if (strcmp(key, "musicMirror") == 0) {
      skip_ws(p);
      if (*p == 'n' || *p == 'N') {
        // null
        if (!skip_value(p))
          return false;
        cfg->musicMirror[0] = cfg->musicMirror[1] = cfg->musicMirror[2] =
            cfg->musicMirror[3] = -1;
      } else if (*p == '[') {
        ++p;
        int ends[4] = {-1, -1, -1, -1};
        for (int i = 0; i < 4; ++i) {
          skip_ws(p);
          double v = 0;
          if (!parse_number(p, &v))
            return false;
          ends[i] = (int)(v + (v >= 0 ? 0.5 : -0.5));
          skip_ws(p);
          if (i < 3) {
            if (*p != ',')
              return false;
            ++p;
          }
        }
        skip_ws(p);
        if (*p != ']')
          return false;
        ++p;
        MusicLayout lay{};
        if (ends[0] < 0 && ends[1] < 0 && ends[2] < 0 && ends[3] < 0) {
          for (int i = 0; i < 4; ++i)
            cfg->musicMirror[i] = -1;
        } else if (music_layout_mirror(ends, &lay)) {
          for (int i = 0; i < 4; ++i)
            cfg->musicMirror[i] = ends[i];
        } else {
          for (int i = 0; i < 4; ++i)
            cfg->musicMirror[i] = -1;
        }
      } else {
        return false;
      }
    } else if (strcmp(key, "musicRest") == 0) {
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (strcmp(s, "peak") == 0 || s[0] == 'p' || s[0] == 'P')
        cfg->musicRest = 'p';
      else if (strcmp(s, "base") == 0 || s[0] == 'b' || s[0] == 'B')
        cfg->musicRest = 'b';
      else
        cfg->musicRest = 'o';
    } else if (strcmp(key, "musicPalette") == 0) {
      char s[16];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      if (strcmp(s, "rainbow") == 0 || s[0] == 'r' || s[0] == 'R')
        cfg->musicPalette = 'r';
      else if (strcmp(s, "fixed") == 0 || s[0] == 'f' || s[0] == 'F')
        cfg->musicPalette = 'f';
      else if (strcmp(s, "level") == 0 || s[0] == 'l' || s[0] == 'L')
        cfg->musicPalette = 'l';
      else if (strcmp(s, "screen") == 0 || s[0] == 's' || s[0] == 'S')
        cfg->musicPalette = 's';
      else
        cfg->musicPalette = 'v';
    } else if (strcmp(key, "musicColor") == 0) {
      char s[8];
      if (!parse_string(p, s, sizeof(s)))
        return false;
      char norm[8];
      if (clamp_music_color(s, norm, (int)sizeof(norm)))
        snprintf(cfg->musicColor, sizeof(cfg->musicColor), "%s", norm);
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
      if (*p != '\0')
        return false;
      clamp_brightness_range(&cfg->brightnessLo, &cfg->brightnessHi);
      clamp_brightness_range(&cfg->regionBrightnessLo,
                             &cfg->regionBrightnessHi);
      return true;
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

std::string config_format_json(const HelperConfig &c) {
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
  snprintf(num, sizeof(num), "  \"saturation\": %.4g,\n", (double)c.saturation);
  o.append(num);
  o.append("  \"brightnessMode\": ");
  append_escaped(&o, c.brightnessMode == 'l' ? "linear" : "full");
  o.append(",\n");
  snprintf(num, sizeof(num), "  \"brightnessLo\": %d,\n", c.brightnessLo);
  o.append(num);
  snprintf(num, sizeof(num), "  \"brightnessHi\": %d,\n", c.brightnessHi);
  o.append(num);
  o.append("  \"saturationAlgo\": ");
  append_escaped(&o, c.saturationAlgo == 'n' ? "neutral" : "luma");
  o.append(",\n");
  o.append("  \"sampleAlgo\": ");
  append_escaped(&o, c.sampleAlgo == 'm' ? "mean" : "rms");
  o.append(",\n");
  o.append("  \"nearBlackLuma\": ");
  append_escaped(&o, c.nearBlackLuma == 'a' ? "mean" : "rec601");
  o.append(",\n");
  o.append("  \"mode\": \"");
  o.push_back(c.mode);
  o.append("\",\n");

  o.append("  \"comPort\": ");
  append_escaped(&o, c.comPort);
  o.append(",\n");
  o.append("  \"captureOutput\": ");
  append_escaped(&o, c.captureOutput);
  o.append(",\n");
  o.append("  \"lastConnectedCom\": ");
  append_escaped(&o, c.lastConnectedCom);
  o.append(",\n");
  o.append("  \"serialConfigured\": ");
  o.append(c.serialConfigured ? "true" : "false");
  o.append(",\n");

  o.append("  \"autoSleepSync\": ");
  o.append(c.autoSleepSync ? "true" : "false");
  o.append(",\n");
  o.append("  \"screenOffSync\": ");
  o.append(c.screenOffSync ? "true" : "false");
  o.append(",\n");
  o.append("  \"turnOffOnShutdown\": ");
  o.append(c.turnOffOnShutdown ? "true" : "false");
  o.append(",\n");
  o.append("  \"startOnBoot\": ");
  o.append(c.startOnBoot ? "true" : "false");
  o.append(",\n");

  o.append("  \"lastScene\": ");
  append_escaped(&o, c.lastScene);
  o.append(",\n");
  o.append("  \"lastCustomSolid\": ");
  append_escaped(&o, c.lastCustomSolid);
  o.append(",\n");
  o.append("  \"wallCompEnabled\": ");
  o.append(c.wallCompEnabled ? "true" : "false");
  o.append(",\n");
  o.append("  \"letterboxDetect\": ");
  o.append(c.letterboxDetect ? "true" : "false");
  o.append(",\n");
  o.append("  \"subtitleDetect\": ");
  o.append(c.subtitleDetect ? "true" : "false");
  o.append(",\n");
  snprintf(num, sizeof(num), "  \"mapDefaultsRev\": %d,\n", c.mapDefaultsRev);
  o.append(num);
  o.append("  \"wallColor\": ");
  append_escaped(&o, c.wallColor);
  o.append(",\n");

  o.append("  \"regionAlgo\": ");
  append_escaped(&o, c.regionAlgo == 'x' ? "max" : "mean");
  o.append(",\n");
  snprintf(num, sizeof(num), "  \"regionBlur\": %d,\n", c.regionBlur);
  o.append(num);
  snprintf(num, sizeof(num), "  \"regionSmooth\": %.4g,\n",
           (double)c.regionSmooth);
  o.append(num);
  snprintf(num, sizeof(num), "  \"regionDark\": %d,\n", c.regionDark);
  o.append(num);
  snprintf(num, sizeof(num),
           "  \"regionBBox\": {\"l\": %d, \"t\": %d, \"w\": %d, \"h\": %d},\n",
           c.regionBBox.l, c.regionBBox.t, c.regionBBox.w, c.regionBBox.h);
  o.append(num);
  o.append("  \"regionBrightnessMode\": ");
  append_escaped(&o, c.regionBrightnessMode == 'l' ? "linear" : "full");
  o.append(",\n");
  snprintf(num, sizeof(num), "  \"regionBrightnessLo\": %d,\n",
           c.regionBrightnessLo);
  o.append(num);
  snprintf(num, sizeof(num), "  \"regionBrightnessHi\": %d,\n",
           c.regionBrightnessHi);
  o.append(num);

  o.append("  \"musicSource\": ");
  append_escaped(&o, c.musicSource == 'i'   ? "mic"
                     : c.musicSource == 'b' ? "both"
                                            : "system");
  o.append(",\n");
  o.append("  \"musicLayout\": ");
  append_escaped(&o, c.musicLayout == 'm' ? "mirror" : "linear");
  o.append(",\n");
  o.append("  \"musicReverse\": ");
  o.append(c.musicReverse ? "true" : "false");
  o.append(",\n");
  snprintf(num, sizeof(num), "  \"musicSensitivity\": %d,\n",
           c.musicSensitivity);
  o.append(num);
  snprintf(num, sizeof(num), "  \"musicDecay\": %d,\n", c.musicDecay);
  o.append(num);
  o.append("  \"musicSilence\": ");
  append_escaped(&o, c.musicSilence == 'm' ? "min" : "off");
  o.append(",\n");
  {
    const bool none = c.musicMirror[0] < 0 && c.musicMirror[1] < 0 &&
                      c.musicMirror[2] < 0 && c.musicMirror[3] < 0;
    if (none) {
      o.append("  \"musicMirror\": null,\n");
    } else {
      snprintf(num, sizeof(num),
               "  \"musicMirror\": [%d, %d, %d, %d],\n", c.musicMirror[0],
               c.musicMirror[1], c.musicMirror[2], c.musicMirror[3]);
      o.append(num);
    }
  }
  o.append("  \"musicRest\": ");
  append_escaped(&o, c.musicRest == 'p'   ? "peak"
                     : c.musicRest == 'b' ? "base"
                                          : "off");
  o.append(",\n");
  o.append("  \"musicPalette\": ");
  append_escaped(&o, c.musicPalette == 'r'   ? "rainbow"
                     : c.musicPalette == 'f' ? "fixed"
                     : c.musicPalette == 'l' ? "level"
                     : c.musicPalette == 's' ? "screen"
                                             : "vu");
  o.append(",\n");
  o.append("  \"musicColor\": ");
  append_escaped(&o, c.musicColor);

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
