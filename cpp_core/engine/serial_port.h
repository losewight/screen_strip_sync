#pragma once

#include <windows.h>

bool open_com(const char *port_name, HANDLE *out_handle);
bool send_one_frame(HANDLE handle, const char *data, DWORD frame_len);
void close_com(HANDLE handle);
bool read_response_ok(HANDLE handle, DWORD timeout_ms = 500);