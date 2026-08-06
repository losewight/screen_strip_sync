# 1. 指定 CMake 的最低版本要求，防止因为语法差异导致构建失败
cmake_minimum_required(VERSION 3.10)

# 2. 声明你的工程名称
project(ScreenStripSyncCore)

# 3. 主线（Day 15+）：独立 helper.exe = 串口属主 + IPC 命令循环
# 废案（同进程 DLL / serial_test / dll_test）已移至 废案_同进程FFI_Day11-14/，不再编入。
# backup/day19_sample_send.cpp 为源码备份，不编入。
# WIN32 = /SUBSYSTEM:WINDOWS，托盘常驻不能挂黑控制台
add_executable(helper WIN32
  helper_main.cpp
  helper_lifecycle.cpp
  config_store.cpp
  config_json.cpp
  autostart.cpp
  serial_port.cpp
  fake_bgra.cpp
  engine_params.cpp
  engine_serial.cpp
  engine_frame.cpp
  engine_intent.cpp
  ipc_loop.cpp
  ipc_push.cpp
  ipc_dispatch.cpp
  dxgi_capture.cpp
  dxgi_region.cpp
  tray_icon.cpp
  ui_launcher.cpp
  helper.rc
)
target_link_libraries(helper PRIVATE kernel32 shell32 comctl32 advapi32 ws2_32 d3d11 dxgi)
# 为什么：GUI 子系统下 freopen 后原生 printf 仍可能丢；/FI 宏转到 g_helper_log
# /utf-8：源文件与执行字符集均按 UTF-8，消掉中文注释触发的 C4819（代码页 936）
target_compile_options(helper PRIVATE
  "/FI${CMAKE_CURRENT_SOURCE_DIR}/helper_log.h"
  /utf-8
)