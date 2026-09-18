import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../state/helper_ui_state.dart';

/// window_manager 的 setBounds 会把逻辑值乘 devicePixelRatio
/// （windows/window_manager.cpp），所以这里先用同一个 DPR 把 helper
/// 给的物理矩形除回逻辑值——同值往返，跨不同 DPI 的屏也不会错。
Rect physicalDesktopToLogicalBounds(Rect physical, double dpr) {
  final scale = dpr <= 0 ? 1.0 : dpr;
  return Rect.fromLTWH(
    physical.left / scale,
    physical.top / scale,
    physical.width / scale,
    physical.height / scale,
  );
}

/// helper 上报的当前抓屏桌面矩形（虚拟桌面物理像素）；拿不到返回 null。
Rect? captureDesktopPhysicalRect(
  CaptureOutputInfo? current,
  List<CaptureOutputInfo> outputs,
) {
  CaptureOutputInfo? src = current;
  if (src == null || src.width <= 0 || src.height <= 0) {
    for (final o in outputs) {
      if (o.isCurrent && o.width > 0 && o.height > 0) {
        src = o;
        break;
      }
    }
  }
  if (src == null || src.width <= 0 || src.height <= 0) return null;
  return Rect.fromLTWH(
    src.left.toDouble(),
    src.top.toDouble(),
    src.width.toDouble(),
    src.height.toDouble(),
  );
}

class MaskWindowRestore {
  const MaskWindowRestore({
    required this.wasAlwaysOnTop,
    this.bounds,
  });

  final bool wasAlwaysOnTop;
  final Rect? bounds;
}

class MaskWindowEnterResult {
  const MaskWindowEnterResult({
    required this.restore,
    required this.aligned,
  });

  final MaskWindowRestore restore;
  final bool aligned;
}

/// 先把窗口挪到被抓的那块屏，再全屏。
/// setFullScreen 内部按 MonitorFromWindow 取 rcMonitor，
/// 因此必须先 setBounds，否则仍然铺在原来那块屏上。
/// 没有矩形时不挪窗（沿用今天行为），[aligned] 为 false。
Future<MaskWindowEnterResult> enterCaptureMaskWindow({
  required Rect? physicalDesktop,
  required double dpr,
}) async {
  final restore = MaskWindowRestore(
    wasAlwaysOnTop: await windowManager.isAlwaysOnTop(),
    bounds: await windowManager.getBounds(),
  );
  await windowManager.setAlwaysOnTop(true);
  var aligned = false;
  if (physicalDesktop != null &&
      physicalDesktop.width > 0 &&
      physicalDesktop.height > 0) {
    await windowManager.setBounds(
      physicalDesktopToLogicalBounds(physicalDesktop, dpr),
    );
    aligned = true;
  }
  await windowManager.setFullScreen(true);
  await windowManager.setBackgroundColor(const Color(0x00000000));
  return MaskWindowEnterResult(restore: restore, aligned: aligned);
}

/// 退出全屏后无条件恢复进入前的位置与尺寸。
/// 为什么：先进 setBounds 再全屏后，即使进来时本就全屏，窗口也可能已经在另一块屏。
Future<void> leaveCaptureMaskWindow(MaskWindowRestore restore) async {
  await windowManager.setFullScreen(false);
  await windowManager.setAlwaysOnTop(restore.wasAlwaysOnTop);
  final bounds = restore.bounds;
  if (bounds != null) {
    await windowManager.setBounds(bounds);
  }
  await windowManager.setBackgroundColor(const Color(0x00000000));
}
