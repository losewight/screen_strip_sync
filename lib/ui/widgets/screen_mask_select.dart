import 'package:flutter/material.dart';

import '../../config/segment_map_codec.dart';
import '../../config/segment_sample.dart';

/// 全屏蒙版上拖框：半透明罩层 + 选区镂空，输出归一化 [SegmentSample]。
///
/// 整窗须透明背景，镂空处才能透出桌面。
class ScreenMaskSelectLayer extends StatefulWidget {
  const ScreenMaskSelectLayer({
    super.key,
    required this.committed,
    required this.currentIndex,
    required this.currentRect,
    required this.onRectChanged,
  });

  final List<SegmentSample?> committed;
  final int currentIndex;
  final SegmentSample? currentRect;
  final ValueChanged<SegmentSample> onRectChanged;

  @override
  State<ScreenMaskSelectLayer> createState() => _ScreenMaskSelectLayerState();
}

class _ScreenMaskSelectLayerState extends State<ScreenMaskSelectLayer> {
  Offset? _origin;

  Offset _toNorm(Offset local, Size size) {
    return Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  void _emit(Offset a, Offset b) {
    widget.onRectChanged(
      SegmentMapCodec.rectFromDisplayDrag(
        ax: a.dx,
        ay: a.dy,
        bx: b.dx,
        by: b.dy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            final n = _toNorm(d.localPosition, size);
            _origin = n;
            _emit(n, n);
          },
          onPanUpdate: (d) {
            final o = _origin;
            if (o == null) return;
            _emit(o, _toNorm(d.localPosition, size));
          },
          onPanEnd: (_) => _origin = null,
          child: CustomPaint(
            size: size,
            painter: _MaskPainter(
              committed: widget.committed,
              currentIndex: widget.currentIndex,
              currentRect: widget.currentRect,
            ),
          ),
        );
      },
    );
  }
}

class _MaskPainter extends CustomPainter {
  _MaskPainter({
    required this.committed,
    required this.currentIndex,
    required this.currentRect,
  });

  final List<SegmentSample?> committed;
  final int currentIndex;
  final SegmentSample? currentRect;

  Rect _toPixel(SegmentSample s, Size size) {
    return Rect.fromLTRB(
      s.x0 * size.width,
      s.y0 * size.height,
      s.x1 * size.width,
      s.y1 * size.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final maskPath = Path()..addRect(full);
    final cur = currentRect;
    if (cur != null) {
      // even-odd：选区从蒙版中挖空，透出桌面
      maskPath.addRect(_toPixel(cur, size));
      maskPath.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(
      maskPath,
      Paint()..color = const Color(0x99000000), // 60% 黑
    );

    for (var i = 0; i < committed.length; i++) {
      final s = committed[i];
      if (s == null || i == currentIndex) continue;
      final r = _toPixel(s, size);
      canvas.drawRect(
        r,
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    if (cur != null) {
      final r = _toPixel(cur, size);
      canvas.drawRect(
        r,
        Paint()
          ..color = const Color(0xFF00B4FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MaskPainter old) =>
      old.currentIndex != currentIndex ||
      old.currentRect != currentRect ||
      old.committed != committed;
}
