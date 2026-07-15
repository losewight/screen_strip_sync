# 1. 指定 CMake 的最低版本要求，防止因为语法差异导致构建失败
cmake_minimum_required(VERSION 3.10)

# 2. 声明你的工程名称
project(ZeerayCore)

# 3. 核心指令：将源码编译为动态链接库
# SHARED 关键字是这里的灵魂，它明确指示编译器生成 .dll（动态库），而不是 .exe（可执行文件）或静态库
add_library(zeeray_core SHARED 
    zeeray_core.cpp
)