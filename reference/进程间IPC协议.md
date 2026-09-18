# Screen Strip Sync — 进程间 IPC 协议

本文描述本软件内部 **Flutter 界面 ↔ `helper.exe`** 的本机通信约定。  
灯带串口协议见 [`灯带串口通信协议.md`](./灯带串口通信协议.md)。

界面是可选的；关掉界面不应导致灯灭或 helper 退出。逐帧像素只在 helper 内处理，**不经 IPC 传输**。

---

## 1. 传输约定

| 项 | 值 |
| --- | --- |
| 地址 | `127.0.0.1:9527`（仅本机回环） |
| 形态 | TCP，一行一条，建议以 `\n` 结尾 |
| 客户端数 | 同时只服务 **1** 个；新连接踢掉旧连接 |
| 行长上限 | **512 字符**（超长丢弃到行尾） |
| 与串口帧长 | **无关**（串口工程上限是 &lt;120 字节，见串口文档） |
| 未知命令 | 记日志后忽略，服务不崩溃 |

---

## 2. 界面 → helper

| 文本 | 含义 |
| --- | --- |
| `sync` | 请求全量配置与状态快照 |
| `start` | 屏幕跟色（map）；持久化场景为 `engine` |
| `start_region` | 屏幕氛围（region）；与 `start` 互斥；场景为 `region` |
| `stop` | 停止引擎（map / region 共用） |
| `solid RRGGBB` | 发送一帧纯色（6 位 hex） |
| `soft_off` | UI 关灯：停引擎 + 纯黑帧；**不**调用设备 `set_power 0` |
| `off` | 真下电：停引擎 + 设备 `set_power 0`（界面很少用） |
| `bye` | 前端退出：只关闭当前连接，灯效与 helper 保持 |
| `quit` | 关闭后台服务：关灯 → 停引擎 → 关串口 → helper 退出 |
| `reconnect` | 关闭串口并重试就绪（最多约 10 次） |
| `set alpha <0.05..1>` | map EMA α |
| `set near_black <0..64>` | map 近黑丢弃阈值；默认 15 |
| `set blur <0..8>` | map 邻域半宽；默认 2 |
| `set saturation <0.5..2>` | map 饱和度增益；默认 1.4 |
| `set mode a\|b` | 已废弃，仅兼容旧配置 |
| `set com COMn` | 只改配置；真正切串口需 `reconnect` |
| `set sleep_sync 0\|1` | 休眠同步 |
| `set shutdown_off 0\|1` | 关机 / 注销时是否关灯 |
| `set autostart 0\|1` | 写入注册表开机自启 |
| `highlight <0..9>` | 校准：仅点亮指定段 |
| `set map default` | 恢复顶边均分采样 |
| `set map x0,y0,x1,y1;...` | 10 段矩形（被抓那块屏的 0..100 百分比） |
| `set region_algo mean\|max` | 氛围聚合算法 |
| `set region_blur <0..20>` | 氛围空间模糊 |
| `set region_smooth <0..0.99>` | 氛围时间惯性（与 map α「越大越跟手」极性相反） |
| `set region_dark <0..50>` | 氛围暗场阈值 |
| `set region_bbox L,T,W,H` | 氛围取色框（被抓那块屏的百分比整数 0..100） |
| `set capture_output <DeviceName\|auto>` | DXGI 抓哪块屏；`auto` = 主屏。热切换不动串口 |
| `set last_custom_solid RRGGBB` | 记住自定义纯色 |

`set …` 生效后，helper 会 debounce（约 1 秒）写回 JSON。场景类命令会更新 `lastScene`。数值在 helper 侧夹紧。

---

## 3. helper → 界面

| 文本 | 含义 |
| --- | --- |
| `cfg <key> <value>` | 配置快照项（key 与 `set` 同名，含 `capture_output`） |
| `cfg map …` | 当前采样映射 |
| `cfg scene …` | `engine` / `region` / `solid RRGGBB` / `off` / `idle` |
| `cfg end` | 快照结束；界面收到后才视为配置完整 |
| `status ready` | 串口已就绪 |
| `status reconnecting` / `reconnect_ok` / `reconnect_fail` | 重连过程 |
| `status com COMn` | 当前打开的 COM |
| `status engine 0\|1` | 发帧线程是否在运行 |
| `status display …` | `engine` / `region` / `solid` / `soft_off` / `idle` |
| `status capture_output NAME WxH L,T [friendly…]` | 当前 duplicate 的屏＋桌面矩形；友好名可选 |
| `status outputs <n>` | 随后 n 条 `status output` |
| `status output i NAME WxH L,T p c [friendly…]` | 可 duplicate 的一块屏（primary / current） |
| `status serial_lost` / `serial_ok` | 串口掉线 / 恢复（部分路径） |
| `ui show` | 托盘请求：把已有窗口置顶 |

连接建立时，helper 会主动推送一轮 `cfg …` + `cfg end` + `status …`。

---

## 4. 两条追色路径

| 路径 | IPC 入口 | 采样 |
| --- | --- | --- |
| 屏幕跟色 map | `start` | `segmentMap` 或顶边均分；百分比相对被抓那块屏；α / near_black / blur / saturation |
| 屏幕氛围 region | `start_region` | `region_bbox` 竖直切 10 段；bbox 相对被抓那块屏；mean/max + blur/smooth/dark |

截图与框选只在 Flutter 完成；IPC 只传百分比等结果，不传像素流。

---

## 5. 配置文件字段

文件：`screen_strip_sync_config.json`（与可执行文件同目录）。  
**只有 helper 写盘**；界面只收快照、只发 `set`。

| 字段 | 含义 |
| --- | --- |
| `emaAlpha` | map EMA |
| `nearBlack` | map 近黑阈值 |
| `blurStep` | map blur |
| `saturation` | 饱和度 |
| `mode` | 废弃字段，兼容保留 |
| `comPort` / `lastConnectedCom` | 串口 |
| `captureOutput` | DXGI DeviceName；空 = auto 跟主屏 |
| `autoSleepSync` | 休眠同步 |
| `turnOffOnShutdown` | 关机关灯 |
| `startOnBoot` | 开机自启 |
| `segmentMap` | map 段矩形 |
| `regionAlgo` / `regionBlur` / `regionSmooth` / `regionDark` / `regionBBox` | region |
| `lastScene` | `engine` / `region` / `solid RRGGBB` / `off` / `idle` |
| `lastCustomSolid` | 自定义纯色 hex，可空 |

缺字段用默认；解析失败整体回退且不阻塞启动。  
串口帧长上限与 50 ms 节流**不是**配置项。

---

## 6. 与产品动作的对应

| 用户动作 | IPC | 对灯带的影响（概念） |
| --- | --- | --- |
| 关界面窗口 | `bye` | 不断灯；helper 继续 |
| 界面「关灯」 | `soft_off` | 停追色 + 黑帧；一般不下电 |
| 托盘退出 / 完全退出 | `quit` | 关灯并退出 helper（真下电走 `set_power 0` 一类路径） |
