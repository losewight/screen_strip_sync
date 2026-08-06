# 废案说明（请勿再作为控灯主线编译）

本目录存放 **Day 11–14 同进程 FFI 方案** 的学习产物，已从主线退役。

## 为什么废弃

- 发帧线程与 Flutter 渲染在**同一进程**抢资源，窗口可见时丢帧。
- Day 15 起架构改为：**helper.exe 独立进程** + 本机 IPC（回环 TCP）只传命令/状态。
- 串口唯一属主 = `helper.exe`；不再经旧 DLL / `dart:ffi` 发帧。
- 本目录为历史废案，文件名含旧工程前缀属归档，不编入主线。

## 本目录文件

| 文件 | 原用途 |
| ------ | -------- |
| `zeeray_core.cpp`（归档名） | DLL 导出 open/close/set_color/start/stop |
| `dll_test.cpp` | 原生 LoadLibrary 调 DLL 验收 |
| `serial_test.cpp` | Day 3–10 阶段串口/线程练习入口 |

## 仍在用的（不在本目录）

- `../helper_main.cpp` — 控灯主线入口
- `../serial_port.h` / `../serial_port.cpp` — 串口封装（helper 仍链接）

主线 CMake 只编 `helper`，不再编本目录内目标。
