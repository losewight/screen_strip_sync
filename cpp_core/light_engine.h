#pragma once

#include <windows.h>

bool power_on(HANDLE h);
bool handshake(HANDLE h);
bool power_off(HANDLE h);
bool send_solid(HANDLE h, const char *rrggbb);
void engine_start(HANDLE h);
void engine_stop();
