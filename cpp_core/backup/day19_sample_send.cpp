// Day19 备份：sample_ok + send_sampled + 握手后发灯示例。
// 不编入 helper.exe（CMake 未列入）；需要时自行拷回或临时加入工程。
//
// 依赖：本文件内假图缓冲；serial_port.h。
// 下列代码为拆分前 helper_main 中的完整可复用片段，当前无人调用。

#if 0 // 整文件默认不编译；需要本地试跑时改为 1 并自行接进工程

#include "serial_port.h"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

static const int kFakeW = 10;
static const int kFakeH = 2;
static const int kBpp = 4;
static const int kFakeStride = kFakeW * kBpp + 16;
static std::vector<uint8_t> g_fake_bgra(kFakeStride * kFakeH, 0);

static void fill_fake_bgra() {
  for (int i = 0; i < kFakeStride * kFakeH; i++)
    g_fake_bgra[i] = 0x7F;
  for (int y = 0; y < kFakeH; ++y) {
    for (int x = 0; x < kFakeW; ++x) {
      uint8_t *pixel = &g_fake_bgra[y * kFakeStride + x * kBpp];
      if (x % 2 == 0) {
        pixel[0] = 0;
        pixel[1] = 0;
        pixel[2] = 255;
        pixel[3] = 255;
      } else {
        pixel[0] = 255;
        pixel[1] = 0;
        pixel[2] = 0;
        pixel[3] = 255;
      }
    }
  }
}

// 正确 stride：y * kFakeStride + x * 4；BGRA → RRGGBB。
static void sample_ok(char out_hex[][7]) {
  const int y = 0;
  for (int x = 0; x < kFakeW; x++) {
    const uint8_t *pixel = &g_fake_bgra[y * kFakeStride + x * kBpp];
    snprintf(out_hex[x], 7, "%02x%02x%02x", pixel[2], pixel[1], pixel[0]);
  }
}

// 红线：帧长 <120；WriteFile 后 Sleep≥50。
static bool send_sampled(HANDLE h, char colors[][7]) {
  char frame[128];
  snprintf(frame, sizeof(frame),
           "set_rgb_pc %04x 00 63 "
           "%s 2 %s 2 %s 2 %s 2 %s 2 "
           "%s 2 %s 2 %s 2 %s 2 %s 2\r\n",
           1, colors[0], colors[1], colors[2], colors[3], colors[4], colors[5],
           colors[6], colors[7], colors[8], colors[9]);

  DWORD len = (DWORD)strlen(frame);
  if (len >= 120) {
    printf("frame too long: %lu\n", (unsigned long)len);
    return false;
  }
  if (!send_one_frame(h, frame, len))
    return false;
  Sleep(50);
  return true;
}

// 原 main 握手成功后的调用示例（拆分后主路径不再调用）。
static void day19_demo_send_to_strip(HANDLE h) {
  fill_fake_bgra();
  char colors[10][7];
  sample_ok(colors);
  if (!send_sampled(h, colors))
    printf("send_sampled failed\n");
  else
    printf("sent sample_ok to strip\n");
}

#endif
