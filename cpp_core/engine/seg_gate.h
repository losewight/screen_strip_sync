#pragma once

// D1 输出端暗门：独立判定信号 + 宽迟滞 + 双向确认 + 最短驻留 + 0.49 保持。
// 纯函数，不依赖 Windows / 全局变量；helper 与 seg_gate_test 共用。
// 最短驻留 kMinDwellFrames 已实现默认开启，以后可能会改（见 PLAN_D §6.1）。

// 判定 EMA：与用户 α / region smooth 正交
constexpr float kGateAlpha = 0.25f;
// 判定信号封顶：只关心暗区；硬切全黑时约 6 帧落到 kGateOff
constexpr float kGateCap = 8.f;
// 开/灭阈值（硬件 1..0x20 等亮平台内，肉眼无代价）
constexpr float kGateOn = 4.f;
constexpr float kGateOff = 1.5f;
// 双向确认帧（×50ms）
constexpr int kGateOnFrames = 2;
constexpr int kGateOffFrames = 3;
// 最短驻留：翻转后至少保持 N 帧才允许再翻；0=旁路。以后可能会改。
constexpr int kMinDwellFrames = 8;
// HyperHDR LedDevice anti-flicker：0-255 刻度 >0.49 才更新 hold
constexpr float kAntiFlickerEps = 0.49f;

struct SegGate {
  float lvl = 0.f;          // 独立判定信号
  float hold[3] = {};       // 0.49 保持后的浮点色（显示路径）
  float last_nz[3] = {};    // 上一次非零输出色（ON 期间兜底）
  bool on = false;
  bool inited = false;
  int cnt = 0;              // 当前方向确认计数（与 dwell 分离）
  int dwell = 0;            // 最短驻留剩余帧；独立块
  // 驻留配置：默认 = kMinDwellFrames；测试可置 0 旁路。以后可能会改常量。
  int dwell_cfg = kMinDwellFrames;
  bool flipped = false;     // 本步是否发生 ON↔OFF（诊断用）
};

void seg_gate_reset(SegGate *s);

// gate_rgb：墙补后的采样（判定 L，与用户 α 正交）
// disp_rgb：用户 EMA(+sat)+墙补后的显示色（0.49 保持 / 组出）
// 写出 out[3]；返回当前是否 ON。
bool seg_gate_step(SegGate *s, float gate_r, float gate_g, float gate_b,
                   float disp_r, float disp_g, float disp_b, float out[3]);

// 测试便捷：gate 与 disp 同色（α=1 口径）
inline bool seg_gate_step_same(SegGate *s, float r, float g, float b,
                               float out[3]) {
  return seg_gate_step(s, r, g, b, r, g, b, out);
}
