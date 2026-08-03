#include "helper_lifecycle.h"

#include "dxgi_capture.h"
#include "ipc_loop.h"
#include "light_engine.h"
#include "serial_port.h"

#include <atomic>
#include <cstdio>

static HANDLE *g_serial = nullptr;
static std::atomic_bool g_shutting_down{false};
// 为什么：方案三开=硬关，关=休眠不碰；与 Flutter autoSleepSync 对齐下发
static std::atomic_bool g_sleep_sync{true};

void helper_set_serial(HANDLE *serial) { g_serial = serial; }

HANDLE *helper_serial() { return g_serial; }

void helper_set_sleep_sync(bool on) {
  g_sleep_sync.store(on);
  printf("sleep_sync=%d\n", on ? 1 : 0);
}

bool helper_get_sleep_sync() { return g_sleep_sync.load(); }

// 为什么：休眠窗口极短——先喊停再立刻 set_power 0，最后才 join；多路径共用防重入
void helper_shutdown() {
  bool expected = false;
  if (!g_shutting_down.compare_exchange_strong(expected, true))
    return;

  printf("helper_shutdown begin\n");
  engine_request_stop();
  if (g_serial != nullptr && *g_serial != INVALID_HANDLE_VALUE) {
    power_off(*g_serial); // 趁 USB 还能写，优先灭灯
  }
  engine_stop(); // join 发帧线程
  if (g_serial != nullptr && *g_serial != INVALID_HANDLE_VALUE) {
    close_com(*g_serial);
    *g_serial = INVALID_HANDLE_VALUE;
  }
  dxgi_shutdown();
  ipc_cancel();
  printf("helper_shutdown done\n");
}
