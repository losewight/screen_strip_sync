#include "autostart.h"

#include <cstdio>
#include <cstring>

#include <windows.h>

static constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
static constexpr wchar_t kValueName[] = L"ScreenStripSyncHelper";

// 拼出期望的 Run 值：`"C:\path\helper.exe" --autostart`
static bool build_run_value(wchar_t *out, size_t out_cap) {
  wchar_t exe[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, exe, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) {
    printf("autostart: GetModuleFileName failed\n");
    return false;
  }
  // 为什么：路径可能含空格，必须加引号，否则 Run 会把参数拆坏
  if (swprintf_s(out, out_cap, L"\"%s\" --autostart", exe) <= 0) {
    printf("autostart: build_run_value overflow\n");
    return false;
  }
  return true;
}

static bool write_run_value(const wchar_t *value) {
  HKEY key = nullptr;
  LONG err = RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key);
  if (err != ERROR_SUCCESS) {
    printf("autostart: RegOpenKeyEx write failed %ld\n", err);
    return false;
  }
  DWORD bytes = static_cast<DWORD>((wcslen(value) + 1) * sizeof(wchar_t));
  err = RegSetValueExW(key, kValueName, 0, REG_SZ,
                       reinterpret_cast<const BYTE *>(value), bytes);
  RegCloseKey(key);
  if (err != ERROR_SUCCESS) {
    printf("autostart: RegSetValueEx failed %ld\n", err);
    return false;
  }
  return true;
}

static bool delete_run_value() {
  HKEY key = nullptr;
  LONG err = RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key);
  if (err != ERROR_SUCCESS) {
    printf("autostart: RegOpenKeyEx delete failed %ld\n", err);
    return false;
  }
  err = RegDeleteValueW(key, kValueName);
  RegCloseKey(key);
  // 值本来就不存在也算成功（清孤儿幂等）
  if (err != ERROR_SUCCESS && err != ERROR_FILE_NOT_FOUND) {
    printf("autostart: RegDeleteValue failed %ld\n", err);
    return false;
  }
  return true;
}

// 读出现有值；不存在返回 false，out 清空
static bool read_run_value(wchar_t *out, size_t out_cap) {
  if (out_cap == 0)
    return false;
  out[0] = L'\0';
  HKEY key = nullptr;
  LONG err =
      RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_QUERY_VALUE, &key);
  if (err != ERROR_SUCCESS)
    return false;
  DWORD type = 0;
  DWORD bytes = static_cast<DWORD>(out_cap * sizeof(wchar_t));
  err = RegQueryValueExW(key, kValueName, nullptr, &type,
                         reinterpret_cast<BYTE *>(out), &bytes);
  RegCloseKey(key);
  if (err != ERROR_SUCCESS || type != REG_SZ) {
    out[0] = L'\0';
    return false;
  }
  // RegQueryValueEx 不保证 NUL 结尾时，手动收口
  size_t chars = bytes / sizeof(wchar_t);
  if (chars >= out_cap)
    chars = out_cap - 1;
  out[chars] = L'\0';
  return true;
}

bool autostart_apply(bool enabled) {
  if (!enabled) {
    bool ok = delete_run_value();
    printf("autostart: apply off -> %s\n", ok ? "ok" : "fail");
    return ok;
  }
  wchar_t value[MAX_PATH + 32];
  if (!build_run_value(value, sizeof(value) / sizeof(value[0])))
    return false;
  bool ok = write_run_value(value);
  printf("autostart: apply on -> %s\n", ok ? "ok" : "fail");
  return ok;
}

bool autostart_reconcile(bool enabled_from_json) {
  if (!enabled_from_json) {
    // JSON 关：清掉本值名（哪怕用户手改过路径）
    bool ok = delete_run_value();
    printf("autostart: reconcile off -> %s\n", ok ? "ok" : "fail");
    return ok;
  }

  wchar_t expected[MAX_PATH + 32];
  if (!build_run_value(expected, sizeof(expected) / sizeof(expected[0])))
    return false;

  wchar_t current[MAX_PATH + 32];
  bool has = read_run_value(current, sizeof(current) / sizeof(current[0]));
  if (has && _wcsicmp(current, expected) == 0) {
    printf("autostart: reconcile already ok\n");
    return true;
  }

  // 缺键或路径漂移 → 重写
  bool ok = write_run_value(expected);
  printf("autostart: reconcile rewrite -> %s (had=%d)\n", ok ? "ok" : "fail",
         has ? 1 : 0);
  return ok;
}
