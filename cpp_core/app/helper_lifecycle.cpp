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

// 为什么：HANDLE 若在 WinMain 栈上，唤醒线程写回时主线程可能已进入 shutdown
static HANDLE g_serial_handle = INVALID_HANDLE_VALUE;

static std::atomic_bool g_shutting_down{false};
static std::atomic_bool g_sleep_sync{true};
static std::atomic_bool g_screen_off_sync{false};
static std::atomic_bool g_monitor_blanked{false};

// 休眠已拆资源；防 QUERYSUSPEND+SUSPEND 连发覆盖快照
static std::atomic_bool g_resources_torn{false};
static std::atomic_bool g_awaiting_resume{false};
static std::mutex g_resume_mu;
static DisplayIntent g_resume_intent{};

static std::mutex g_resume_thread_mu;
static std::thread g_resume_worker;
static std::atomic_bool g_resuming{false};

// 启动期串口 worker：与 resume 对称；boot / reconnect 共用同一槽
static std::mutex g_boot_thread_mu;
static std::thread g_boot_worker;
static std::atomic_bool g_boot_busy{false};
// 为什么：boot/reconnect 进行中再点 reconnect 不能丢；结尾再跑一轮
static std::atomic_bool g_reconnect_pending{false};

HANDLE *helper_serial() { return &g_serial_handle; }

bool helper_is_shutting_down() { return g_shutting_down.load(); }

void helper_set_sleep_sync(bool on) {
  g_sleep_sync.store(on);
  printf("sleep_sync=%d\n", on ? 1 : 0);
}

bool helper_get_sleep_sync() { return g_sleep_sync.load(); }

void helper_note_resources_ready() { g_resources_torn.store(false); }

void helper_set_screen_off_sync(bool on) {
  g_screen_off_sync.store(on);
  printf("screen_off_sync=%d\n", on ? 1 : 0);
}

bool helper_get_screen_off_sync() { return g_screen_off_sync.load(); }

void helper_on_monitor_off() {
  if (g_shutting_down.load()) return;
  if (!g_screen_off_sync.load()) return;

  bool expected = false;
  if (!g_monitor_blanked.compare_exchange_strong(expected, true)) return;

  engine_stop();
  HANDLE *p = helper_serial();
  if (p && *p != INVALID_HANDLE_VALUE) {
    send_solid(*p, "000000");
  }
  ipc_push_runtime_status();
  printf("monitor off: blanked (intent preserved)\n");
}

void helper_on_monitor_on() {
  if (g_shutting_down.load()) return;
  
  bool expected = true;
  if (!g_monitor_blanked.compare_exchange_strong(expected, false)) return;
  
  HANDLE *p = helper_serial();
  if (!p || *p == INVALID_HANDLE_VALUE) {
    printf("monitor on: no serial, skip restore\n");
    return;
  }
  
  DisplayIntent intent = engine_get_display_intent();
  apply_display_intent(*p, intent);
  ipc_push_runtime_status();
  printf("monitor on: restored intent kind=%d\n", (int)intent.kind);
}

static void sleep_interruptible_shutdown(DWORD ms) {
  const DWORD slice = 50;
  const DWORD start = GetTickCount();
  while (!g_shutting_down.load()) {
    const DWORD elapsed = GetTickCount() - start;
    if (elapsed >= ms)
      break;
    DWORD left = ms - elapsed;
    if (left > slice)
      left = slice;
    Sleep(left);
  }
}

void helper_on_suspend() {
  g_monitor_blanked.store(false); // suspend 接管，blanked 语义结束
  if (g_shutting_down.load())
    return;
  // 为什么：sleep_sync=0 必须完全 no-op；拆 COM 会把正在追色的灯带弄灭
  if (!g_sleep_sync.load()) {
    printf("suspend: sleep_sync=0, no-op\n");
    return;
  }

  bool expected = false;
  if (!g_resources_torn.compare_exchange_strong(expected, true)) {
    printf("suspend: already torn, skip\n");
    return;
  }

  {
    std::lock_guard<std::mutex> lock(g_resume_mu);
    g_resume_intent = engine_get_display_intent();
    g_awaiting_resume.store(true);
    printf("suspend: snapshot kind=%d for resume\n", (int)g_resume_intent.kind);
  }

  // 为什么：停发帧 + 拆 DXGI 同锁，避免 stop 与 shutdown 之间被 start 插队
  engine_stop_and_release_dxgi();
  HANDLE *p = helper_serial();
  if (p != nullptr && *p != INVALID_HANDLE_VALUE) {
    // 软关：黑帧，不用 set_power 0（唤醒还要开口）
    send_solid(*p, "000000");
    close_com(*p);
    *p = INVALID_HANDLE_VALUE;
  }
  engine_set_intent_idle();
  ipc_push_runtime_status();
  printf("suspend: resources torn (com/dxgi/engine)\n");
}

static void resume_worker_body() {
  printf("resume: begin\n");

  DisplayIntent snap{};
  {
    std::lock_guard<std::mutex> lock(g_resume_mu);
    snap = g_resume_intent;
  }

  auto abort_owned = [](HANDLE neu) {
    if (neu != INVALID_HANDLE_VALUE) {
      power_off(neu);
      close_com(neu);
    }
    g_awaiting_resume.store(false);
    g_resuming.store(false);
  };

  HelperConfig cfg{};
  config_copy(&cfg);
  if (!cfg.serialConfigured) {
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
    sleep_interruptible_shutdown(500);
  }

  if (!serial_ok) {
    printf("resume: give up serial\n");
    abort_owned(neu);
    ipc_push_runtime_status();
    return;
  }

  // 为什么：写回前必须再看退出旗标；已 shutdown 则本线程负责灭灯关口，禁止覆盖 INVALID
  if (g_shutting_down.load()) {
    printf("resume: shutting down, drop new handle\n");
    abort_owned(neu);
    return;
  }

  HANDLE *p = helper_serial();
  if (p != nullptr)
    *p = neu;

  if (g_shutting_down.load()) {
    // shutdown 正在 join 我们，随后会 power_off+close 这份句柄；这里不要双关
    printf("resume: wrote handle but shutdown raced; yield to shutdown\n");
    g_awaiting_resume.store(false);
    g_resuming.store(false);
    return;
  }

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
      sleep_interruptible_shutdown(500);
    }
    if (!dxgi_ok) {
      printf("resume: dxgi give up -> soft_off (was engine/region)\n");
      if (g_shutting_down.load()) {
        g_awaiting_resume.store(false);
        g_resuming.store(false);
        return;
      }
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

  if (g_shutting_down.load()) {
    g_awaiting_resume.store(false);
    g_resuming.store(false);
    return;
  }

  apply_display_intent(neu, snap);
  g_monitor_blanked.store(false); // 唤醒后显示器必亮
  g_awaiting_resume.store(false);
  helper_note_resources_ready();
  ipc_push_runtime_status();
  printf("resume: done\n");
  g_resuming.store(false);
}

void helper_resume_from_sleep() {
  if (g_shutting_down.load())
    return;
  if (!g_sleep_sync.load()) {
    printf("resume: sleep_sync=0, no-op\n");
    return;
  }

  if (!g_awaiting_resume.load()) {
    printf("resume: skip (no snapshot)\n");
    return;
  }

  // 为什么：系统常连发 RESUMEAUTOMATIC + RESUMESUSPEND；只跑一遍
  bool expected = false;
  if (!g_resuming.compare_exchange_strong(expected, true)) {
    printf("resume: already in progress\n");
    return;
  }

  std::lock_guard<std::mutex> lock(g_resume_thread_mu);
  if (g_shutting_down.load()) {
    g_resuming.store(false);
    return;
  }
  if (g_resume_worker.joinable())
    g_resume_worker.join();
  g_resume_worker = std::thread(resume_worker_body);
}

// 一次 reconnect：停引擎、关旧口、重开、恢复 intent；可被 shutdown 打断
static void reconnect_once() {
  printf("reconnect: begin\n");

  engine_stop();
  HANDLE *p = helper_serial();
  if (p != nullptr && *p != INVALID_HANDLE_VALUE) {
    close_com(*p);
    *p = INVALID_HANDLE_VALUE;
  }
  // 为什么：休眠 teardown 关过 DXGI；重连后追色要能抓屏
  engine_ensure_dxgi();

  HANDLE neu = INVALID_HANDLE_VALUE;
  bool ok = false;
  for (int i = 1; i <= 10; ++i) {
    if (g_shutting_down.load())
      break;
    if (try_serial_ready(&neu)) {
      ok = true;
      printf("reconnect: try %d ok\n", i);
      break;
    }
    printf("reconnect: try %d failed\n", i);
    sleep_interruptible_shutdown(500);
  }

  if (!ok) {
    printf("reconnect: failed\n");
    if (neu != INVALID_HANDLE_VALUE) {
      power_off(neu);
      close_com(neu);
    }
    if (!g_shutting_down.load()) {
      engine_set_intent_idle();
      if (ipc_has_client())
        ipc_push_serial_fail();
    }
    return;
  }

  // 为什么：写回前必须再看退出旗标；已 shutdown 则本线程负责灭灯关口，禁止覆盖 INVALID
  if (g_shutting_down.load()) {
    printf("reconnect: shutting down, drop new handle\n");
    if (neu != INVALID_HANDLE_VALUE) {
      power_off(neu);
      close_com(neu);
    }
    return;
  }

  if (p != nullptr)
    *p = neu;

  if (g_shutting_down.load()) {
    // shutdown 正在 join 我们，随后会 power_off+close；这里不要双关
    printf("reconnect: wrote handle but shutdown raced; yield to shutdown\n");
    return;
  }

  helper_note_resources_ready();
  char com[16];
  engine_get_com(com, sizeof(com));
  config_set_last_connected_com(com);
  config_set_serial_configured(true);

  DisplayIntent intent = engine_get_display_intent();
  if (intent.kind == DisplayIntentKind::Idle) {
    HelperConfig c{};
    config_copy(&c);
    parse_last_scene(c.lastScene, &intent);
  }
  apply_display_intent(neu, intent);

  if (!g_shutting_down.load() && ipc_has_client())
    ipc_push_reconnect_ok();
  printf("reconnect: done\n");
}

// 为什么：在 g_boot_thread_mu 下清 busy / 看 pending，禁止 worker 内 spawn+join 自己
// push_boot_ready：boot 成功且无 pending 时推 ready；boot 失败且无 pending 推 fail
enum class SerialExitPush { None, Ready, Fail };

static void serial_worker_exit(SerialExitPush push) {
  for (;;) {
    bool run_reconnect = false;
    SerialExitPush do_push = SerialExitPush::None;
    {
      std::lock_guard<std::mutex> lock(g_boot_thread_mu);
      if (g_shutting_down.load()) {
        g_boot_busy.store(false);
        return;
      }
      if (g_reconnect_pending.exchange(false)) {
        // busy 保持 true；解锁后同线程跑 reconnect
        run_reconnect = true;
      } else {
        g_boot_busy.store(false);
        do_push = push;
      }
    }
    if (run_reconnect) {
      reconnect_once();
      push = SerialExitPush::None; // reconnect 自己推 ok/fail
      continue;
    }
    if (do_push == SerialExitPush::Ready && ipc_has_client())
      ipc_push_serial_ready();
    else if (do_push == SerialExitPush::Fail && ipc_has_client())
      ipc_push_serial_fail();
    return;
  }
}

static void reconnect_worker_body() {
  reconnect_once();
  serial_worker_exit(SerialExitPush::None);
}

static void boot_worker_body(HelperConfig boot_cfg) {
  printf("boot: begin serialConfigured=%d\n",
         boot_cfg.serialConfigured ? 1 : 0);

  auto abort_owned = [](HANDLE neu) {
    if (neu != INVALID_HANDLE_VALUE) {
      power_off(neu);
      close_com(neu);
    }
  };

  if (!boot_cfg.serialConfigured) {
    printf("boot: serialConfigured=0; skip auto open\n");
    serial_worker_exit(SerialExitPush::None);
    return;
  }

  HANDLE neu = INVALID_HANDLE_VALUE;
  bool serial_ok = false;
  for (int i = 1; i <= 10; ++i) {
    if (g_shutting_down.load())
      break;
    if (try_serial_ready(&neu)) {
      serial_ok = true;
      printf("boot: serial ok (try %d/10)\n", i);
      break;
    }
    printf("boot: serial fail (try %d/10)\n", i);
    sleep_interruptible_shutdown(500);
  }

  if (!serial_ok) {
    // 为什么：无灯带也不能退进程；托盘+IPC 已常驻，用户可稍后换口/重连
    printf("boot: give up after 10 tries; stay alive without COM\n");
    abort_owned(neu);
    // pending reconnect 会再试并推结果；无 pending 才推 fail
    serial_worker_exit(SerialExitPush::Fail);
    return;
  }

  // 为什么：写回前必须再看退出旗标；已 shutdown 则本线程负责灭灯关口，禁止覆盖 INVALID
  if (g_shutting_down.load()) {
    printf("boot: shutting down, drop new handle\n");
    abort_owned(neu);
    serial_worker_exit(SerialExitPush::None);
    return;
  }

  HANDLE *p = helper_serial();
  if (p != nullptr)
    *p = neu;

  if (g_shutting_down.load()) {
    // shutdown 正在 join 我们，随后会 power_off+close；这里不要双关
    printf("boot: wrote handle but shutdown raced; yield to shutdown\n");
    serial_worker_exit(SerialExitPush::None);
    return;
  }

  char com[16];
  engine_get_com(com, sizeof(com));
  config_set_last_connected_com(com);
  config_set_serial_configured(true);

  DisplayIntent boot{};
  if (parse_last_scene(boot_cfg.lastScene, &boot)) {
    apply_display_intent(neu, boot);
  } else {
    printf("boot: bad lastScene [%s], stay idle\n", boot_cfg.lastScene);
  }

  helper_note_resources_ready();
  printf("boot: done\n");
  // 为什么：先清 busy 再推 ready（serial_worker_exit）；有 pending 则同线程 drain
  serial_worker_exit(SerialExitPush::Ready);
}

void helper_boot_serial_async(const HelperConfig &boot_cfg) {
  if (g_shutting_down.load())
    return;

  // 为什么：未配备不造线程；与 WinMain 旧路径「skip auto open」同语义
  if (!boot_cfg.serialConfigured) {
    printf("boot: serialConfigured=0; skip thread\n");
    return;
  }

  HelperConfig copy = boot_cfg;
  std::thread to_join;
  {
    std::lock_guard<std::mutex> lock(g_boot_thread_mu);
    if (g_shutting_down.load())
      return;
    if (g_boot_worker.joinable())
      to_join = std::move(g_boot_worker);
  }
  // 为什么：锁外 join；worker exit 也要拿同一把锁
  if (to_join.joinable())
    to_join.join();

  std::lock_guard<std::mutex> lock(g_boot_thread_mu);
  if (g_shutting_down.load())
    return;
  if (g_boot_busy.load()) {
    // 竞态：join 后另一条路径又占了槽；boot 只启动一次，挂 reconnect 即可
    g_reconnect_pending.store(true);
    printf("boot: serial worker busy after join; pending reconnect\n");
    return;
  }
  g_boot_busy.store(true);
  g_boot_worker = std::thread(boot_worker_body, copy);
  printf("boot: async started\n");
}

void helper_reconnect_serial_async() {
  if (g_shutting_down.load())
    return;

  std::thread to_join;
  {
    std::lock_guard<std::mutex> lock(g_boot_thread_mu);
    if (g_shutting_down.load())
      return;

    // 为什么：busy 时只挂 pending，IPC 不 join；worker 在 exit 握手里 drain
    if (g_boot_busy.load()) {
      g_reconnect_pending.store(true);
      printf("reconnect: pending (serial worker busy)\n");
      return;
    }

    if (g_boot_worker.joinable())
      to_join = std::move(g_boot_worker);
  }
  if (to_join.joinable())
    to_join.join();

  std::lock_guard<std::mutex> lock(g_boot_thread_mu);
  if (g_shutting_down.load())
    return;
  if (g_boot_busy.load()) {
    g_reconnect_pending.store(true);
    printf("reconnect: pending (serial worker busy after join)\n");
    return;
  }
  g_boot_busy.store(true);
  g_reconnect_pending.store(false);
  g_boot_worker = std::thread(reconnect_worker_body);
  printf("reconnect: async started\n");
}

void helper_boot_serial_wait() {
  // 为什么：shutdown 等开口完全结束再动 COM；IPC reconnect 不再走这条
  // 锁外 join，避免与 serial_worker_exit 抢同一把锁死锁
  std::thread to_join;
  {
    std::lock_guard<std::mutex> lock(g_boot_thread_mu);
    if (g_boot_worker.joinable())
      to_join = std::move(g_boot_worker);
  }
  if (to_join.joinable())
    to_join.join();
}

bool helper_boot_serial_busy() { return g_boot_busy.load(); }

void helper_shutdown(bool turn_off_lights) {
  bool expected = false;
  if (!g_shutting_down.compare_exchange_strong(expected, true))
    return;

  printf("helper_shutdown begin (lights=%d)\n", turn_off_lights ? 1 : 0);
  g_awaiting_resume.store(false);

  // 为什么：先拦 CreateProcess，再通知在线 UI 立刻 exit(0)，避免断线后 Flutter
  // 误 Process.start 把 helper 拉活
  ui_shutdown();
  if (ipc_push_ui_quit())
    Sleep(150);

  helper_boot_serial_wait();

  {
    std::lock_guard<std::mutex> lock(g_resume_thread_mu);
    if (g_resume_worker.joinable())
      g_resume_worker.join();
  }

  engine_request_stop();
  // join 发帧 + 拆 DXGI；必须在 power_off 之前，否则 0ms 连写会把灯重新点亮
  engine_stop_and_release_dxgi();

  HANDLE *p = helper_serial();
  if (turn_off_lights && p != nullptr && *p != INVALID_HANDLE_VALUE) {
    power_off(*p);
  }
  if (p != nullptr && *p != INVALID_HANDLE_VALUE) {
    close_com(*p);
    *p = INVALID_HANDLE_VALUE;
  }
  ipc_cancel();
  printf("helper_shutdown done\n");
}
