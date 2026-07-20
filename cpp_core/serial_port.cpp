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

  // 设置串口数据读取超时时间
  COMMTIMEOUTS timeouts{};
  timeouts.ReadIntervalTimeout = MAXDWORD;
  timeouts.ReadTotalTimeoutConstant = 0;
  timeouts.ReadTotalTimeoutMultiplier = 0;
  /// 设置串口数据写入超时时间
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

// 发送一帧数据
bool send_one_frame(HANDLE handle, const char *data, DWORD frame_len) {
  if (frame_len >= 120) {
    return false;
  }
  std::lock_guard<std::mutex> lock(g_serial_mtx); // 加锁,作用域结束时自动解锁
  DWORD written = 0;
  BOOL ok = WriteFile(handle, data, frame_len, &written, nullptr);
  return ok && (written == frame_len);
}

bool read_response_ok(HANDLE handle, DWORD timeout_ms) {
  std::lock_guard<std::mutex> lock(g_serial_mtx);
  char buf[256] = {0};
  size_t total_len = 0;
  DWORD start_time = GetTickCount();

  while (GetTickCount() - start_time < timeout_ms) {
    DWORD nread = 0;
    DWORD cap = (DWORD)sizeof(buf) - total_len;
    if (cap == 0) {
      return false;
    }
    if (!ReadFile(handle, buf + total_len, cap, &nread, nullptr)) {
      return false;
    }
    if (nread > 0) {
      total_len += nread;
      buf[total_len] = '\0';
      if (strstr(buf, "ok\r\n") != nullptr) {
        return true;
      }
    }
    Sleep(1);
  }
  return false;
}

// 关闭串口
void close_com(HANDLE handle) {
  if (handle != INVALID_HANDLE_VALUE) {
    CloseHandle(handle);
  }
}
