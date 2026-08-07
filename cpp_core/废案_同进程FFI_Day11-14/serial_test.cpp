#include "../engine/serial_port.h"
#include <atomic>
#include <cstdio>
#include <cstring>
#include <thread>

/// 全局变量，用于控制线程退出
std::atomic<bool> g_running{false};

/// 引擎状态
enum class EngineState { Stopped, Running };

/// 握手
bool handshake(HANDLE h) {
  // 步骤 1：声明 PC 就绪
  if (!send_one_frame(h, "set_pc_available 1\r\n", 20)) {
    printf("handshake step1 send failed\n");
    return false;
  }
  if (!read_response_ok(h, 500)) {
    printf("handshake step1 no ok\n");
    return false;
  }

  // 步骤 2：设置渐变延迟
  if (!send_one_frame(h, "set_usb_dim_time 20\r\n", 21)) {
    printf("handshake step2 send failed\n");
    return false;
  }
  if (!read_response_ok(h, 500)) {
    printf("handshake step2 no ok\n");
    return false;
  }

  // 步骤 3：开启联动
  if (!send_one_frame(h, "set_pc_linkage 1\r\n", 18)) {
    printf("handshake step3 send failed\n");
    return false;
  }
  if (!read_response_ok(h, 500)) {
    printf("handshake step3 no ok\n");
    return false;
  }

  printf("handshake ok\n");
  return true;
}
/// 开机
bool power_on(HANDLE h) {
  if (!send_one_frame(h, "set_power 1\r\n", 13)) {
    printf("power on send failed\n");
    return false;
  }
  if (!read_response_ok(h, 500)) {
    printf("power on no ok\n");
    return false;
  }
  return true;
}
/// 释放联动
bool release_linkage(HANDLE h) {
  if (!send_one_frame(h, "set_pc_linkage 0\r\n", 18)) {
    printf("release linkage send failed\n");
    return false;
  }
  if (!read_response_ok(h, 500)) {
    printf("release linkage no ok\n");
    return false;
  }
  return true;
}

/// 生产者生成帧
void produce_colors(int frame_index, char *out_frame, size_t out_cap) {
  // 协议：FrameID 是 uint16，用 %04x 格式化；超过 0xffff 自然回绕
  const unsigned frame_id = (unsigned)frame_index & 0xFFFFu;

  if (frame_index % 2 != 0) {
    // 红/蓝交替 10 段，Step 全是 2
    snprintf(
        out_frame, out_cap,
        "set_rgb_pc %04x 00 63 ff0000 2 0000ff 2 ff0000 2 0000ff 2 ff0000 2 "
        "0000ff 2 ff0000 2 0000ff 2 ff0000 2 0000ff 2\r\n",
        frame_id);
  } else {
    snprintf(
        out_frame, out_cap,
        "set_rgb_pc %04x 00 63 00ff00 2 ff00ff 2 00ff00 2 ff00ff 2 00ff00 2 "
        "ff00ff 2 00ff00 2 ff00ff 2 00ff00 2 ff00ff 2\r\n",
        frame_id);
  }
}
/// 消费者发送帧到串口
bool consumer_to_serial(HANDLE h, const char *frame, DWORD frame_len) {
  if (!send_one_frame(h, frame, frame_len)) {
    return false;
  }
  Sleep(50); // 等待50ms
  return true;
}

/// 帧循环线程
void frame_loop(HANDLE h) {
  int i = 0;
  while (g_running.load()) {
    char frame_buf[128];
    produce_colors(i, frame_buf, sizeof(frame_buf));
    DWORD frame_len = (DWORD)strlen(frame_buf);
    if (!consumer_to_serial(h, frame_buf, frame_len)) {
      break;
    }
    if (i % 10 == 0) {
      printf("send %d (id=%04x)\n", i, (unsigned)i & 0xFFFFu);
    }
    i++;
  }
}

/// 关闭灯光
bool power_off(HANDLE h) {
  if (!send_one_frame(h, "set_power 0\r\n", 13)) {
    printf("power off send failed\n");
    return false;
  }
  if (!read_response_ok(h, 500)) {
    printf("power off no ok\n");
    return false;
  }
  return true;
}

/// 启动引擎
void start_engine(HANDLE h, std::thread &worker, EngineState &state) {
  if (state == EngineState::Running)
    return;
  if (!power_on(h)) {
    printf("power on failed\n");
    return;
  }
  if (!handshake(h)) {
    printf("handshake failed\n");
    return;
  }
  g_running.store(true);
  worker = std::thread(frame_loop, h);
  state = EngineState::Running;
  printf("engine state: running\n");
}

// 关闭引擎
void stop_engine(HANDLE h, std::thread &worker, EngineState &state) {
  if (state == EngineState::Stopped)
    return;
  g_running.store(false);
  if (worker.joinable()) {
    worker.join();
  }
  if (!power_off(h)) {
    printf("power off failed\n");
    return;
  }
  state = EngineState::Stopped;
  printf("engine state: stopped\n");
}

int main() {
  // 引擎状态

  EngineState state = EngineState::Stopped;

  HANDLE h = nullptr;
  if (!open_com("COM10", &h)) {
    printf("open failed\n");
    return 1;
  }
  printf("open ok\n");

  std::thread worker;
  for (int k = 0; k < 3; k++) {
    start_engine(h, worker, state);
    getchar();
    stop_engine(h, worker, state);
  }

  close_com(h);
  return 0;
}