#include "app_paths.h"

#include <cstdio>
#include <cstring>

#include <ShlObj.h>
#include <windows.h>

static constexpr wchar_t kDataFolder[] = L"Screen Strip Sync";
static constexpr char kConfigName[] = "screen_strip_sync_config.json";
static constexpr char kHelperLogName[] = "helper.log";
static constexpr char kCrashLogName[] = "screen_strip_sync_crash.log";

static bool wide_to_utf8(const wchar_t *wide, char *out, size_t cap) {
  if (!wide || !out || cap == 0)
    return false;
  const int n = WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, (int)cap,
                                    nullptr, nullptr);
  return n > 0 && (size_t)n <= cap;
}

static bool copy_file_if_missing(const wchar_t *src, const wchar_t *dst) {
  if (GetFileAttributesW(dst) != INVALID_FILE_ATTRIBUTES)
    return true;
  if (GetFileAttributesW(src) == INVALID_FILE_ATTRIBUTES)
    return false;
  return CopyFileW(src, dst, TRUE) != 0;
}

bool data_dir_wide(wchar_t *out, size_t cap) {
  if (!out || cap < 16)
    return false;

  PWSTR base = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base)) ||
      base == nullptr) {
    return false;
  }

  const int need = swprintf_s(out, cap, L"%s\\%s", base, kDataFolder);
  CoTaskMemFree(base);
  if (need <= 0)
    return false;

  if (!CreateDirectoryW(out, nullptr)) {
    const DWORD err = GetLastError();
    if (err != ERROR_ALREADY_EXISTS)
      return false;
  }
  return true;
}

bool data_dir_utf8(char *out, size_t cap) {
  wchar_t wide[MAX_PATH];
  if (!data_dir_wide(wide, MAX_PATH))
    return false;
  return wide_to_utf8(wide, out, cap);
}

static bool join_data_file(const char *name, char *out, size_t cap) {
  char dir[MAX_PATH];
  if (!data_dir_utf8(dir, sizeof(dir)))
    return false;
  if (snprintf(out, cap, "%s\\%s", dir, name) <= 0)
    return false;
  return true;
}

bool helper_log_path(char *out, size_t cap) {
  return join_data_file(kHelperLogName, out, cap);
}

bool config_file_path(char *out, size_t cap) {
  return join_data_file(kConfigName, out, cap);
}

void data_dir_migrate_from_exe_dir() {
  wchar_t exe[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, exe, MAX_PATH);
  if (n == 0 || n >= MAX_PATH)
    return;

  wchar_t *slash = wcsrchr(exe, L'\\');
  if (!slash)
    return;
  *(slash + 1) = L'\0';

  wchar_t data[MAX_PATH];
  if (!data_dir_wide(data, MAX_PATH))
    return;

  static const wchar_t *kNames[] = {
      L"screen_strip_sync_config.json",
      L"helper.log",
      L"screen_strip_sync_crash.log",
  };

  for (const wchar_t *name : kNames) {
    wchar_t src[MAX_PATH];
    wchar_t dst[MAX_PATH];
    if (swprintf_s(src, MAX_PATH, L"%s%ls", exe, name) <= 0)
      continue;
    if (swprintf_s(dst, MAX_PATH, L"%s\\%ls", data, name) <= 0)
      continue;
    if (copy_file_if_missing(src, dst)) {
      char src_u[MAX_PATH];
      char dst_u[MAX_PATH];
      if (wide_to_utf8(src, src_u, sizeof(src_u)) &&
          wide_to_utf8(dst, dst_u, sizeof(dst_u))) {
        printf("data_dir: migrate %s -> %s\n", src_u, dst_u);
      }
    }
  }
}
