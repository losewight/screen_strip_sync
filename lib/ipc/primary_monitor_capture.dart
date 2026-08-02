import 'dart:async';
import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// 主显示器一帧静图（与 DXGI EnumOutputs(0) 对齐：主屏）。
///
/// 调用：[capturePrimaryMonitor] → 得到本对象 → UI 用 [image] 显示；
/// 用完后调用 [dispose]。不经过 helper / IPC。
class PrimaryMonitorShot {
  PrimaryMonitorShot({
    required this.width,
    required this.height,
    required this.image,
  });

  final int width;
  final int height;
  final ui.Image image;

  void dispose() => image.dispose();
}

/// BitBlt 抓主屏 → BGRA → [ui.Image]。
///
/// 失败抛 [StateError]（调用方 catch 后提示用户）。
Future<PrimaryMonitorShot> capturePrimaryMonitor() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
    throw StateError('主屏截图仅支持 Windows');
  }

  final width = GetSystemMetrics(SM_CXSCREEN);
  final height = GetSystemMetrics(SM_CYSCREEN);
  if (width <= 0 || height <= 0) {
    throw StateError('无法读取主屏尺寸');
  }

  final hdcScreen = GetDC(null);
  if (hdcScreen.address == 0) {
    throw StateError('GetDC 失败');
  }

  final hdcMem = CreateCompatibleDC(hdcScreen);
  final hbm = CreateCompatibleBitmap(hdcScreen, width, height);
  if (hdcMem.address == 0 || hbm.address == 0) {
    if (hbm.address != 0) DeleteObject(HGDIOBJ(hbm));
    if (hdcMem.address != 0) DeleteDC(hdcMem);
    ReleaseDC(null, hdcScreen);
    throw StateError('CreateCompatibleBitmap/DC 失败');
  }

  final old = SelectObject(hdcMem, HGDIOBJ(hbm));
  final blit = BitBlt(hdcMem, 0, 0, width, height, hdcScreen, 0, 0, SRCCOPY);
  if (!blit.value) {
    SelectObject(hdcMem, old);
    DeleteObject(HGDIOBJ(hbm));
    DeleteDC(hdcMem);
    ReleaseDC(null, hdcScreen);
    throw StateError('BitBlt 失败');
  }

  final bmi = calloc<BITMAPINFO>();
  late final Uint8List pixels;
  try {
    bmi.ref.bmiHeader
      ..biSize = sizeOf<BITMAPINFOHEADER>()
      ..biWidth = width
      ..biHeight =
          -height // 顶向下，便于直接喂给 Flutter
      ..biPlanes = 1
      ..biBitCount = 32
      ..biCompression = BI_RGB;

    final byteCount = width * height * 4;
    final buf = calloc<Uint8>(byteCount);
    try {
      final lines = GetDIBits(
        hdcMem,
        hbm,
        0,
        height,
        buf,
        bmi,
        DIB_RGB_COLORS,
      );
      if (lines == 0) {
        throw StateError('GetDIBits 失败');
      }
      pixels = Uint8List.fromList(buf.asTypedList(byteCount));
    } finally {
      calloc.free(buf);
    }
  } finally {
    calloc.free(bmi);
    SelectObject(hdcMem, old);
    DeleteObject(HGDIOBJ(hbm));
    DeleteDC(hdcMem);
    ReleaseDC(null, hdcScreen);
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  final image = await completer.future;
  return PrimaryMonitorShot(width: width, height: height, image: image);
}
