#include "engine_internal.h"

#include "dxgi_capture.h"
#include "helper_lifecycle.h"
#include "serial_port.h"
#include "wall_comp.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <mutex>

static void reset_seg_states() {
  for (int i = 0; i < 10; ++i) {
    g_seg[i].on = false;
    g_seg[i].off_count = 0;
  }
}

// 为什么：L 用 max(R,G,B)，与 D0「单通道非 0 即可见」一致；不用 Rec.601
// 返回 true → 本帧该段强制真黑（跳过 EMA 输出 / sat）
static bool seg_deadzone_force_black(int i, float r, float g, float b) {
  if (!g_dz_enable.load())
    return false;

  const float L = (std::max)(r, (std::max)(g, b));
  const float ton = (float)g_dz_ton.load();
  const float toff = (float)g_dz_toff.load();
  const int n_off = g_dz_off_frames.load();
  SegState &s = g_seg[i];

  if (!s.on) {
    if (L >= ton) {
      // OFF→ON 跃阶：seed EMA；随后对称 EMA 因 old==new 等价本帧直通
      g_ema_r[i] = r;
      g_ema_g[i] = g;
      g_ema_b[i] = b;
      s.on = true;
      s.off_count = 0;
      return false;
    }
    g_ema_r[i] = g_ema_g[i] = g_ema_b[i] = 0.f;
    s.off_count = 0;
    return true;
  }

  // ON
  if (L <= toff) {
    ++s.off_count;
    if (s.off_count >= n_off) {
      s.on = false;
      s.off_count = 0;
      g_ema_r[i] = g_ema_g[i] = g_ema_b[i] = 0.f;
      return true;
    }
  } else {
    s.off_count = 0;
  }
  return false;
}

// 为什么：float EMA 可能落在 (0,T)；硬件仍灭 → 抬到 ≥T_on，禁止半死区假渐变
static void clamp_half_deadzone(float *r, float *g, float *b) {
  if (!g_dz_enable.load())
    return;
  const float ton = (float)g_dz_ton.load();
  if (ton <= 0.f)
    return;
  const float mx = (std::max)(*r, (std::max)(*g, *b));
  if (mx > 0.f && mx < ton) {
    const float scale = ton / mx;
    *r *= scale;
    *g *= scale;
    *b *= scale;
  }
}

// 为什么：produce = 抓屏采样；AccessLost 交给 frame_loop 拆再建；
// timeout / 其它失败跳过本帧
static DxgiErr produce_colors_map(int frame_index, char *out_frame,
                                  size_t out_cap) {
  unsigned char rgb[10][3] = {};
  bool custom = false;
  SegmentRect rects[kSegmentCount];
  engine_copy_map_snapshot(&custom, rects);
  // 调用：有自定义表则按矩形采；否则顶边默认
  DxgiErr e = dxgi_grab_and_sample(50, rgb, custom ? rects : nullptr);
  if (e != DxgiErr::Ok)
    return e;

  // α 越小越拖影；由 IPC set alpha 写入 g_alpha
  const float alpha = g_alpha.load();
  // 为什么：采样平均易发灰；EMA 后再抬饱和度，避免增益被时间平滑冲掉
  const float sat = g_saturation.load();
  char colors[10][7] = {};

  for (int i = 0; i < 10; ++i) {
    // 为什么：直接用采样字节做 EMA，不再 sscanf 绕 ASCII
    const float r = (float)rgb[i][0];
    const float g = (float)rgb[i][1];
    const float b = (float)rgb[i][2];

    if (seg_deadzone_force_black(i, r, g, b)) {
      snprintf(colors[i], 7, "000000");
      continue;
    }

    if (!g_ema_inited) {
      g_ema_r[i] = r;
      g_ema_g[i] = g;
      g_ema_b[i] = b;
    } else {
      // out = α * new + (1-α) * old
      g_ema_r[i] = alpha * r + (1.f - alpha) * g_ema_r[i];
      g_ema_g[i] = alpha * g + (1.f - alpha) * g_ema_g[i];
      g_ema_b[i] = alpha * b + (1.f - alpha) * g_ema_b[i];
    }

    float or_ = g_ema_r[i];
    float og = g_ema_g[i];
    float ob = g_ema_b[i];
    // Rec.601 亮度守恒：C' = L + s*(C-L)；s=1 恒等
    if (sat != 1.f) {
      const float L = 0.299f * or_ + 0.587f * og + 0.114f * ob;
      or_ = L + sat * (or_ - L);
      og = L + sat * (og - L);
      ob = L + sat * (ob - L);
      if (or_ < 0.f)
        or_ = 0.f;
      else if (or_ > 255.f)
        or_ = 255.f;
      if (og < 0.f)
        og = 0.f;
      else if (og > 255.f)
        og = 255.f;
      if (ob < 0.f)
        ob = 0.f;
      else if (ob > 255.f)
        ob = 255.f;
    }

    wall_comp_apply(&or_, &og, &ob);
    clamp_half_deadzone(&or_, &og, &ob);

    // 字符串只在组帧前出现一次
    snprintf(colors[i], 7, "%02x%02x%02x", (unsigned)(or_ + 0.5f),
             (unsigned)(og + 0.5f), (unsigned)(ob + 0.5f));
  }
  g_ema_inited = true;

  const unsigned frame_id = (unsigned)frame_index & 0xFFFFu;
  snprintf(out_frame, out_cap,
           "set_rgb_pc %04x 00 63 "
           "%s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           frame_id, colors[0], colors[1], colors[2], colors[3], colors[4],
           colors[5], colors[6], colors[7], colors[8], colors[9]);

  // 红线：组完再查长度
  if (strlen(out_frame) >= 120)
    return DxgiErr::AcquireFailed;
  return DxgiErr::Ok;
}

// Python 惯性：out = s*prev + (1-s)*target；s 高更钝（与 map α 极性相反）
static DxgiErr produce_colors_region(int frame_index, char *out_frame,
                                     size_t out_cap) {
  int l, t, w, h;
  {
    std::lock_guard<std::mutex> lock(g_region_bbox_mu);
    l = g_region_l;
    t = g_region_t;
    w = g_region_w;
    h = g_region_h;
  }
  unsigned char rgb[10][3] = {};
  DxgiErr e = dxgi_grab_and_sample_region(50, l, t, w, h, g_region_algo.load(),
                                          g_region_blur.load(),
                                          g_region_dark.load(), rgb);
  if (e != DxgiErr::Ok)
    return e;

  const float smooth = g_region_smooth.load();
  char colors[10][7] = {};

  for (int i = 0; i < 10; ++i) {
    const float r = (float)rgb[i][0];
    const float g = (float)rgb[i][1];
    const float b = (float)rgb[i][2];

    if (seg_deadzone_force_black(i, r, g, b)) {
      snprintf(colors[i], 7, "000000");
      continue;
    }

    if (!g_ema_inited) {
      g_ema_r[i] = r;
      g_ema_g[i] = g;
      g_ema_b[i] = b;
    } else {
      g_ema_r[i] = smooth * g_ema_r[i] + (1.f - smooth) * r;
      g_ema_g[i] = smooth * g_ema_g[i] + (1.f - smooth) * g;
      g_ema_b[i] = smooth * g_ema_b[i] + (1.f - smooth) * b;
    }

    float or_ = g_ema_r[i];
    float og = g_ema_g[i];
    float ob = g_ema_b[i];
    wall_comp_apply(&or_, &og, &ob);
    clamp_half_deadzone(&or_, &og, &ob);

    snprintf(colors[i], 7, "%02x%02x%02x", (unsigned)(or_ + 0.5f),
             (unsigned)(og + 0.5f), (unsigned)(ob + 0.5f));
  }
  g_ema_inited = true;

  const unsigned frame_id = (unsigned)frame_index & 0xFFFFu;
  snprintf(out_frame, out_cap,
           "set_rgb_pc %04x 00 63 "
           "%s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           frame_id, colors[0], colors[1], colors[2], colors[3], colors[4],
           colors[5], colors[6], colors[7], colors[8], colors[9]);

  if (strlen(out_frame) >= 120)
    return DxgiErr::AcquireFailed;
  return DxgiErr::Ok;
}

static DxgiErr produce_colors(int frame_index, char *out_frame,
                              size_t out_cap) {
  if (g_sync_path.load() == SyncPath::Region)
    return produce_colors_region(frame_index, out_frame, out_cap);
  return produce_colors_map(frame_index, out_frame, out_cap);
}

// 为什么：整段 Sleep(2000) 会让 engine_stop 的 join 卡死；50ms 切片才能看见 g_running
static void sleep_while_running(DWORD ms) {
  const DWORD slice = 50;
  const DWORD start = GetTickCount();
  while (g_running.load()) {
    const DWORD elapsed = GetTickCount() - start;
    if (elapsed >= ms)
      break;
    DWORD left = ms - elapsed;
    if (left > slice)
      left = slice;
    Sleep(left);
  }
}

void frame_loop(HANDLE h) {
  int i = 0;
  int recover_fails = 0;
  DWORD last_recover_log = 0;
  while (g_running.load()) {
    char frame_buf[128];
    DxgiErr e = produce_colors(i, frame_buf, sizeof(frame_buf));
    // DuplicateFailed：recover 拆掉后 init 失败，指针已空，须继续试再建
    if (e == DxgiErr::AccessLost || e == DxgiErr::DuplicateFailed) {
      // 为什么：ACCESS_LOST 后死指针仍非空，必须 recover 而非 ensure
      const DWORD now = GetTickCount();
      if (now - last_recover_log >= 2000) {
        printf("frame_loop: DXGI access lost, recovering\n");
        last_recover_log = now;
      }
      if (engine_recover_dxgi()) {
        recover_fails = 0;
        continue;
      }
      ++recover_fails;
      // 首败已立刻试过；之后 200ms 起，连续失败拉长，上限 2s
      DWORD sleep_ms = 200u * (DWORD)recover_fails;
      if (sleep_ms > 2000)
        sleep_ms = 2000;
      sleep_while_running(sleep_ms);
      continue;
    }
    if (e != DxgiErr::Ok) {
      sleep_while_running(10);
      continue;
    }
    // 为什么：produce 可能很慢；写出前再看一次，避免停机后又发一帧把灯点亮
    if (!g_running.load())
      break;
    if (!send_one_frame(h, frame_buf, (DWORD)strlen(frame_buf)))
      break;
    i++;
  }
  g_running.store(false);
}

bool engine_ensure_dxgi() {
  if (dxgi_is_ready())
    return true;
  DxgiErr e = dxgi_init();
  if (e != DxgiErr::Ok) {
    printf("engine_ensure_dxgi failed: %d\n", (int)e);
    return false;
  }
  printf("engine_ensure_dxgi: re-inited\n");
  return true;
}

bool engine_recover_dxgi() {
  // 为什么：ACCESS_LOST 后指针仍非空，ensure 会误判 ready；必须先拆再建
  dxgi_shutdown();
  DxgiErr e = dxgi_init();
  if (e != DxgiErr::Ok) {
    printf("engine_recover_dxgi failed: %d\n", (int)e);
    return false;
  }
  printf("engine_recover_dxgi: ok\n");
  return true;
}

static void engine_start_path(HANDLE h, SyncPath path) {
  std::lock_guard<std::mutex> lock(g_engine_mu);
  // 同路径已在跑：幂等（不新建线程）。关进程中即使同路径也要 join 掉。
  if (g_running.load() && g_sync_path.load() == path &&
      !helper_is_shutting_down())
    return;
  g_running.store(false);
  // 为什么：g_running 已是 false 但 joinable 的残留 worker 仍可能占串口；不能用旗标当 join 条件
  if (g_worker.joinable())
    g_worker.join();
  g_ema_inited = false;
  reset_seg_states();
  if (helper_is_shutting_down())
    return;
  if (!dxgi_is_ready()) {
    DxgiErr e = dxgi_init();
    if (e != DxgiErr::Ok) {
      printf("engine_start_path: dxgi_init failed: %d\n", (int)e);
      return;
    }
  }
  g_sync_path.store(path);
  g_ema_inited = false;
  reset_seg_states();
  g_running.store(true);
  g_worker = std::thread(frame_loop, h);
}

void engine_start(HANDLE h) { engine_start_path(h, SyncPath::Map); }

void engine_start_region(HANDLE h) { engine_start_path(h, SyncPath::Region); }

void engine_request_stop() { g_running.store(false); }

void engine_stop() {
  std::lock_guard<std::mutex> lock(g_engine_mu);
  g_running.store(false);
  if (g_worker.joinable())
    g_worker.join();
  g_ema_inited = false;
  reset_seg_states();
}
