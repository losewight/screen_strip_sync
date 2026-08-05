#include "engine_internal.h"

#include "serial_port.h"

#include <cstdio>
#include <cstring>
#include <mutex>

static void play_strip_scan(HANDLE h);

bool try_serial_ready(HANDLE *out_h) {
  char name[16];
  {
    std::lock_guard<std::mutex> lock(g_com_mu);
    snprintf(name, sizeof(name), "%s", g_com_name);
  }
  HANDLE h = INVALID_HANDLE_VALUE;
  if (!open_com(name, &h)) {
    printf("open_com %s failed\n", name);
    return false;
  }
  if (!power_on(h) || !handshake(h)) {
    power_off(h);
    close_com(h);
    return false;
  }
  play_strip_scan(h);
  *out_h = h;
  printf("serial ready on %s\n", name);
  return true;
}

bool power_on(HANDLE h) {
  if (!send_one_frame(h, "set_power 1\r\n",
                      (DWORD)(strlen("set_power 1\r\n")))) {
    return false;
  }
  return read_response_ok(h, 500);
}

bool handshake(HANDLE h) {
  if (!send_one_frame(h, "set_pc_available 1\r\n", 20))
    return false;
  if (!read_response_ok(h, 500))
    return false;
  if (!send_one_frame(h, "set_usb_dim_time 45\r\n", 21))
    return false;
  if (!read_response_ok(h, 500))
    return false;
  if (!send_one_frame(h, "set_pc_linkage 1\r\n", 18))
    return false;
  return read_response_ok(h, 500);
}

// 握手后自检：00FFFF 以 2 段为步幅从头到尾依次亮起（已亮保持）
static bool send_seq_frame(HANDLE h, int frame_id, int lit_through) {
  char colors[10][7];
  for (int seg = 0; seg < 10; ++seg) {
    const char *color = (seg <= lit_through) ? "00ffff" : "000000";
    snprintf(colors[seg], 7, "%s", color);
  }

  char frame[128];
  const int n = snprintf(frame, sizeof(frame),
                         "set_rgb_pc %04x 00 63 "
                         "%s 2 %s 2 %s 2 %s 2 %s 2 "
                         "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
                         frame_id & 0xFFFF, colors[0], colors[1], colors[2],
                         colors[3], colors[4], colors[5], colors[6], colors[7],
                         colors[8], colors[9]);
  if (n < 0 || (size_t)n >= sizeof(frame))
    return false;

  const DWORD len = (DWORD)strlen(frame);
  if (len >= 120)
    return false;
  if (!send_one_frame(h, frame, len))
    return false;
  Sleep(300); // 自检动画用 300ms 间隔（仍 ≥50ms 红线）
  return true;
}

static void play_strip_scan(HANDLE h) {
  int frame_id = 1;

  // lit_through：当前已亮到的段下标（含），每步 +2
  for (int lit_through = 1; lit_through < 10; lit_through += 2) {
    if (!send_seq_frame(h, frame_id++, lit_through)) {
      printf("strip seq light failed at segment %d\n", lit_through);
      return;
    }
  }
  printf("strip seq light ok\n");
}

bool power_off(HANDLE h) {
  if (!send_one_frame(h, "set_power 0\r\n",
                      (DWORD)(strlen("set_power 0\r\n")))) {
    return false;
  }
  return read_response_ok(h, 500);
}

bool send_solid(HANDLE h, const char *rrggbb) {
  char frame[128];
  snprintf(frame, sizeof(frame),
           "set_rgb_pc %04x 00 63 %s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           1, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb, rrggbb,
           rrggbb, rrggbb);

  DWORD len = (DWORD)strlen(frame);
  if (len >= 120) { // 红线：拒绝 >=120
    printf("frame too long: %lu\n", (unsigned long)len);
    return false;
  }
  if (!send_one_frame(h, frame, len))
    return false;
  Sleep(50); // 红线：帧间隔 ≥50ms
  return true;
}

bool send_highlight(HANDLE h, int seg) {
  if (seg < 0 || seg >= kSegmentCount)
    return false;
  const char *colors[kSegmentCount];
  for (int i = 0; i < kSegmentCount; ++i)
    colors[i] = (i == seg) ? "ffffff" : "000000";

  char frame[128];
  snprintf(frame, sizeof(frame),
           "set_rgb_pc %04x 00 63 "
           "%s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           1, colors[0], colors[1], colors[2], colors[3], colors[4], colors[5],
           colors[6], colors[7], colors[8], colors[9]);

  DWORD len = (DWORD)strlen(frame);
  if (len >= 120) {
    printf("highlight frame too long: %lu\n", (unsigned long)len);
    return false;
  }
  if (!send_one_frame(h, frame, len))
    return false;
  Sleep(50);
  return true;
}
