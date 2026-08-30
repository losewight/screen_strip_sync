#include "engine_internal.h"

#include "serial_port.h"
#include "wall_comp.h"

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
  static const char kAvail[] = "set_pc_available 1\r\n";
  static const char kDim[] = "set_usb_dim_time 45\r\n";
  static const char kLink[] = "set_pc_linkage 1\r\n";
  // 为什么：字面量改长度时魔法 20/21/18 会 silently 截断或越读
  if (!send_one_frame(h, kAvail, (DWORD)strlen(kAvail)))
    return false;
  if (!read_response_ok(h, 500))
    return false;
  if (!send_one_frame(h, kDim, (DWORD)strlen(kDim)))
    return false;
  if (!read_response_ok(h, 500))
    return false;
  if (!send_one_frame(h, kLink, (DWORD)strlen(kLink)))
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
  if (!rrggbb || strlen(rrggbb) != 6)
    return false;

  float r = 0.f, g = 0.f, b = 0.f;
  for (int c = 0; c < 3; ++c) {
    unsigned v = 0;
    for (int k = 0; k < 2; ++k) {
      char ch = rrggbb[c * 2 + k];
      unsigned d = 0;
      if (ch >= '0' && ch <= '9')
        d = (unsigned)(ch - '0');
      else if (ch >= 'a' && ch <= 'f')
        d = (unsigned)(ch - 'a' + 10);
      else if (ch >= 'A' && ch <= 'F')
        d = (unsigned)(ch - 'A' + 10);
      else
        return false;
      v = (v << 4) | d;
    }
    if (c == 0)
      r = (float)v;
    else if (c == 1)
      g = (float)v;
    else
      b = (float)v;
  }
  wall_comp_apply(&r, &g, &b);
  char color[7];
  snprintf(color, sizeof(color), "%02x%02x%02x", (unsigned)(r + 0.5f),
           (unsigned)(g + 0.5f), (unsigned)(b + 0.5f));

  char frame[128];
  snprintf(frame, sizeof(frame),
           "set_rgb_pc %04x 00 63 %s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           1, color, color, color, color, color, color, color, color, color,
           color);

  DWORD len = (DWORD)strlen(frame);
  if (len >= 120) { // 红线：拒绝 >=120
    printf("frame too long: %lu\n", (unsigned long)len);
    return false;
  }
  if (!send_one_frame(h, frame, len))
    return false;
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
  return true;
}
