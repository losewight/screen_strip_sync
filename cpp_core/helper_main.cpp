// helper 入口：串口属主生命周期 + 把命令通道交给 ipc_loop。
// Day19 假图打印见 fake_bgra（当前不调用）；发灯备份见
// backup/day19_sample_send.cpp。
#include "dxgi_capture.h"
#include "ipc_loop.h"
#include "light_engine.h"
#include "serial_port.h"

#include <cstdio>

int main(int argc, char *argv[]) {
  (void)argc;
  (void)argv;

  // 为什么：engine 线程里会反复 grab，DXGI 必须常驻到进程结束
  DxgiErr dxgi = dxgi_init();
  if (dxgi != DxgiErr::Ok) {
    printf("dxgi_init failed: %d\n", (int)dxgi);
    return 1;
  }
  printf("dxgi_init ok\n");

  HANDLE h = INVALID_HANDLE_VALUE;
  if (!open_com("COM10", &h)) {
    printf("open_com failed\n");
    dxgi_shutdown();
    return 1;
  }
  if (!power_on(h) || !handshake(h)) {
    printf("power_on/handshake failed\n");
    power_off(h);
    close_com(h);
    dxgi_shutdown();
    return 1;
  }
  printf("serial ready\n");

  // 阻塞
  if (!ipc_run(9527, h)) {
    printf("ipc_run failed\n");
  }

  engine_stop();
  power_off(h);
  close_com(h);
  dxgi_shutdown();
  return 0;
}
