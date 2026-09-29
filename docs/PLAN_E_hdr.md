# 阶段 E — HDR 显示适配（计划）

> **权威进度勾选在** `.cursorrules` 第 6 节「阶段 E」（**已收**；当前主线见阶段 F）。  
> 本文件是详细背景与落地说明；冲突时以 `.cursorrules` 为准。  
> 日期：2026-09-28  
> 阶段 D（死区）暂停，待阶段 F 完成后回来验收。

---

## 1. 问题定义

Windows 开 HDR 时，`IDXGIOutput1::DuplicateOutput` 会把桌面**强制降成** `B8G8R8A8_UNORM`：高光截断、饱和度被压，灯带跟色发灰。

正确路径：`IDXGIOutput5::DuplicateOutput1`，优先要 `R16G16B16A16_FLOAT`（scRGB 线性），再在软件侧按系统 SDR 白点归一化 → 高光软压缩 → sRGB 8 位，下游 map / region / near_black / 死区 **刻度不变**。

```text
HDR 桌面 FP16 scRGB
  → 白点归一（1.0 = SDR 白）
  → Reinhard 软压缩 [knee, peak] → [knee, 1]
  → 线性 → sRGB8
  → 现有采样 / 黑边 / EMA / seg_gate（不改）
```

---

## 2. 与现有红线的边界

| 项 | 关系 | 纪律 |
|----|------|------|
| BRT=`63` / 死区 `T` / `near_black` | **正交** | 转换输出仍 0..255 sRGB；门限与 D 口径不改 |
| 帧长 &lt; 120 / Sleep≥50ms | **不碰** | 只改 capture 层 |
| SDR 路径 | **零开销** | BGRA 仍直读；不走 LUT |
| 色域外负值 | **钳 0** | 暂不做 Rec.2020→709 映射 |
| 混合显卡选屏 | **本阶段不做** | E0 日志可判断；仍 Enum 默认 adapter |

---

## 3. 转换口径

1. `g_half_to_lin[65536]`：half → 线性 scRGB，负 / NaN → 0；再乘 `80 / sdr_white_nits`，使 1.0 = 桌面 SDR 白。
2. 软压缩：三通道取 `m = max(r,g,b)`；`m > knee` 时统一乘 `s = rolloff(m)/m`（保色相）。  
   - `[0,knee]` 原样；`(knee,1]` smoothstep 且 **强制 f(1)=1**（SDR 白→255）；`(1,peak]` → 1（灯带无头上空间）。  
   - `peak = MaxLuminance / sdr_white_nits`（≥1）。`knee` 内部常量 **0.75**，不开放配置。
3. `g_lin_to_srgb8[4097]`：线性 → sRGB 8 位。
4. `hdr_convert_set_params(white_nits, peak_nits)`：参数变了才重建 LUT。

---

## 4. 步骤勾选

权威勾选见 `.cursorrules`；此处为落地说明。

| 步 | 内容 | 验收 |
|----|------|------|
| E0 | `dxgi_init` 打 ColorSpace / MaxLuminance / SDR 白点 / Format | HDR 开→`G2084_P2020` + 旧接口 Format=87 |
| E1 | `hdr_convert` + `hdr_convert_test` | SDR 白→255；18% 灰≈118 — **离线 ALL PASS** |
| E2 | `BgraReader` / `Fp16Reader` 模板化 map/region/letterbox | SDR 行为与改前一致 |
| E3 | `DuplicateOutput1` + DPI V2 + 白点 2s 刷新 | Format=10；纯色接近 SDR；滑块 2s 内跟上 |
| E4 | 调 `knee` / 采样耗时 | blur=8 热路径 &lt;≈5ms 或降抽点 — **默认 0.75 + 耗时日志已进** |
| E5 | `status hdr` + UI 标签 | **不做** |

---

## 5. 实测记录

### E0（诊断）

| 条件 | ColorSpace | BitsPerColor | MaxLuminance | SDR 白点 (nits) | 复制 Format |
|------|------------|--------------|--------------|-----------------|-------------|
| HDR 关 | （待填） | | | | |
| HDR 开 + 旧 Dup | （待填） | | | | 期望 87 |
| HDR 开 + Dup1 | （待填） | | | | 期望 10 |

### E4（knee / 耗时）

| knee | 观感（高光） | blur=8 采样 ms | 备注 |
|------|--------------|----------------|------|
| 0.60 | （待填） | | |
| **0.75**（默认） | （待填） | | helper.log `sample X.XXms` 每 5s |
| 0.90 | （待填） | | |

> 口径已落地（`kHdrKnee=0.75`；FP16 抽点 dens=12/20）；热路径限流打耗时。上表待实机补记。若 blur=8 持续 &gt;5ms，再降抽点。

---

## 6. 风险

- 核显+独显：HDR 输出可能不在默认 adapter → 本阶段不扩选卡。
- `DuplicateOutput1` 可能要求 Per-Monitor V2 DPI → E3 启动时设置。
- 切换 HDR 触发 ACCESS_LOST → 靠既有 C3 自愈重建并重读色彩空间。
