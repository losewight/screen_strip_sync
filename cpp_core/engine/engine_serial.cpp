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
  printf("serial ready on %s (strip: %dm, step: %d)\n", name,
         engine_get_device_step(), engine_get_device_step());
  return true;
}

bool power_on(HANDLE h) {
  if (!send_one_frame(h, "set_power 1\r\n",
                      (DWORD)(strlen("set_power 1\r\n")))) {
    return false;
  }
  return read_response_ok(h, 500);
}

static void detect_strip_length(HANDLE h) {
  static const char kQuery[] = "get_length\r\n";
  if (!send_one_frame(h, kQuery, (DWORD)strlen(kQuery))) {
    printf("get_length send failed, default to 2m (step=2)\n");
    engine_set_device_step(2);
    return;
  }

  char buf[128] = {0};
  size_t n = read_response_text(h, buf, sizeof(buf), 500, "\n");
  if (n == 0) {
    printf("get_length read timeout, default to 2m (step=2)\n");
    engine_set_device_step(2);
    return;
  }

  int len = parse_strip_length(buf);
  if (is_valid_strip_length(len)) {
    engine_set_device_step(len);
    printf("strip length detected: %dm (%d LEDs, step=%d)\n", len, len * 10,
           len);
  } else {
    engine_set_device_step(2);
    printf("strip length unconfirmed (rx: '%s'), default to 2m (step=2)\n",
           buf);
  }
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
  if (!read_response_ok(h, 500))
    return false;
  detect_strip_length(h);
  return true;
}

// 握手后自检：00FFFF 以 2 段为步幅从头到尾依次亮起（已亮保持）
static bool send_seq_frame(HANDLE h, int frame_id, int lit_through) {
  char colors[10][7];
  for (int seg = 0; seg < 10; ++seg) {
    const char *color = (seg <= lit_through) ? "00ffff" : "000000";
    snprintf(colors[seg], 7, "%s", color);
  }

  char frame[128];
  if (!build_rgb_pc_frame((unsigned)frame_id, 0x63, colors, 0, frame, sizeof(frame)))
    return false;

  const DWORD len = (DWORD)strlen(frame);
  if (!send_one_frame(h, frame, len))
    return false;

  // 接受性探针：首帧若被固件拒绝，会返回 err seg n
  if (frame_id == 1) {
    char probe_buf[64] = {0};
    if (read_response_text(h, probe_buf, sizeof(probe_buf), 50, "\r\n") > 0) {
      if (strstr(probe_buf, "err seg") != nullptr) {
        printf("WARNING: strip firmware rejected set_rgb_pc frame! rx: %s\n",
               probe_buf);
      }
    }
  }

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
  if (!build_rgb_pc_solid_frame(1, 0x63, color, 0, frame, sizeof(frame)))
    return false;

  const DWORD len = (DWORD)strlen(frame);
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
  if (!build_rgb_pc_frame(1, 0x63, colors, 0, frame, sizeof(frame)))
    return false;

  const DWORD len = (DWORD)strlen(frame);
  if (!send_one_frame(h, frame, len))
    return false;
  return true;
}
