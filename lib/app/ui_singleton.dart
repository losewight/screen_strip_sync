import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 进程存活期间持有，勿 CloseHandle（与 helper 的 `ScreenStripSyncHelper` 对称）。
/// 赋值即引用，防止 GC/分析器认为可丢弃。
// ignore: unused_element
HANDLE? _uiSingletonMutex;

final _createMutexW = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Pointer Function(Pointer<SECURITY_ATTRIBUTES>, Int32, Pointer<Utf16>),
      Pointer Function(Pointer<SECURITY_ATTRIBUTES>, int, Pointer<Utf16>)
    >('CreateMutexW');

/// 尝试占有 UI 单实例互斥 `Local\ScreenStripSyncUi`。
///
/// 返回 `false` 表示已有界面进程，调用方应立刻 `exit(0)`。
bool tryAcquireUiSingleton() {
  if (!Platform.isWindows) return true;

  final name = r'Local\ScreenStripSyncUi'.toNativeUtf16();
  try {
    final handle = HANDLE(_createMutexW(nullptr, TRUE, name));
    if (handle.address == 0) return false;

    // 为什么：第二实例仍拿到句柄，必须靠 GetLastError 区分
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
      CloseHandle(handle);
      return false;
    }

    _uiSingletonMutex = handle;
    return true;
  } finally {
    free(name);
  }
}
