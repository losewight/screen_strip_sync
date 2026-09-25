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
// 屏幕跟色饱和度增益；1.0=原色，>1 更艳；Rec.601 亮度守恒
inline float clamp_saturation(float v) {
  if (v < 0.5f)
    return 0.5f;
  if (v > 2.f)
    return 2.f;
  return v;
}
// map 饱和度算法：'l'=保持亮度（默认），'n'=减去中性色；非法回 luma
inline char clamp_saturation_algo(char c) {
  return (c == 'n' || c == 'N') ? 'n' : 'l';
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
