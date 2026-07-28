# Zeeray 项目现状

面向：后端基本就绪 → **先做前端** → 再整合 IPC → 再收产品债。

---

## 1. 项目与架构边界

Windows 平台 PC 屏幕同步氛围灯驱动（米家追光灯带 Pro / Zeeray）。

**v2 双进程：**

| 进程 | 职责 |
|------|------|
| Flutter (Dart) | UI、模式切换、JSON 配置、EMA / 调色方案参数 |
| `helper.exe` (C++) | 串口唯一属主、DXGI 抓屏、采样组帧、发帧循环 |

两进程经本机 IPC（`127.0.0.1` 回环 TCP）只传「命令 / 状态」文本；逐帧像素与发帧热路径全部留在 helper，**不再经 dart:ffi**。

Flutter **绝不**直接开串口（防两进程抢 COM）。helper 须随 App 退出而干净退出（关灯 → 停线程 → 关串口 → 进程退出），防僵尸占用 COM。

历史：早期同进程 FFI 方案已废案（窗口可见时与 Flutter 渲染抢资源丢帧）。学习产物见 `cpp_core/废案_同进程FFI_Day11-14/`、`lib - 副本/`（含旧 FFI），**控灯主线是 helper.exe**。

---

## 2. 硬红线（任何实现不得突破）

- **设备**：米家追光灯带 Pro，20 段物理 RGB；纯 ASCII 串口，230400 8N1，帧以 `\r\n` 结尾。
- **帧长**：含 `\r\n` 工程限制 **&lt; 120 字节**（拒绝 `>=120`）；设备硬上限 128，无防溢出，溢出会死机需硬件重启。10 段渲染、Step=2。
- **帧间隔**：`WriteFile` 后节流 **Sleep ≥ 50ms**（实测极限；再短丢帧）。
- **进程边界**：串口属主 = helper；IPC 只传命令/状态，不传像素热数据；通道绑定 `127.0.0.1`、只 accept 单连接，不对外监听。

---

## 3. 已实现（对照当前代码）

### Helper（`cpp_core/`）

- 串口：`CreateFile`、230400 8N1、超时/Purge；`send_one_frame` 互斥 + 帧长校验拒绝 `>=120`。
- 引擎：握手 / 纯色 / 氛围灯后台循环（DXGI 采样 → RGB EMA → 组 ASCII 帧 → 互斥写 + Sleep 50ms）。
- DXGI：Desktop Duplication、stride 采样、10 段边缘、blurStep 水平平均。
- IPC：Winsock 监听 `127.0.0.1:9527`，按行解析命令，可回传 `status …`。
- 生命周期：Ctrl-C / 关控制台 / 休眠 / 注销等路径走 `helper_shutdown`（停引擎、关灯、关串口、关 DXGI、取消 IPC）。

### Flutter（活跃树仅 `lib/main.dart`）

- IPC **烟测台**：`Process.start` 拉起 helper → Socket 连接；按钮：连接 / 红（`solid`）/ 开始 / 停止 / 重连；唤醒后杀 helper 再重连。
- **尚无**产品级 UI、JSON 配置页、方案 A/B 控件。
- `lib - 副本/`：旧导航壳 + FFI 废案，未接入活跃 `lib/`。

---

## 4. 未解决 / 产品债

| 类别 | 内容 |
|------|------|
| 亮度模型 | Brightness **写死 `63`**；仅对 RGB 做 EMA → 软件 α 对灭灯渐变几乎不可见。诊断「α 无效 / 硬切亮灭」时先查 BRT，勿误判为超时/采样 bug。 |
| 双调色 | **方案 A**（简单跟色，默认）与 **方案 B**（luma→Brightness + 亮度 EMA + 可选校正）均未落地；校正须经 Flutter JSON + IPC 下发，禁止写死唯一魔法数。 |
| Helper 缺口 | 无父进程 PID 监测；DXGI `ACCESS_LOST` 未恢复；COM 失败后无自动重连（仅 IPC `reconnect`）；COM 口写死；EMA / 采样 / blur 不可配置；IPC 断连后不重回 listen。 |
| 前端缺口 | 产品 UI、模式切换、JSON、状态面板、helper 相对路径打包（当前开发用绝对路径）。 |
| 工作节奏 | **现阶段只做前端壳与交互**；IPC 正式整合与调参下发放到前端成型后再做；亮度方案 A/B 放在前端+IPC 稳之后。 |

---

## 5. 前端职责速查

**做：** UI 交互、模式切换、JSON 读写、EMA / 方案参数展示与编辑。

**不做：** 网络请求、复杂路由、直接开串口、逐帧像素热路径。

**协作约定：** 写 UI 时简要说明 Widget 树与状态管理（开发者在边做边学 Flutter）。

---

## 6. IPC 命令清单（接口备忘）

前端阶段可先本地 mock 状态；成型后再接到 helper。以下为 **helper 当前已支持** 的文本协议（一行一条，建议 `\n` 结尾）。

| 方向 | 文本 | 含义 |
|------|------|------|
| → helper | `start` | 启动氛围灯引擎线程 |
| → helper | `stop` | 停止引擎 |
| → helper | `solid RRGGBB` | 发一帧纯色（6 位 hex） |
| → helper | `off` | 停引擎并关灯 |
| → helper | `quit` | 停引擎并结束 IPC 循环（helper 退出） |
| → helper | `reconnect` | 关串口并重试就绪 |
| ← helper | `status ready` | 连接后就绪 |
| ← helper | `status reconnecting` | 正在重连串口 |
| ← helper | `status reconnect_ok` | 重连成功 |
| ← helper | `status reconnect_fail` | 重连失败 |

未知命令：helper 打日志并忽略，不崩。超长行丢弃。

配置类命令（EMA α、方案 A/B、校正增益等）**尚未实现**——阶段 B 可先写接口草稿，再改 C++。

---

## 7. 推进清单

**用法：** 从上往下取第一项未勾选的做；一天一事，不必赶多项。不写死日期编号；会了的可跳过。

### 阶段 A — 前端壳（先做，可暂不碰真灯）

- [ ] **A1** App 壳：导航（主控 / 设置），拆出页面文件，告别单文件烟测堆叠。
- [ ] **A2** 主控页布局：开始 / 停止、纯色、关灯、连接状态占位（先本地 `setState`，不强制 helper）。
- [ ] **A3** 设置页骨架：EMA α、方案 A/B 切换入口（绑本地变量即可；先不落盘）。
- [ ] **A4** JSON 配置读写：本地存/读上述参数；启动恢复上次选择。
- [ ] **A5** 状态与反馈：连接中 / 就绪 / 失败 / 引擎运行中的文案与简单视觉反馈。
- [ ] **A6** UI 打磨一小步：间距、禁用态、基础动效（可选，克制）。

### 阶段 B — 接 IPC（前端成型后再做）

- [ ] **B1** 抽出 `HelperClient`（启动进程、Socket、按行收发）；主控按钮改调客户端；helper 路径改为相对/可配置，去掉硬编码绝对路径。
- [ ] **B2** 对齐现有命令：`start` / `stop` / `solid` / `off` / `quit` / `reconnect` + 解析 `status …`。
- [ ] **B3** 生命周期：退出发 `quit`；唤醒重连；确认无僵尸 helper（把烟测逻辑迁入正式壳）。
- [ ] **B4** 配置下发：JSON 变更经 IPC 传到 helper（若尚无命令，先记接口草稿，再改 C++）。

### 阶段 C — 产品债与收尾（前端 + IPC 稳后再做）

- [ ] **C1** 方案 A 默认通路确认（高 BRT + RGB 跟色）。
- [ ] **C2** 方案 B：luma → Brightness + 亮度 EMA；设置页校正滑条真正生效。
- [ ] **C3** Helper 缺口按需：COM 可配 / 自动重连、父进程监测、DXGI 恢复等。
- [ ] **C4** 全路线对照：红线复查 + 打包（helper 与 App 同目录）。
