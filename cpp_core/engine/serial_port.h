#pragma once

#include <cstddef>
#include <windows.h>

bool open_com(const char *port_name, HANDLE *out_handle);
bool send_one_frame(HANDLE handle, const char *data, DWORD frame_len);
void close_com(HANDLE handle);
size_t read_response_text(HANDLE handle, char *out_buf, size_t out_cap,
                          DWORD timeout_ms, const char *find_str = nullptr);
bool read_response_ok(HANDLE handle, DWORD timeout_ms = 500);
