#include <cstdint>
#include <cstdio>
#include <windows.h>

typedef int32_t (*FuncGetVersion)();
typedef int32_t (*FnOpen)(const char *port_name);
typedef void (*FnClose)();
typedef int32_t (*FnSetColor)(uint8_t r, uint8_t g, uint8_t b);

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

  auto set_color = (FnSetColor)GetProcAddress(dll, "zeeray_set_color");
  if (!set_color) {
    printf("GetProcAddress set_color failed\n");
    close();
    FreeLibrary(dll);
    return 1;
  }
  if (!set_color(255, 0, 0)) {
    printf("zeeray_set_color failed\n");
    close();
    FreeLibrary(dll);
    return 1;
  }
  printf("zeeray_set_color success\n");
  Sleep(1000);

  close();
  printf("zeeray_close success\n");

  FreeLibrary(dll);
  return 0;
}