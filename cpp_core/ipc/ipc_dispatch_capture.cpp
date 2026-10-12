// 必须先于 windows.h
#include <winsock2.h>
#include <ws2tcpip.h>

#include "config_clamp.h"
#include "config_store.h"
#include "dxgi_capture.h"
#include "ipc_internal.h"
#include "ipc_loop.h"
#include "light_engine.h"

#include <cstdio>

// 换屏：停引擎 → 拆 DXGI → 按新名 init → 用实际选中的名字落盘 → 按意图恢复。
// 不动串口。失败回退 auto 再试一次，并把真实值推回 UI。
void cmd_set_capture_output(const char *wanted, HANDLE *serial, SOCKET client) {
  char clamped[64];
  clamp_capture_output(wanted, clamped, (int)sizeof(clamped));
  printf("cmd=set capture_output [%s]\n", clamped);

  engine_stop();
  dxgi_set_capture_output(clamped);
  dxgi_shutdown();
  DxgiErr e = dxgi_init();
  if (e != DxgiErr::Ok) {
    printf("set capture_output: init failed %d, retry auto\n", (int)e);
    dxgi_set_capture_output("auto");
    dxgi_shutdown();
    e = dxgi_init();
  }

  if (e != DxgiErr::Ok) {
    printf("set capture_output: auto also failed %d\n", (int)e);
    config_set_capture_output("auto");
    ipc_push_config_snapshot();
    push_runtime_status(client, false);
    return;
  }

  CaptureOutputInfo cur{};
  const char *persist = "auto";
  if (dxgi_current_output(&cur) && cur.device_name[0] != '\0')
    persist = cur.device_name;
  config_set_capture_output(persist);

  DisplayIntent intent = engine_get_display_intent();
  if (intent.kind == DisplayIntentKind::Idle) {
    HelperConfig c{};
    config_copy(&c);
    parse_last_scene(c.lastScene, &intent);
  }
  if (serial != nullptr && *serial != INVALID_HANDLE_VALUE)
    apply_display_intent(*serial, intent);

  // 为什么：auto / 不存在的名字都会被纠成真实 DeviceName，UI 必须立刻看到
  ipc_push_config_snapshot();
  push_runtime_status(client, false);
}
