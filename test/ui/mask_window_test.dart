import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_strip_sync/state/helper_ui_state.dart';
import 'package:screen_strip_sync/ui/widgets/mask_window.dart';

void main() {
  group('physicalDesktopToLogicalBounds', () {
    test('divides physical pixels by the same DPR setBounds will multiply', () {
      const physical = Rect.fromLTWH(2560, 0, 1920, 1080);
      final logical = physicalDesktopToLogicalBounds(physical, 1.25);
      expect(logical.left, closeTo(2048, 0.01));
      expect(logical.top, 0);
      expect(logical.width, closeTo(1536, 0.01));
      expect(logical.height, closeTo(864, 0.01));
    });

    test('treats non-positive dpr as 1', () {
      const physical = Rect.fromLTWH(100, 50, 200, 100);
      expect(physicalDesktopToLogicalBounds(physical, 0), physical);
      expect(physicalDesktopToLogicalBounds(physical, -2), physical);
    });
  });

  group('captureDesktopPhysicalRect', () {
    test('prefers currentCapture then isCurrent in the list', () {
      const current = CaptureOutputInfo(
        name: r'\\.\DISPLAY1',
        width: 2560,
        height: 1440,
        left: 0,
        top: 0,
        isCurrent: true,
      );
      const other = CaptureOutputInfo(
        name: r'\\.\DISPLAY2',
        width: 1920,
        height: 1080,
        left: 2560,
        top: 0,
        isCurrent: true,
      );
      expect(
        captureDesktopPhysicalRect(current, [other]),
        const Rect.fromLTWH(0, 0, 2560, 1440),
      );
      expect(
        captureDesktopPhysicalRect(null, [other]),
        const Rect.fromLTWH(2560, 0, 1920, 1080),
      );
      expect(captureDesktopPhysicalRect(null, const []), isNull);
    });
  });
}
