// helper 入口：串口属主启动编排 + 把命令通道交给 ipc_loop。
// 关灯 / 休眠软关 / 唤醒恢复见 helper_lifecycle.cpp。
#include "dxgi_capture.h"
#include "helper_lifecycle.h"
#include "ipc_loop.h"
#include "light_engine.h"
#include "power_watch.h"

#include <cstdio>

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

int main(int argc, char *argv[]) {
  SetConsoleCtrlHandler(on_ctrl, TRUE);

  // 为什么：Flutter 用 argv[1] 传入当前选中口，避免先死开 COM10 再 reconnect
  if (argc >= 2) {
    if (engine_set_com(argv[1])) {
      printf("com from argv: %s\n", argv[1]);
    } else {
      printf("bad com argv [%s], keep default\n", argv[1]);
    }
  }

  // 为什么：engine 线程里会反复 grab，DXGI 必须常驻到进程结束
  DxgiErr dxgi = dxgi_init();
  if (dxgi != DxgiErr::Ok) {
    printf("dxgi_init failed: %d\n", (int)dxgi);
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
    return 1;
  }

  // 为什么：控制台收不到休眠消息，隐藏窗拦 PBT_APMSUSPEND / 会话结束
  power_watch_start();

  // 阻塞
  if (!ipc_run(9527, &h)) {
    printf("ipc_run failed\n");
  }

  helper_shutdown();
  return 0;
}
