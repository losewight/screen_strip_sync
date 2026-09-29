# 阶段 F — Map 忽略字幕（计划）

> **权威进度勾选在** `.cursorrules` 第 6 节「阶段 F」（**当前主线**）。  
> 本文件是详细背景与落地说明；冲突时以 `.cursorrules` 为准。  
> 日期：2026-09-29  
> 与归档「F1–F4」（前端史）无关，勿混淆。

---

## 1. 问题

自定义段映射框若压到画面底部，硬字幕 / 半透明字幕条的亮字会进 mean，灯跟白字闪。  
letterbox 只处理对称黑边，**不能**去掉内容区内的字幕。

口径：自动扫内容底字幕带 → 滑动窗命中达标后把各段 `y1` 上收。仅 **map / sample_rects**；顶边 fallback 与 region 不动。

---

## 2. 与红线边界

| 项 | 关系 |
|----|------|
| letterbox | **串联**：先黑边，字幕相对内容底；hold 共用 |
| near_black / 死区 / BRT=63 | **正交** |
| 帧长 / 50ms | **不碰** |
| segmentMap 存盘坐标 | **不改**（只改运行时采样 y1） |

---

## 3. 算法摘要

1. 内容窗底部 1/5：5 探针 luma；亮点≥2 或同行高对比 → 字幕行。  
2. 连续带 + pad → 本采样 `raw_crop`。  
3. 滑动窗 `kWindow=167`（≈10s @~60ms/采样）；`hits≥56` 开，`hits≤10` 关（全停后 ≈9.4s）。  
4. active 时 crop = 窗内 hit 的 max。

一帧 = 一次 `subtitle_process`（map 成功采样），不是屏刷新。

---

## 4. 步骤勾选

权威勾选见 `.cursorrules`。

| 步 | 内容 | 验收 |
|----|------|------|
| F0 | `subtitle_detect` + `sample_rects` y1 裁切 + hold/reset | 日志 `subtitle crop=` |
| F1 | JSON / IPC / `cfg subtitle_detect` | 开关落盘与推送 |
| F2 | Flutter「智能忽略字幕」+ 单测 | 黑边 Hint 不再提字幕 |
| F3 | 实机 | 见下 |

---

## 5. 实机验收

- [ ] map 框压底 + 硬字幕：开检测 → 灯不跟白字闪；关 → 跟字闪  
- [ ] 无自定义 map（顶边）行为不变  
- [ ] region 氛围不变  
- [ ] 校准 hold 期间 crop=0  
- [ ] 有 letterbox 电影时，字幕仍相对内容底裁切  
