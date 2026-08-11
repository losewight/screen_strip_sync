#include "helper_lifecycle.h"

#include "config_store.h"
#include "dxgi_capture.h"
#include "ipc_loop.h"
#include "light_engine.h"
#include "serial_port.h"
#include "ui_launcher.h"

#include <atomic>
#include <cstdio>
#include <mutex>
#include <thread>

static HANDLE *g_serial = nullptr;
static std::atomic_bool g_shutting_down{false};
static std::atomic_bool g_sleep_sync{true};

// 休眠已拆资源；防 QUERYSUSPEND+SUSPEND 连发覆盖快照
static std::atomic_bool g_resources_torn{false};
static std::atomic_bool g_awaiting_resume{false};
static std::mutex g_resume_mu;
static DisplayIntent g_resume_intent{};

void helper_set_serial(HANDLE *serial) { g_serial = serial; }

HANDLE *helper_serial() { return g_serial; }

void helper_set_sleep_sync(bool on) {
  g_sleep_sync.store(on);
  printf("sleep_sync=%d\n", on ? 1 : 0);
}

bool helper_get_sleep_sync() { return g_sleep_sync.load(); }

void helper_note_resources_ready() { g_resources_torn.store(false); }

void helper_on_suspend() {
  if (g_shutting_down.load())
    return;

  bool expected = false;
  if (!g_resources_torn.compare_exchange_strong(expected, true)) {
    printf("suspend: already torn, skip\n");
    return;
  }

  // 为什么：开关只影响醒来；休眠拆法相同。开则先快照再拆。
  if (g_sleep_sync.load()) {
    std::lock_guard<std::mutex> lock(g_resume_mu);
    g_resume_intent = engine_get_display_intent();
    g_awaiting_resume.store(true);
    printf("suspend: snapshot kind=%d for resume\n", (int)g_resume_intent.kind);
  } else {
    g_awaiting_resume.store(false);
    printf("suspend: sleep_sync off, no resume\n");
  }

  engine_stop();
  if (g_serial != nullptr && *g_serial != INVALID_HANDLE_VALUE) {
    // 软关：黑帧，不用 set_power 0（唤醒还要开口）
    send_solid(*g_serial, "000000");
    close_com(*g_serial);
    *g_serial = INVALID_HANDLE_VALUE;
  }
  engine_set_intent_idle();
  dxgi_shutdown();
  ipc_push_runtime_status();
  printf("suspend: resources torn (com/dxgi/engine)\n");
}

void helper_resume_from_sleep() {
  if (g_shutting_down.load())
    return;

  if (!g_awaiting_resume.load()) {
    printf("resume: skip (sleep_sync was off or no snapshot)\n");
    return;
  }

  // 为什么：系统常连发 RESUMEAUTOMATIC + RESUMESUSPEND；只跑一遍
  static std::atomic_bool g_resuming{false};
  bool expected = false;
  if (!g_resuming.compare_exchange_strong(expected, true)) {
    printf("resume: already in progress\n");
    return;
  }

  // 为什么：DXGI 重试可能数秒，不能堵托盘消息泵
  std::thread([] {
    printf("resume: begin\n");

    DisplayIntent snap{};
    {
      std::lock_guard<std::mutex> lock(g_resume_mu);
      snap = g_resume_intent;
    }

    // 1) 先重开串口（纯色不依赖 DXGI；桌面复制唤醒后常短暂 ACCESS_DENIED）
    if (!config_get().serialConfigured) {
      printf("resume: serialConfigured=0; skip serial reopen\n");
      g_awaiting_resume.store(false);
      ipc_push_runtime_status();
      g_resuming.store(false);
      return;
    }

    HANDLE neu = INVALID_HANDLE_VALUE;
    bool serial_ok = false;
    for (int i = 1; i <= 10; ++i) {
      if (g_shutting_down.load())
        break;
      if (try_serial_ready(&neu)) {
        serial_ok = true;
        printf("resume: serial ok (try %d/10)\n", i);
        break;
      }
      printf("resume: serial fail (try %d/10)\n", i);
      Sleep(500);
    }

    if (!serial_ok) {
      printf("resume: give up serial\n");
      g_awaiting_resume.store(false);
      ipc_push_runtime_status();
      g_resuming.store(false);
      return;
    }

    if (g_serial != nullptr)
      *g_serial = neu;

    // 2) 追色才要 DXGI；唤醒后 DuplicateOutput 常 0x80070005，多试几次
    if (snap.kind == DisplayIntentKind::Engine ||
        snap.kind == DisplayIntentKind::Region) {
      bool dxgi_ok = false;
      for (int i = 1; i <= 20; ++i) {
        if (g_shutting_down.load())
          break;
        if (engine_ensure_dxgi()) {
          dxgi_ok = true;
          printf("resume: dxgi ok (try %d/20)\n", i);
          break;
        }
        printf("resume: dxgi retry %d/20\n", i);
        Sleep(500);
      }
      if (!dxgi_ok) {
        printf("resume: dxgi give up -> soft_off (was engine/region)\n");
        engine_stop();
        engine_set_intent_soft_off();
        send_solid(neu, "000000");
        g_awaiting_resume.store(false);
        helper_note_resources_ready();
        ipc_push_runtime_status();
        g_resuming.store(false);
        return;
      }
    }

    apply_display_intent(neu, snap);
    g_awaiting_resume.store(false);
    helper_note_resources_ready();
    ipc_push_runtime_status();
    printf("resume: done\n");
    g_resuming.store(false);
  }).detach();
}

// 为什么：休眠窗口极短——先喊停再立刻 set_power 0，最后才 join；多路径共用防重入
void helper_shutdown() {
  bool expected = false;
  if (!g_shutting_down.compare_exchange_strong(expected, true))
    return;

  printf("helper_shutdown begin\n");
  g_awaiting_resume.store(false);
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
  ui_shutdown(); // 只关子进程句柄，不杀 Flutter
  printf("helper_shutdown done\n");
}
