# 1. 指定 CMake 的最低版本要求，防止因为语法差异导致构建失败
cmake_minimum_required(VERSION 3.10)

# 2. 声明你的工程名称
project(ZeerayCore)

# 3. 主线（Day 15+）：独立 helper.exe = 串口属主 + IPC 命令循环
# 废案（同进程 DLL / serial_test / dll_test）已移至 废案_同进程FFI_Day11-14/，不再编入。
# backup/day19_sample_send.cpp 为源码备份，不编入。
add_executable(helper
  helper_main.cpp
  helper_lifecycle.cpp
  serial_port.cpp
  fake_bgra.cpp
  light_engine.cpp
  ipc_loop.cpp
  dxgi_capture.cpp
  power_watch.cpp
)
target_link_libraries(helper PRIVATE kernel32 ws2_32 d3d11 dxgi)