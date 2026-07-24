#include <cstdint>
#include <cstdio>
#include <windows.h>

typedef int32_t (*FuncGetVersion)();
typedef int32_t (*FnOpen)(const char *port_name);
typedef void (*FnClose)();
typedef int32_t (*FnSetColor)(uint8_t r, uint8_t g, uint8_t b);
typedef int32_t (*FnStart)();
typedef void (*FnStop)();

int main() {
  HMODULE dll = LoadLibraryA("zeeray_core.dll");
  if (!dll) {
    printf("LoadLibraryA failed:%lu\n", GetLastError());
    return 1;
  }

  auto get_version = (FuncGetVersion)GetProcAddress(dll, "zeeray_get_version");
  if (!get_version) {
    printf("GetProcAddress failed\n");
    FreeLibrary(dll);
    return 1;
  }
  printf("get_version:%d\n", get_version());

  auto open = (FnOpen)GetProcAddress(dll, "zeeray_open");
  auto close = (FnClose)GetProcAddress(dll, "zeeray_close");
  if (!open || !close) {
    printf("GetProcAddress open/close failed\n");
    FreeLibrary(dll);
    return 1;
  }
  if (!open("COM10")) {
    printf("zeeray_open failed\n");
    FreeLibrary(dll);
    return 1;
  }
  printf("zeeray_open success\n");

  auto start = (FnStart)GetProcAddress(dll, "zeeray_start_engine");
  auto stop = (FnStop)GetProcAddress(dll, "zeeray_stop_engine");
  if (!start || !stop) {
    printf("GetProcAddress start/stop failed\n");
    close();
    FreeLibrary(dll);
    return 1;
  }

  if (!start()) {
    printf("start failed\n");
    close();
    FreeLibrary(dll);
    return 1;
  }
  printf("engine running 3s...\n");
  Sleep(5000);

  stop();
  printf("engine stopped\n");
  Sleep(1000);

  close();
  printf("zeeray_close success\n");

  FreeLibrary(dll);
  return 0;
}