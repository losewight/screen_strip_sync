#include "fake_bgra.h"

#include <cstdint>
#include <cstdio>
#include <vector>

// 假 BGRA：stride > W*4，模拟显存行对齐里的 padding。
static const int kFakeW = 10;
static const int kFakeH = 2;
static const int kBpp = 4;
static const int kFakeStride = kFakeW * kBpp + 16;

static std::vector<uint8_t> g_fake_bgra(kFakeStride *kFakeH, 0);

void fill_fake_bgra() {
  for (int i = 0; i < kFakeStride * kFakeH; i++) {
    g_fake_bgra[i] = 0x7F;
  }

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

// 仅给 print_fake_stride_demo 用；发灯版在 backup/day19_sample_send.cpp。
static void sample_ok_for_print(char out_hex[][7]) {
  const int y = 0;
  for (int x = 0; x < kFakeW; x++) {
    const uint8_t *pixel = &g_fake_bgra[y * kFakeStride + x * kBpp];
    snprintf(out_hex[x], 7, "%02x%02x%02x", pixel[2], pixel[1], pixel[0]);
  }
}

void sample_wrong(char out_hex[][7]) {
  const int y = 1;
  const int bad_stride = kFakeW * kBpp;
  for (int x = 0; x < kFakeW; x++) {
    const uint8_t *pixel = &g_fake_bgra[y * bad_stride + x * kBpp];
    snprintf(out_hex[x], 7, "%02x%02x%02x", pixel[2], pixel[1], pixel[0]);
  }
}

void print_fake_stride_demo() {
  fill_fake_bgra();
  printf("fake filled: W=%d stride=%d\n", kFakeW, kFakeStride);

  char ok[10][7], bad[10][7];
  sample_ok_for_print(ok);
  sample_wrong(bad);
  printf("ok:   ");
  for (int i = 0; i < kFakeW; i++)
    printf("%s ", ok[i]);
  printf("\n");
  printf("wrong:");
  for (int i = 0; i < kFakeW; i++)
    printf("%s ", bad[i]);
  printf("\n");
}
