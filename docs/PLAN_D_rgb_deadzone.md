# 阶段 D — RGB 灰度死区适配（计划）

> **权威进度勾选在** `.cursorrules` 第 6 节「阶段 D」（**当前唯一主线**）。  
> 本文件是详细背景与落地说明；冲突时以 `.cursorrules` 为准。  
> 分析来源：`reference/serial_color_analysis_report.md`（对标 HyperHDR，轻量落地）。  
> 日期：2026-09-22  
> H / F / A / B / M 等旧阶段已归档为完成，不再挂待办。

---

## 1. 问题定义（硬件事实）

米家追光灯带控制器对 **每通道 RGB 灰阶** 有截断：低于某值 `T` 时 **直接灭灯**（不是「很暗」）。

```text
软件 RGB：  0 ──────── T ──────── 255
硬件表现：  灭 ─死区─ 灭 ┃ 可见区（过 T 后才跟）
```

| 现象 | 原因 |
|------|------|
| 暗部闪烁 | 对称 EMA 在 `T` 附近抖 → 每帧亮灭 |
| 暗→亮突变 | 死区内爬坡被硬件吞掉，过 `T` 才突然可见 |
| 亮→暗拖尾 | 一阶 EMA 长尾 + 人眼暗部敏感 |

**算法目标**：承认死区不可见 —— **跳过死区做过渡；回死区干净灭灯**。  
不是「把暗部抹得更平滑」，也不是「永远留一点底光」。

---

## 2. 与现有红线 / 概念的边界

| 项 | 关系 | 纪律 |
|----|------|------|
| Brightness 写死 `63` | **正交** | 死区只在 RGB 通道处理；**禁止**用 BRT 做暗部渐变（方案 A/B 已废弃） |
| `near_black`（DXGI 采样） | **不同层** | 采样丢近黑点；不是硬件导通阈值。勿把 `T` 和 `near_black` 混成一个旋钮 |
| 帧长 &lt; 120 / Sleep≥50ms | **不碰** | 只改 `produce_colors_*` 后处理；迟滞帧数按 50ms≈20fps 折算 |
| HyperHDR `backlightThreshold` 常亮底光 | **默认不做** | 与 `soft_off` / 真黑冲突；若以后要做必须可关且默认关 |
| Hybrid 弹簧 / float YUV / 色温功率全套 | **不搬** | 仍 uint8 组帧；只借鉴「跃阶 + 非对称 + 迟滞」思路 |

诊断「α 无效 / 硬切亮灭」顺序：

1. 先确认 BRT 仍写死 `63`（已知取舍，不是回归 bug）  
2. 再查 RGB 是否仍在死区里做对称 EMA（本阶段要修的）  
3. 最后才查采样 / 超时 / 线程

---

## 3. 目标管线（落点）

仅改 helper 热路径后处理（map + region 两边都要）：

```text
采样 rgb[10][3]
  → 用户 EMA（map α / region smooth；持续跑，不清零不 seed）
  → 饱和度（仅 map）
  → 墙补（采样路与显示路各一份，同口径）
  → D1 暗门 seg_gate（判定信号 ⊥ 用户 α）
       · 独立 gate_lvl EMA（kGateAlpha=0.25，封顶 kGateCap=8）
       · 宽迟滞 kGateOn=4 / kGateOff=1.5 + 双向确认帧
       · 最短驻留 kMinDwellFrames=8（已实现；以后可能会改）
       · 0.49 保持（HyperHDR LedDevice；亮部 LSB）
  →（D2）非对称 EMA ·（D3）可选伽马
  → 组帧 set_rgb_pc … 63 …（BRT 仍写死）
```

每段 `SegGate`：判定电平 + hold + last_nz + ON/OFF + 确认计数 + 驻留倒计时（与确认计数分离）。

```text
L_raw = max(R,G,B)（墙补后采样；与用户 α 正交）
gate_lvl ← EMA(min(L_raw, kGateCap))

OFF → ON：gate_lvl ≥ kGateOn 连续 kGateOnFrames，且驻留已满
ON  → OFF：gate_lvl ≤ kGateOff 连续 kGateOffFrames，且驻留已满 → 输出 000000
ON  时：显示色走用户 EMA+0.49；若取整为 0 则 last_nz 抬到 max=1（硬件等亮平台）
```

---

## 4. 分步清单（与 `.cursorrules` 第 6 节勾选一一对应）

### D0 — 实测 `hard_threshold`（阻塞后续）

用 `send_solid` 扫灰度（Brightness 仍 `63`）：

```text
040404 → 080808 → 0c0c0c → 101010 → 181818 → 202020 → 282828 …
```

记下：**刚好稳定可见** 的最小灰阶 → `T`。  
据此定 `T_on` / `T_off`（建议 `T_off < T_on`，迟滞宽度至少 1～2 个可见台阶）。

*验收*：表格写入本文件「实测记录」节；代码里常量有出处注释。

### D1 — 输出端防闪烁（独立判定 + 宽迟滞 + 双向确认 + 最短驻留）

- `engine/seg_gate.h|.cpp`：纯函数 `seg_gate_step`（helper 与离线测试共用）
- `engine_frame.cpp`：map/region 在墙补后接入；启停 `reset_seg_gates`
- 无 IPC / JSON / UI（常量写死；`dwell_cfg` 仅测试可改）
- 离线：`experiments/seg_gate_test`（CMake 目标 `seg_gate_test`）

*验收*：`seg_gate_test` PASS；暗场不再 0↔最低亮闪；真黑能灭；诊断 `raw_0nz_edges ≫ gate_flips`。

### D2 — 非对称时间平滑

- map：由单一 `g_alpha` 派生或并存 `α_up` / `α_down`（IPC 先可只暴露一个「响应」旋钮，内部拆；避免一上来堆 UI）  
- region：`smooth` 保持「高=更钝」极性，内部映射成非对称等价物  
- 常量先写死可测值（报告量级：`α_up≈0.15`，`α_down≈0.35`），再决定是否进 JSON

*验收*：亮起不过冲闪；变暗明显比对称 EMA 干脆，且不在死区拖尾假爬坡。

### D3 — 伽马（可选）

- 输出前 `powf(x/255, γ)*255`（γ 默认约 2.2）  
- 与迟滞/跃阶叠加后目视对比；无效或损色则回退，不硬留

*验收*：暗部落地更跟手且不引入偏色；否则标记废弃并删代码。

### 明确不做（本阶段）

- 改 Brightness / 复活方案 A/B  
- 默认常亮底光  
- 把 `T` 与 `near_black` 合并成一个 UI 滑条  
- 引入 HyperHDR 整套 ICE / 弹簧阻尼 / 浮点色域管线  
- 为暗部算法加长串口帧或压低 50ms

---

## 5. 修改文件预期

| 文件 | 内容 |
|------|------|
| `cpp_core/engine/seg_gate.h|.cpp` | `SegGate`、常量、`seg_gate_step` / `reset` |
| `cpp_core/engine/engine_internal.h` | `g_seg_gate[10]` |
| `cpp_core/engine/engine_frame.cpp` | map/region 接入 + 5s 诊断 |
| `cpp_core/engine/engine_params.cpp` | `g_seg_gate` 定义 |
| `experiments/seg_gate_test/` | 合成序列回放断言 |
| `cpp_core/CMakeLists.txt` | helper 编入 seg_gate；目标 `seg_gate_test` |

编译验收：`cmake --build cpp_core/build --config Release`；跑 `seg_gate_test.exe`。

---

## 6. 实测记录（D0 填写）

> **测法**（2026-09-22）：SSCOM 直连，230400 8N1；握手同 helper（`set_power 1` → `set_pc_available 1` → `set_usb_dim_time 45` → `set_pc_linkage 1`）；帧格式 **5 段 × Step=4**（厂商抓包短帧；单段 Step=20 会 `err seg n 32`）；BRT 固定 **`63`**；只扫 **蓝通道** `0000BB`（非等灰 `BBBBBB`）。

| 灰阶 hex（蓝） | 观感（灭 / 闪 / 稳亮） | 备注 |
|----------------|------------------------|------|
| `000000` | 灭 | 基线真黑 |
| `000001` | 稳亮 | **最小可见** |
| `000002` … `000020` | 稳亮 | 目视与 `000001` 同色（BRT=`63` 下暗部台阶观感扁平，属已知取舍） |

- 判定 `T` = **1**（`0x01`，蓝通道）
- `T_on` = **1** `T_off` = **0** 确认帧数 N = **2**（×50ms；T 已贴底，迟滞只能落在 0/1）— **旧 D1 取值；已废弃**
- **口径备注**：死区宽度仅 1 级；D1 跃阶几乎「非 0 即可见」。若后续等灰 `010101` / 红绿单通道与蓝不一致，以补测改写本表，勿猜大阈值。
- **芯片等亮平台（2026-09-24）**：低亮度输入会被控制器统一成同一最低亮度（规避低亮偏色）；`000001`…`000020` 目视同色属硬件行为，不是软件漏测。暗门开/灭阈值可放在此平台内，肉眼无代价。
- **`near_black` 悬崖**：整段像素均低于 `near_black` → 采样输出 `0`；任一像素幸存 → 输出 ≥ `near_black`（默认 4）。暗场原始值常为 0↔≥4 交替，无中间过渡。

---

## 6.1 D1 记录（2026-09-24 重做）

### 旧实现为何失败（已删于 `9249e94`）

1. 亮起无确认帧：1 帧 `L≥1` 即 ON，并 seed EMA（跳过平滑）
2. 判定用原始采样；暗场是 `near_black` 悬崖（0↔≥4）
3. 迟滞窗口只有 `T_on=1` / `T_off=0` 一级
4. `clamp_half_deadzone` 把衰减尾巴抬成 1 → 灯卡最低亮
5. 与 0.49 无关：旧代码无防闪烁保持；`emaAlpha` 默认 1，对 EMA 后做迟滞等于对原始做

### 新设计（`seg_gate`）

| 常量 | 值 | 作用 |
|------|-----|------|
| `kGateAlpha` | 0.25 | 独立判定 EMA（⊥ 用户 α） |
| `kGateCap` | 8 | 判定封顶；硬切全黑约 6+3 帧灭 |
| `kGateOn` / `kGateOff` | 4 / 1.5 | 宽迟滞（等亮平台内） |
| `kGateOnFrames` / `kGateOffFrames` | 2 / 3 | 双向确认 |
| `kMinDwellFrames` | 8（400ms） | 最短驻留；**已实现，以后可能会改** |
| `kAntiFlickerEps` | 0.49 | HyperHDR LedDevice 亮部 LSB 保持 |

### 最短驻留（以后可能会改）

**已实现默认开启** `kMinDwellFrames=8`。副作用：

- 刚灭后 400ms 内真亮起 → 最多晚亮 400ms（最显眼）
- 刚开后 400ms 内真切黑 → 最低亮最多多停 400ms + 确认帧
- 400ms 由「每秒 ≤2.5 次翻转」反推，无实测依据

优化方向（D1 不做，实测后再定）：

- 强信号绕过（`L_raw≥32` 忽略驻留开灯）— 首选
- 两侧驻留不同（灭后短 / 开后长）
- 缩短或 `dwell_cfg=0` 关闭

实现约束：驻留用独立 `dwell` / `dwell_cfg`，与确认 `cnt` 分离；`0` 完全旁路。

### 离线对照（`seg_gate_test`，2026-09-24）

| 序列 | dwell=8 | dwell=0 |
|------|---------|---------|
| 0/5 交替 200f | flips=0 | flips=0 |
| 0..6 噪声 200f | flips≤2 | flips≤2 |
| 0/255 交替 200f | flips≤25 | 受前两层约束 |
| 线性淡出 40→0 | 1×OFF，≤10f | — |
| 硬切 200→0 | 1×OFF，≤10f | — |
| 阶跃 0→50 | 1×ON，≤3f | — |
| 100.4↔100.6 | 取整字节不变 | — |
| 灭后 +2f 阶跃 50 | first_on=5（基线） | — |

实机：看 helper 日志 `seg_gate diag 5s: raw_0nz_edges=… gate_flips=…`；暗场应 raw≫flips。

---

## 7. 参考

- `reference/serial_color_analysis_report.md` — 现象与 HyperHDR 对标  
- `reference/项目注意事项与踩坑.md` §4 — BRT=`63` 诊断纪律  
- `.cursorrules` §2 红线、§6 阶段 D、§7 产品债
