#include "seg_gate.h"

#include <algorithm>
#include <cmath>

void seg_gate_reset(SegGate *s) {
  if (s == nullptr)
    return;
  *s = SegGate{};
}

static float chan_max(float r, float g, float b) {
  return (std::max)(r, (std::max)(g, b));
}

static void scale_to_min1(float *r, float *g, float *b) {
  const float mx = chan_max(*r, *g, *b);
  if (mx <= 0.f) {
    *r = *g = *b = 0.f;
    return;
  }
  // 为什么：硬件 1..0x20 等亮；抬到 max=1 不算死区内假渐变
  const float scale = 1.f / mx;
  *r *= scale;
  *g *= scale;
  *b *= scale;
}

bool seg_gate_step(SegGate *s, float gate_r, float gate_g, float gate_b,
                   float disp_r, float disp_g, float disp_b, float out[3]) {
  if (s == nullptr || out == nullptr)
    return false;

  s->flipped = false;

  // —— 独立判定信号（与用户 α 正交；封顶只关心暗区）——
  const float L_raw = chan_max(gate_r, gate_g, gate_b);
  const float L_cap = (std::min)(L_raw, kGateCap);
  if (!s->inited) {
    s->lvl = L_cap;
    s->hold[0] = disp_r;
    s->hold[1] = disp_g;
    s->hold[2] = disp_b;
    s->inited = true;
  } else {
    s->lvl = s->lvl + kGateAlpha * (L_cap - s->lvl);
  }

  // —— 0.49 保持（HyperHDR LedDevice；亮部 LSB 抖动）——
  {
    const float dr = std::fabs(disp_r - s->hold[0]);
    const float dg = std::fabs(disp_g - s->hold[1]);
    const float db = std::fabs(disp_b - s->hold[2]);
    const float dmax = (std::max)(dr, (std::max)(dg, db));
    if (dmax > kAntiFlickerEps) {
      s->hold[0] = disp_r;
      s->hold[1] = disp_g;
      s->hold[2] = disp_b;
    }
  }

  // —— 最短驻留（独立块；dwell_cfg==0 时完全旁路）——
  // 为什么：先判 blocked 再在帧末递减，保证翻转后满 dwell_cfg 帧不可再翻
  const int dwell_n = s->dwell_cfg;
  const bool dwell_blocked = (dwell_n > 0) && (s->dwell > 0);

  // —— 宽迟滞 + 双向确认 ——
  if (!s->on) {
    if (!dwell_blocked && s->lvl >= kGateOn) {
      ++s->cnt;
      if (s->cnt >= kGateOnFrames) {
        s->on = true;
        s->cnt = 0;
        s->flipped = true;
        if (dwell_n > 0)
          s->dwell = dwell_n;
      }
    } else {
      s->cnt = 0;
    }
  } else {
    if (!dwell_blocked && s->lvl <= kGateOff) {
      ++s->cnt;
      if (s->cnt >= kGateOffFrames) {
        s->on = false;
        s->cnt = 0;
        s->flipped = true;
        if (dwell_n > 0)
          s->dwell = dwell_n;
      }
    } else {
      s->cnt = 0;
    }
  }

  if (dwell_n > 0 && s->dwell > 0)
    --s->dwell;

  // —— 组出 ——
  if (!s->on) {
    out[0] = out[1] = out[2] = 0.f;
    return false;
  }

  float or_ = s->hold[0];
  float og = s->hold[1];
  float ob = s->hold[2];

  // 取整后是否非零：用 +0.5 口径与组帧一致
  const unsigned ur = (unsigned)(or_ + 0.5f);
  const unsigned ug = (unsigned)(og + 0.5f);
  const unsigned ub = (unsigned)(ob + 0.5f);
  if (ur == 0 && ug == 0 && ub == 0) {
    // ON 期间显示色掉到 0：用 last_nz 抬到 max=1，避免 α=1 时亮灭交替
    or_ = s->last_nz[0];
    og = s->last_nz[1];
    ob = s->last_nz[2];
    if (chan_max(or_, og, ob) <= 0.f) {
      or_ = 1.f;
      og = ob = 0.f;
    } else {
      scale_to_min1(&or_, &og, &ob);
    }
  } else {
    s->last_nz[0] = or_;
    s->last_nz[1] = og;
    s->last_nz[2] = ob;
  }

  out[0] = or_;
  out[1] = og;
  out[2] = ob;
  return true;
}
