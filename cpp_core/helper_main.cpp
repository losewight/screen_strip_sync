// helper 入口：无黑窗壳 + 单实例 + 参数；串口属主启动编排交给 ipc_loop。
// 关灯 / 休眠软关 / 唤醒恢复见 helper_lifecycle.cpp。
#include "config_store.h"
#include "dxgi_capture.h"
#include "helper_lifecycle.h"
#include "ipc_loop.h"
#include "light_engine.h"
#include "tray_icon.h"

#include <cstdio>
#include <cstring>
#include <share.h>
#include <wchar.h>

#include <shellapi.h>

// 供 helper_log.h 宏使用；_fsopen 可边跑边读
FILE *g_helper_log = nullptr;

// 供 H5 读取：--autostart / --no-ui 时不拉 Flutter
static bool g_silent_start = false;
static HANDLE g_singleton = nullptr;

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

// exe 同目录 helper.log；保留全项目 printf，不逐个改
static void redirect_stdio_to_log() {
  char path[MAX_PATH];
  DWORD n = GetModuleFileNameA(nullptr, path, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) {
    return;
  }
  char *slash = strrchr(path, '\\');
  if (!slash) {
    return;
  }
  // 为什么：截掉文件名，拼 helper.log（与配置同目录规则一致）
  strcpy_s(slash + 1, MAX_PATH - (slash + 1 - path), "helper.log");

  // 为什么：_SH_DENYNO 允许验收时边跑边读；无缓冲避免日志晚到
  g_helper_log = _fsopen(path, "a", _SH_DENYNO);
  if (!g_helper_log) {
    return;
  }
  setvbuf(g_helper_log, nullptr, _IONBF, 0);

  // 顺带挂 stdout/stderr，便于将来 fprintf(stdout)；主通道仍是 g_helper_log
  FILE *fp = nullptr;
  freopen_s(&fp, path, "a", stdout);
  freopen_s(&fp, path, "a", stderr);
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
  // 为什么：第二个实例不得开串口、不得 bind；H5 再加「通知首实例开界面」
  g_singleton = CreateMutexW(nullptr, TRUE, L"Local\\ZeerayHelperSingleton");
  if (g_singleton == nullptr) {
    return 1;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(g_singleton);
    g_singleton = nullptr;
    return 0;
  }

  redirect_stdio_to_log();
  printf("helper WinMain start\n");

#ifdef _DEBUG
  // 为什么：Debug 下额外开控制台方便挂调试器；printf 仍走 helper.log
  AllocConsole();
#endif

  SetConsoleCtrlHandler(on_ctrl, TRUE);
  parse_cmdline_args();

  config_load();
  config_apply();

  // 为什么：engine 线程里会反复 grab，DXGI 必须常驻到进程结束
  DxgiErr dxgi = dxgi_init();
  if (dxgi != DxgiErr::Ok) {
    printf("dxgi_init failed: %d\n", (int)dxgi);
    config_shutdown();
    return 1;
  }
  printf("dxgi_init ok\n");

  HANDLE h = INVALID_HANDLE_VALUE;
  helper_set_serial(&h);

  const int max_tries = 10;
  bool ready = false;
  for (int i = 1; i <= max_tries; ++i) {
    if (try_serial_ready(&h)) {
      ready = true;
      printf("serial ready (try %d/%d)\n", i, max_tries);
      break;
    }
    printf("serial not ready (try %d/%d)\n", i, max_tries);
    Sleep(500);
  }
  if (!ready) {
    printf("serial give up after %d tries\n", max_tries);
    dxgi_shutdown();
    config_shutdown();
    return 1;
  }

  {
    char com[16];
    engine_get_com(com, sizeof(com));
    config_set_last_connected_com(com);
  }

  // 为什么：托盘窗兼收电源广播；ipc_run 占主线程，托盘在独立消息循环
  tray_start();

  // 阻塞
  if (!ipc_run(9527, &h)) {
    printf("ipc_run failed\n");
  }

  helper_shutdown();
  tray_stop();
  // 为什么：先 join saver 再落盘（config_shutdown 内），避免与 debounce
  // 线程竞态用旧快照盖掉最新 JSON
  config_shutdown();
  if (g_singleton) {
    CloseHandle(g_singleton);
    g_singleton = nullptr;
  }
  if (g_helper_log) {
    fclose(g_helper_log);
    g_helper_log = nullptr;
  }
  return 0;
}
