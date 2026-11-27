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

// 为什么：硬件忽略亮度、只显示色相（等效 max→255）；暗尾浮点色相
// 若不先归一化，取整后只剩 max=1~5 的粗档，会跳成极光色。
static void normalize_hue255(float *r, float *g, float *b) {
  const float mx = chan_max(*r, *g, *b);
  if (mx <= 0.f) {
    *r = *g = *b = 0.f;
    return;
  }
  const float scale = 255.f / mx;
  *r *= scale;
  *g *= scale;
  *b *= scale;
}

// 统一灭灯收尾：清理低亮锁色与兜底缓存，避免跨场景残色泄漏到下一轮暗场
static void turn_gate_off(SegGate *s, int dwell_n) {
  s->on = false;
  s->cnt = 0;
  s->sub_gate_run = 0;
  s->lit_run = 0;
  s->zero_run = 0;
  s->lvl = (std::min)(s->lvl, kGateOff);
  s->hue_locked = false;
  s->locked_ok = false;
  s->locked[0] = s->locked[1] = s->locked[2] = 0.f;
  s->last_nz[0] = s->last_nz[1] = s->last_nz[2] = 0.f;
  s->flipped = true;
  if (dwell_n > 0)
    s->dwell = dwell_n;
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
  // 为什么：慢衰减接近 0 时若 hold 停在 0.51，0.49 差值窗会阻止 disp_zero 成立，
  // 所以 disp 已落入 <0.25 近零区时必须放行归零。
  {
    const float dr = std::fabs(disp_r - s->hold[0]);
    const float dg = std::fabs(disp_g - s->hold[1]);
    const float db = std::fabs(disp_b - s->hold[2]);
    const float dmax = (std::max)(dr, (std::max)(dg, db));
    const bool disp_near_zero = chan_max(disp_r, disp_g, disp_b) < 0.25f &&
                                chan_max(s->hold[0], s->hold[1], s->hold[2]) > 0.f;
    if (dmax > kAntiFlickerEps || disp_near_zero) {
      s->hold[0] = disp_r;
      s->hold[1] = disp_g;
      s->hold[2] = disp_b;
    }
  }

  // —— 最短驻留（独立块；dwell_cfg==0 时完全旁路）——
  // 为什么：先判 blocked 再在帧末递减，保证翻转后满 dwell_cfg 帧不可再翻
  const int dwell_n = s->dwell_cfg;
  const bool dwell_blocked = (dwell_n > 0) && (s->dwell > 0);

  s->bright_run = (L_raw >= kFastOnLevel) ? s->bright_run + 1 : 0;
  s->relight_run = (L_raw >= kFastRelightLevel) ? s->relight_run + 1 : 0;

  // —— 快速亮灯：持续强信号不等判定爬升 + 确认 ——
  // 平时灭灯（!dwell_blocked）用 kFastOnLevel(16) 保 50ms 极速点亮；
  // 刚灭灯驻留期内（dwell_blocked）须达 kFastRelightLevel(40) 才破锁重亮。
  const int fast_on_run = dwell_blocked ? s->relight_run : s->bright_run;
  if (!s->on && fast_on_run >= kFastOnFrames) {
    s->on = true;
    s->cnt = 0;
    s->sub_gate_run = 0;
    s->flipped = true;
    // 为什么：让判定电平跟上，避免刚开灯就被常规灭灯路径判低
    s->lvl = (std::max)(s->lvl, kGateCap);
    if (dwell_n > 0)
      s->dwell = dwell_n;
  }

  // —— 宽迟滞 + 双向确认 + 夹层超时灭灯 ——
  if (s->flipped) {
    // 本帧已由快速亮灯翻转
  } else if (!s->on) {
    s->sub_gate_run = 0;
    if (!dwell_blocked && s->lvl >= kGateOn) {
      ++s->cnt;
      if (s->cnt >= kGateOnFrames) {
        s->on = true;
        s->cnt = 0;
        s->sub_gate_run = 0;
        s->flipped = true;
        if (dwell_n > 0)
          s->dwell = dwell_n;
      }
    } else {
      s->cnt = 0;
    }
  } else {
    s->sub_gate_run = (L_raw < kGateOn) ? (s->sub_gate_run + 1) : 0;
    if (!dwell_blocked) {
      if (s->lvl <= kGateOff) {
        ++s->cnt;
        if (s->cnt >= kGateOffFrames) {
          turn_gate_off(s, dwell_n);
        }
      } else {
        s->cnt = 0;
      }
      if (s->on && s->sub_gate_run >= kSubGateOffFrames) {
        turn_gate_off(s, dwell_n);
      }
    } else {
      s->cnt = 0;
    }
  }

  // —— 快速灭灯：持续亮过的段切黑 / 连续全黑兜底，不走判定慢衰减 ——
  // 为什么：last_nz 兜底只为暗区噪声；亮段硬切黑若也兜底，会在最低亮度拖约 450ms
  {
    const bool disp_zero = (unsigned)(s->hold[0] + 0.5f) == 0 &&
                           (unsigned)(s->hold[1] + 0.5f) == 0 &&
                           (unsigned)(s->hold[2] + 0.5f) == 0;
    // ON 期间单帧掉 0 已被 last_nz 吸收，不抹掉先前累积的 lit_run；
    // 若即使 lit_run < kFastOffLitFrames 仍连续 kDimOffZeroFrames 帧为 0，也直接关灯。
    if (!disp_zero) {
      const int reset_zeros = s->on ? 2 : 1;
      s->lit_run = (s->zero_run >= reset_zeros) ? 1 : s->lit_run + 1;
      s->zero_run = 0;
    } else {
      ++s->zero_run;
      const bool should_fast_off =
          (s->lit_run >= kFastOffLitFrames &&
           s->zero_run >= kFastOffZeroFrames) ||
          (s->zero_run >= kDimOffZeroFrames);
      if (!s->flipped && s->on && should_fast_off) {
        turn_gate_off(s, dwell_n);
      }
    }
  }

  if (dwell_n > 0 && s->dwell > 0)
    --s->dwell;

  // —— 组出 ——
  if (!s->on) {
    s->hue_locked = false;
    s->locked_ok = false;
    s->locked[0] = s->locked[1] = s->locked[2] = 0.f;
    s->last_nz[0] = s->last_nz[1] = s->last_nz[2] = 0.f;
    out[0] = out[1] = out[2] = 0.f;
    return false;
  }

  // —— 低亮色相锁迟滞（仅 ON 时更新；归一化前的 hold L）——
  const float L_disp = chan_max(s->hold[0], s->hold[1], s->hold[2]);
  if (!s->hue_locked) {
    if (L_disp <= kHueLockOff)
      s->hue_locked = true;
  } else {
    if (L_disp >= kHueLockOn)
      s->hue_locked = false;
  }
  if ((!s->hue_locked || !s->locked_ok) && L_disp > 0.f) {
    s->locked[0] = s->hold[0];
    s->locked[1] = s->hold[1];
    s->locked[2] = s->hold[2];
    normalize_hue255(&s->locked[0], &s->locked[1], &s->locked[2]);
    s->locked_ok = true;
  }

  float or_ = s->hold[0];
  float og = s->hold[1];
  float ob = s->hold[2];

  // freeze：低亮区输出最后可靠色相，直到暗门灭（跳过死区粗档跳色）
  if (s->hue_locked && s->locked_ok) {
    or_ = s->locked[0];
    og = s->locked[1];
    ob = s->locked[2];
  }

  // 取整后是否非零：用 +0.5 口径与组帧一致
  const unsigned ur = (unsigned)(or_ + 0.5f);
  const unsigned ug = (unsigned)(og + 0.5f);
  const unsigned ub = (unsigned)(ob + 0.5f);
  if (ur == 0 && ug == 0 && ub == 0) {
    // ON 期间显示色掉到 0：用 last_nz 色相兜底（已 max→255，不再抬到 1）
    or_ = s->last_nz[0];
    og = s->last_nz[1];
    ob = s->last_nz[2];
    if (chan_max(or_, og, ob) <= 0.f) {
      or_ = 255.f;
      og = ob = 0.f;
    }
  } else {
    // A：输出前归一化保色相（与 wall_comp 同口径）
    normalize_hue255(&or_, &og, &ob);
    s->last_nz[0] = or_;
    s->last_nz[1] = og;
    s->last_nz[2] = ob;
  }

  out[0] = or_;
  out[1] = og;
  out[2] = ob;
  return true;
}
