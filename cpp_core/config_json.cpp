#include "config_json.h"

#include "config_clamp.h"

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

bool config_parse_json(const char *json, HelperConfig *cfg) {
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
           "  \"regionBBox\": {\"l\": %d, \"t\": %d, \"w\": %d, \"h\": %d}",
           c.regionBBox.l, c.regionBBox.t, c.regionBBox.w, c.regionBBox.h);
  o.append(num);

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

