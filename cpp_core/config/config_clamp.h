#pragma once

// 与 engine / Dart 对齐的夹紧；config_json 与 config_store 共用。
inline float clamp_alpha(float v) {
  if (v < 0.05f)
    return 0.05f;
  if (v > 1.f)
    return 1.f;
  return v;
}
inline int clamp_near_black(int v) {
  if (v < 0)
    return 0;
  if (v > 64)
    return 64;
  return v;
}
inline int clamp_blur(int v) {
  if (v < 0)
    return 0;
  if (v > 8)
    return 8;
  return v;
}
// 屏幕跟色饱和度增益；1.0=原色，>1 更艳（固定减去中性色）
inline float clamp_saturation(float v) {
  if (v < 0.5f)
    return 0.5f;
  if (v > 2.f)
    return 2.f;
  return v;
}
// map 饱和度算法：固定 'n'=减去中性色；'l'=保持亮度仅旧兼容，一律钳回 'n'
inline char clamp_saturation_algo(char c) {
  (void)c;
  return 'n';
}
inline int clamp_region_blur(int v) {
  if (v < 0)
    return 0;
  if (v > 20)
    return 20;
  return v;
}
inline float clamp_region_smooth(float v) {
  if (v < 0.f)
    return 0.f;
  if (v > 0.99f)
    return 0.99f;
  return v;
}
inline int clamp_region_dark(int v) {
  if (v < 0)
    return 0;
  if (v > 50)
    return 50;
  return v;
}
inline int clamp_pct(int v) {
  if (v < 0)
    return 0;
  if (v > 100)
    return 100;
  return v;
}
inline int clamp_music_pct(int v) { return clamp_pct(v); }
inline char clamp_music_source(char c) {
  if (c == 'i' || c == 'I')
    return 'i';
  if (c == 'b' || c == 'B')
    return 'b';
  return 's';
}
inline char clamp_music_layout(char c) {
  return (c == 'm' || c == 'M') ? 'm' : 'l';
}
inline char clamp_music_silence(char c) {
  return (c == 'm' || c == 'M') ? 'm' : 'o';
}
inline char clamp_music_rest(char c) {
  if (c == 'p' || c == 'P')
    return 'p';
  if (c == 'b' || c == 'B')
    return 'b';
  return 'o';
}
inline char clamp_music_palette(char c) {
  if (c == 'r' || c == 'R')
    return 'r';
  if (c == 'f' || c == 'F')
    return 'f';
  if (c == 'l' || c == 'L')
    return 'l';
  if (c == 's' || c == 'S')
    return 's';
  return 'v';
}
// 6 位 hex → 小写写入 out[7]；非法 / 000000 返回 false
inline bool clamp_music_color(const char *in, char *out, int cap) {
  if (!out || cap < 7 || !in || in[6] != '\0')
    return false;
  char norm[7];
  for (int i = 0; i < 6; ++i) {
    char c = in[i];
    bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F');
    if (!ok)
      return false;
    if (c >= 'A' && c <= 'F')
      c = (char)(c - 'A' + 'a');
    norm[i] = c;
  }
  norm[6] = '\0';
  if (norm[0] == '0' && norm[1] == '0' && norm[2] == '0' && norm[3] == '0' &&
      norm[4] == '0' && norm[5] == '0')
    return false;
  for (int i = 0; i < 7; ++i)
    out[i] = norm[i];
  return true;
}
// 校验镜像端点：四值均在 0..9 且两条不相交；全 -1 视为「未设」合法清空。
inline bool valid_music_mirror(const int ends[4]) {
  if (!ends)
    return false;
  if (ends[0] < 0 && ends[1] < 0 && ends[2] < 0 && ends[3] < 0)
    return true;
  // 延迟到 music_layout_mirror；此处只做粗范围，真正相交由调用方 layout 校验
  for (int i = 0; i < 4; ++i) {
    if (ends[i] < 0 || ends[i] > 9)
      return false;
  }
  return true;
}
inline bool valid_region_bbox(int l, int t, int w, int h) {
  l = clamp_pct(l);
  t = clamp_pct(t);
  w = clamp_pct(w);
  h = clamp_pct(h);
  return w > 0 && h > 0 && l + w <= 100 && t + h <= 100;
}
inline bool valid_rect(float x0, float y0, float x1, float y1) {
  return x0 >= 0.f && y0 >= 0.f && x1 <= 1.f && y1 <= 1.f && x0 < x1 && y0 < y1;
}
// 长度截断；空串归一为 auto。名字合不合法交给 select_capture_output 回退。
inline void clamp_capture_output(const char *in, char *out, int cap) {
  if (!out || cap <= 0)
    return;
  if (!in || in[0] == '\0') {
    if (cap >= 5) {
      out[0] = 'a';
      out[1] = 'u';
      out[2] = 't';
      out[3] = 'o';
      out[4] = '\0';
    } else {
      out[0] = '\0';
    }
    return;
  }
  int i = 0;
  for (; in[i] && i + 1 < cap; ++i)
    out[i] = in[i];
  out[i] = '\0';
}
