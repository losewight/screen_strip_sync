// helper 入口：无黑窗壳 + 单实例 + 参数；串口属主启动编排交给 ipc_loop。
// 关灯 / 休眠软关 / 唤醒恢复见 helper_lifecycle.cpp。
#include "app_paths.h"
#include "autostart.h"
#include "config_store.h"
#include "dxgi_capture.h"
#include "helper_lifecycle.h"
#include "helper_log.h"
#include "ipc_loop.h"
#include "light_engine.h"
#include "tray_icon.h"
#include "ui_launcher.h"

#include <cstdio>
#include <cstring>

#include <shellapi.h>

// 与 helper.rc ProductVersion 对齐；开源诊断横幅用
static constexpr char kHelperVersion[] = "1.0.2";

// 供 H5 读取：--autostart / --no-ui 时不拉 Flutter
static bool g_silent_start = false;
static HANDLE g_singleton = nullptr;
static char g_helper_log_path[MAX_PATH] = {};

static BOOL WINAPI on_ctrl(DWORD type) {
  switch (type) {
  case CTRL_C_EVENT:
  case CTRL_CLOSE_EVENT:
  case CTRL_LOGOFF_EVENT:
  case CTRL_SHUTDOWN_EVENT:
    // 为什么：先关灯再打断 ipc，不只 cancel（否则进程退出时灯可能还亮）
    helper_shutdown();
    return TRUE;
  default:
    return FALSE;
  }
}

static HANDLE create_singleton_mutex() {
  // 为什么：NULL DACL 允许跨完整性级别（普通桌面快捷方式 ↔
  // 提权托盘）打开同一互斥体
  static SECURITY_DESCRIPTOR sd{};
  InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION);
  SetSecurityDescriptorDacl(&sd, TRUE, nullptr, FALSE);
  SECURITY_ATTRIBUTES sa{};
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = &sd;
  sa.bInheritHandle = FALSE;
  return CreateMutexW(&sa, TRUE, L"Global\\ScreenStripSyncHelper");
}

// exe 旁 helper.log 已废弃；可写数据在 %LocalAppData%\\Screen Strip Sync
static void redirect_stdio_to_log() {
  char path[MAX_PATH];
  if (!helper_log_path(path, sizeof(path))) {
    return;
  }
  strcpy_s(g_helper_log_path, path);
  helper_log_open(path);
  if (g_helper_log == nullptr)
    g_helper_log_path[0] = '\0';
}

static void print_startup_banner() {
  if (g_helper_log == nullptr) {
    return;
  }
#ifdef _DEBUG
  const char *build = "Debug";
#else
  const char *build = "Release";
#endif
  printf("=== helper %s %s silent=%d log=%s ===\n", kHelperVersion, build,
         g_silent_start ? 1 : 0,
         g_helper_log_path[0] ? g_helper_log_path : "(none)");
}

static bool arg_is_silent_flag(const wchar_t *w) {
  return _wcsicmp(w, L"--autostart") == 0 || _wcsicmp(w, L"--no-ui") == 0;
}

static void parse_cmdline_args() {
  int argc = 0;
  LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) {
    return;
  }

  // 为什么：COM 只来自 JSON（H2）；argv 仅认静默旗标
  for (int i = 1; i < argc; ++i) {
    if (arg_is_silent_flag(argv[i])) {
      g_silent_start = true;
    } else {
      printf("ignore argv: not a silent flag\n");
    }
  }

  if (g_silent_start) {
    printf("silent start (--autostart/--no-ui)\n");
  }

  LocalFree(argv);
}

int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int) {
  // 为什么：第二个实例不得开串口、不得 bind；只通知首实例开界面后立刻退出
  g_singleton = create_singleton_mutex();
  if (g_singleton == nullptr) {
    return 1;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(g_singleton);
    g_singleton = nullptr;
    ui_notify_running_instance();
    return 0;
  }

  redirect_stdio_to_log();
  data_dir_migrate_from_exe_dir();

#ifdef _DEBUG
  // 为什么：Debug 下额外开控制台方便挂调试器；printf 仍走 helper.log
  AllocConsole();
#endif

  SetConsoleCtrlHandler(on_ctrl, TRUE);
  parse_cmdline_args();
  print_startup_banner();
  printf("helper WinMain start\n");

  config_load();
  config_apply(); // 为什么：开串口前必须把内存配置打进引擎
  HelperConfig boot_cfg{};
  config_copy(&boot_cfg);
  // 为什么：JSON 真源纠注册表路径漂移；off 时清孤儿键
  autostart_reconcile(boot_cfg.startOnBoot);

  // 为什么：DXGI 失败仍要托盘+IPC（纯色/关灯可用）；追色时 engine_ensure_dxgi
  // 再试
  DxgiErr dxgi = dxgi_init();
  if (dxgi != DxgiErr::Ok) {
    printf("dxgi_init failed: %d (stay alive; capture later)\n", (int)dxgi);
  } else {
    printf("dxgi_init ok\n");
  }

  // 为什么：托盘窗兼收电源广播；ipc_run 占主线程，托盘在独立消息循环
  tray_start();

  // 为什么：串口开口可能拖数秒；丢到 boot 线程，主路径先 listen 拉 UI
  helper_boot_serial_async(boot_cfg);

  // 为什么：--no-ui/--autostart 永不拉 Flutter；未配备串口也不覆盖静默
  const bool launch_ui = !g_silent_start;
  HANDLE *serial = helper_serial();
  if (!ipc_run(9527, serial, launch_ui)) {
    printf("ipc_run failed\n");
  }

  helper_shutdown();
  tray_stop();
  ui_shutdown();
  // 为什么：先 join saver 再落盘（config_shutdown 内），避免与 debounce
  // 线程竞态用旧快照盖掉最新 JSON
  config_shutdown();
  if (g_singleton) {
    CloseHandle(g_singleton);
    g_singleton = nullptr;
  }
  helper_log_close();
  return 0;
}
