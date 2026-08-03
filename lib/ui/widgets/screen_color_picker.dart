import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/spacing.dart';

/// 全屏蒙版取色（与段映射校准同一套进/退窗逻辑）。
///
/// 确认返回色；取消 / Esc 返回 `null`。
Future<Color?> showScreenColorPicker(BuildContext context) {
  // opaque:true 且页内镂空透明，才能透过 HWND 看到桌面（而非下层路由）
  return Navigator.of(context).push<Color>(
    PageRouteBuilder(
      opaque: true,
      barrierColor: Colors.transparent,
      pageBuilder: (_, _, _) => const _ScreenColorPickerPage(),
    ),
  );
}

/// 光标下桌面像素（屏幕 DC + GetPixel）；失败返回 `null`。
Color? _sampleDesktopAtCursor() {
  final point = calloc<POINT>();
  try {
    if (!GetCursorPos(point).value) return null;
    final hdc = GetDC(null);
    if (hdc.address == 0) return null;
    try {
      final c = GetPixel(hdc, point.ref.x, point.ref.y);
      // CLR_INVALID
      if (c == 0xFFFFFFFF) return null;
      return Color.fromARGB(255, GetRValue(c), GetGValue(c), GetBValue(c));
    } finally {
      ReleaseDC(null, hdc);
    }
  } finally {
    calloc.free(point);
  }
}

String _hexOf(Color c) {
  final r = (c.r * 255.0).round().clamp(0, 255);
  final g = (c.g * 255.0).round().clamp(0, 255);
  final b = (c.b * 255.0).round().clamp(0, 255);
  return '${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';
}

/// 全屏半透明蒙版取色：罩桌面，光标处镂空，点击取样，ESC 取消。
class _ScreenColorPickerPage extends StatefulWidget {
  const _ScreenColorPickerPage();

  @override
  State<_ScreenColorPickerPage> createState() => _ScreenColorPickerPageState();
}

class _ScreenColorPickerPageState extends State<_ScreenColorPickerPage> {
  bool _exiting = false;

  bool _wasFullScreen = false;
  bool _wasAlwaysOnTop = false;
  Rect? _savedBounds;

  final _focusNode = FocusNode();
  Offset? _cursor;
  Color _preview = const Color(0xFF808080);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _enterMaskWindow();
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _enterMaskWindow() async {
    _wasFullScreen = await windowManager.isFullScreen();
    _wasAlwaysOnTop = await windowManager.isAlwaysOnTop();
    _savedBounds = await windowManager.getBounds();
    await windowManager.setAlwaysOnTop(true);
    if (!_wasFullScreen) {
      await windowManager.setFullScreen(true);
    }
    // 为什么：蒙版镂空要透出桌面，窗体背景必须透明
    await windowManager.setBackgroundColor(const Color(0x00000000));
  }

  Future<void> _leaveMaskWindow() async {
    if (!_wasFullScreen) {
      await windowManager.setFullScreen(false);
    }
    await windowManager.setAlwaysOnTop(_wasAlwaysOnTop);
    final bounds = _savedBounds;
    if (bounds != null && !_wasFullScreen) {
      await windowManager.setBounds(bounds);
    }
    await windowManager.setBackgroundColor(const Color(0x00000000));
  }

  Future<void> _popCancel() async {
    if (_exiting) return;
    _exiting = true;
    await _leaveMaskWindow();
    if (mounted) Navigator.of(context).pop();
  }

  void _onHover(Offset local) {
    if (_exiting || !mounted) return;
    // 镂空孔上 GetPixel 在部分系统可用；点击路径会再藏窗复验
    final sampled = _sampleDesktopAtCursor();
    setState(() {
      _cursor = local;
      if (sampled != null) _preview = sampled;
    });
  }

  Future<void> _onDown() async {
    if (_exiting || !mounted) return;
    _exiting = true;
    // 为什么：分层透明窗上 GetPixel 常读到蒙版色；藏窗后再取光标下真色
    await windowManager.hide();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final sampled = _sampleDesktopAtCursor() ?? _preview;
    await _leaveMaskWindow();
    await windowManager.show();
    await windowManager.focus();
    if (mounted) Navigator.of(context).pop(sampled);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popCancel();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _popCancel();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final viewSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerHover: (e) => _onHover(e.localPosition),
                  onPointerMove: (e) => _onHover(e.localPosition),
                  onPointerDown: (_) => _onDown(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        size: viewSize,
                        painter: _EyedropperMaskPainter(cursor: _cursor),
                      ),
                      if (_cursor != null)
                        _PreviewChip(
                          cursor: _cursor!,
                          color: _preview,
                          viewSize: viewSize,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 半透明罩层 + 光标处小孔镂空（透出桌面供 GetPixel）。
class _EyedropperMaskPainter extends CustomPainter {
  _EyedropperMaskPainter({required this.cursor});

  final Offset? cursor;

  static const _hole = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final maskPath = Path()..addRect(full);
    final c = cursor;
    if (c != null) {
      // even-odd：取样孔从蒙版挖空，透出桌面
      maskPath.addRect(
        Rect.fromCenter(center: c, width: _hole, height: _hole),
      );
      maskPath.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(
      maskPath,
      Paint()..color = const Color(0x99000000), // 与校准蒙版同密度
    );

    if (c != null) {
      final hole = Rect.fromCenter(center: c, width: _hole, height: _hole);
      canvas.drawRect(
        hole,
        Paint()
          ..color = const Color(0xFF00B4FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      // 十字准星
      final cross = Paint()
        ..color = Colors.white
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(c.dx - 18, c.dy),
        Offset(c.dx - _hole / 2, c.dy),
        cross,
      );
      canvas.drawLine(
        Offset(c.dx + _hole / 2, c.dy),
        Offset(c.dx + 18, c.dy),
        cross,
      );
      canvas.drawLine(
        Offset(c.dx, c.dy - 18),
        Offset(c.dx, c.dy - _hole / 2),
        cross,
      );
      canvas.drawLine(
        Offset(c.dx, c.dy + _hole / 2),
        Offset(c.dx, c.dy + 18),
        cross,
      );
    } else {
      final tp = TextPainter(
        text: const TextSpan(
          text: '移动鼠标取色 · 点击确认 · Esc 取消',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w500,
            height: 1.4,
            shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.85);
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EyedropperMaskPainter old) =>
      old.cursor != cursor;
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({
    required this.cursor,
    required this.color,
    required this.viewSize,
  });

  final Offset cursor;
  final Color color;
  final Size viewSize;

  @override
  Widget build(BuildContext context) {
    const chipW = 120.0;
    const chipH = 56.0;
    const gap = 20.0;

    var left = cursor.dx + gap;
    var top = cursor.dy + gap;
    if (left + chipW > viewSize.width) {
      left = cursor.dx - gap - chipW;
    }
    if (top + chipH > viewSize.height) {
      top = cursor.dy - gap - chipH;
    }

    return Positioned(
      left: left.clamp(0, viewSize.width - chipW),
      top: top.clamp(0, viewSize.height - chipH),
      child: IgnorePointer(
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(AppSpacing.control),
          color: const Color(0xE6101010),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.control),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: AppSpacing.pageSection,
                  height: AppSpacing.pageSection,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppSpacing.compact),
                    border: Border.all(color: Colors.white38),
                  ),
                ),
                const SizedBox(width: AppSpacing.control),
                Text(
                  _hexOf(color).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
