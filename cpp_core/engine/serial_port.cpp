#include "serial_port.h"
#include <cstdio>
#include <cstring>
#include <mutex>

static std::mutex g_serial_mtx; // 串口互斥锁

// 打开串口，设置串口参数，返回句柄
bool open_com(const char *port_name, HANDLE *out_handle) {
  char path[32];
  snprintf(path, sizeof(path), "\\\\.\\%s", port_name);
  HANDLE h = CreateFileA(path, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                         OPEN_EXISTING, 0, nullptr);
  if (h == INVALID_HANDLE_VALUE) {
    return false;
  }
  DCB dcb{};
  dcb.DCBlength = sizeof(DCB);
  // 获取串口参数
  if (!GetCommState(h, &dcb)) {
    CloseHandle(h);
    return false;
  }
  // 设置串口参数
  dcb.BaudRate = 230400;
  dcb.ByteSize = 8;
  dcb.Parity = NOPARITY;
  dcb.StopBits = ONESTOPBIT;
  dcb.fDtrControl = DTR_CONTROL_ENABLE;
  dcb.fRtsControl = RTS_CONTROL_DISABLE;
  dcb.fOutxCtsFlow = FALSE;
  dcb.fOutxDsrFlow = FALSE;
  dcb.fOutX = FALSE;
  dcb.fInX = FALSE;
  // 写回串口参数
  if (!SetCommState(h, &dcb)) {
    CloseHandle(h);
    return false;
  }

  COMMTIMEOUTS timeouts{};
  // 读：非阻塞轮询（MAXDWORD + 0/0）；握手/关灯用 read_response_ok 自己 Sleep
  timeouts.ReadIntervalTimeout = MAXDWORD;
  timeouts.ReadTotalTimeoutConstant = 0;
  timeouts.ReadTotalTimeoutMultiplier = 0;
  // 为什么：无写超时则设备卡住时 WriteFile 永不返回，握着 g_serial_mtx，join 退不出
  timeouts.WriteTotalTimeoutMultiplier = 0;
  timeouts.WriteTotalTimeoutConstant = 200;
  if (!SetCommTimeouts(h, &timeouts)) {
    CloseHandle(h);
    return false;
  }
  /// 设置串口读事件掩码
  if (!SetCommMask(h, EV_RXCHAR | EV_TXEMPTY | EV_DSR)) {
    CloseHandle(h);
    return false;
  }

  // 清空串口缓冲区
  PurgeComm(h, PURGE_RXCLEAR | PURGE_TXCLEAR);
  *out_handle = h;
  return true;
} // open_com

// 发送一帧数据。节流在锁内：外层再 Sleep 会变成 ≥100ms，且关灯/高亮会 0ms 连写。
bool send_one_frame(HANDLE handle, const char *data, DWORD frame_len) {
  if (data == nullptr || frame_len >= 120)
    return false;
  if (frame_len < 2 || data[frame_len - 2] != '\r' ||
      data[frame_len - 1] != '\n')
    return false;
  std::lock_guard<std::mutex> lock(g_serial_mtx);
  DWORD written = 0;
  BOOL ok = WriteFile(handle, data, frame_len, &written, nullptr);
  if (!ok || written != frame_len) {
    // 为什么：短写会把半帧留在设备缓冲；不清 + 不补 CRLF，下一帧会拼死机
    printf("WriteFile failed: GetLastError=%lu written=%lu/%lu\n",
           (unsigned long)GetLastError(), (unsigned long)written,
           (unsigned long)frame_len);
    PurgeComm(handle, PURGE_TXCLEAR | PURGE_RXCLEAR);
    if (written > 0) {
      DWORD crlf = 0;
      WriteFile(handle, "\r\n", 2, &crlf, nullptr);
    }
    return false;
  }
  Sleep(50);
  return true;
}

bool read_response_ok(HANDLE handle, DWORD timeout_ms) {
  // 为什么：读是轮询+Sleep，若占着写锁，发帧线程会被卡住几百 ms；
  // 握手/关灯路径本就是「先 write 再 read」，同线程不会并发写读交错。
  char buf[256] = {0};
  size_t total_len = 0;
  DWORD start_time = GetTickCount();

  while (GetTickCount() - start_time < timeout_ms) {
    DWORD nread = 0;
    DWORD cap = (DWORD)(sizeof(buf) - 1 - total_len);
    if (cap == 0)
      return false;
    if (!ReadFile(handle, buf + total_len, cap, &nread, nullptr))
      return false;
    if (nread > 0) {
      total_len += nread;
      buf[total_len] = '\0';
      if (strstr(buf, "ok\r\n") != nullptr)
        return true;
    }
    Sleep(1);
  }
  return false;
}

// 关闭串口。与 WriteFile 同锁，避免 close 与短写补 CRLF 交错。
void close_com(HANDLE handle) {
  std::lock_guard<std::mutex> lock(g_serial_mtx);
  if (handle != INVALID_HANDLE_VALUE) {
    CloseHandle(handle);
  }
}
