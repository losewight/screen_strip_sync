# 1. 指定 CMake 的最低版本要求，防止因为语法差异导致构建失败
cmake_minimum_required(VERSION 3.10)

project(ScreenStripSyncCore)

# 供 clangd / IDE：尽量导出编译数据库（VS 生成器偶发无效时靠 cpp_core/.clangd）
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# 源码按职责分子目录；废案 / backup 不编入。
# WIN32 = /SUBSYSTEM:WINDOWS，托盘常驻不能挂黑控制台
add_executable(helper WIN32
  app/helper_main.cpp
  app/app_paths.cpp
  app/helper_log.cpp
  app/helper_lifecycle.cpp
  config/config_store.cpp
  config/config_json.cpp
  config/autostart.cpp
  engine/serial_port.cpp
  engine/engine_params.cpp
  engine/engine_serial.cpp
  engine/engine_frame.cpp
  engine/engine_intent.cpp
  engine/wall_comp.cpp
  ipc/ipc_loop.cpp
  ipc/ipc_push.cpp
  ipc/ipc_dispatch.cpp
  capture/dxgi_capture.cpp
  capture/dxgi_region.cpp
  shell/tray_icon.cpp
  shell/ui_launcher.cpp
  shell/helper.rc
)

# 为什么：各模块互引用仍写 "foo.h"，不强制 ../engine/... 相对路径
target_include_directories(helper PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/app
  ${CMAKE_CURRENT_SOURCE_DIR}/config
  ${CMAKE_CURRENT_SOURCE_DIR}/engine
  ${CMAKE_CURRENT_SOURCE_DIR}/capture
  ${CMAKE_CURRENT_SOURCE_DIR}/ipc
  ${CMAKE_CURRENT_SOURCE_DIR}/shell
)

target_link_libraries(helper PRIVATE kernel32 shell32 ole32 comctl32 advapi32 ws2_32 d3d11 dxgi)

# 为什么：GUI 子系统下 freopen 后原生 printf 仍可能丢；/FI 宏转到 g_helper_log
# /utf-8：源文件与执行字符集均按 UTF-8，消掉中文注释触发的 C4819（代码页 936）
target_compile_options(helper PRIVATE
  "/FI${CMAKE_CURRENT_SOURCE_DIR}/app/helper_log.h"
  /utf-8
)

# experiments/frame_interval_limit：极限帧间隔摸底（控制台，不编入 helper）
add_executable(interval_limit_test
  ${CMAKE_CURRENT_SOURCE_DIR}/../experiments/frame_interval_limit/interval_limit_test.cpp
  engine/serial_port.cpp
)
target_include_directories(interval_limit_test PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/engine
)
target_link_libraries(interval_limit_test PRIVATE kernel32 winmm)
target_compile_options(interval_limit_test PRIVATE /utf-8)
