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

/// 一屏编辑：点选某段后拖框改写；未选中时拖拽不改框。
class ScreenMaskEditLayer extends StatefulWidget {
  const ScreenMaskEditLayer({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onSelect,
    required this.onRectChanged,
  });

  final List<SegmentSample> segments;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<SegmentSample> onRectChanged;

  @override
  State<ScreenMaskEditLayer> createState() => _ScreenMaskEditLayerState();
}

class _ScreenMaskEditLayerState extends State<ScreenMaskEditLayer> {
  Offset? _origin;
  /// 本手势已用于切选，不再进入拖框改写。
  bool _selectOnlyGesture = false;

  Offset _toNorm(Offset local, Size size) {
    return Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  Rect _toPixel(SegmentSample s, Size size) {
    return Rect.fromLTRB(
      s.x0 * size.width,
      s.y0 * size.height,
      s.x1 * size.width,
      s.y1 * size.height,
    );
  }

  /// 重叠时取面积最小，方便点进小框。
  int? _hitTest(Offset local, Size size) {
    int? best;
    var bestArea = double.infinity;
    for (var i = 0; i < widget.segments.length; i++) {
      final r = _toPixel(widget.segments[i], size);
      if (!r.contains(local)) continue;
      final area = r.width * r.height;
      if (area < bestArea) {
        bestArea = area;
        best = i;
      }
    }
    return best;
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
          onTapUp: (d) {
            final hit = _hitTest(d.localPosition, size);
            if (hit != null) widget.onSelect(hit);
          },
          onPanStart: (d) {
            final hit = _hitTest(d.localPosition, size);
            final selected = widget.selectedIndex;
            if (hit != null && hit != selected) {
              widget.onSelect(hit);
              _selectOnlyGesture = true;
              _origin = null;
              return;
            }
            if (selected == null) {
              if (hit != null) widget.onSelect(hit);
              _selectOnlyGesture = true;
              _origin = null;
              return;
            }
            _selectOnlyGesture = false;
            final n = _toNorm(d.localPosition, size);
            _origin = n;
            _emit(n, n);
          },
          onPanUpdate: (d) {
            if (_selectOnlyGesture) return;
            final o = _origin;
            if (o == null || widget.selectedIndex == null) return;
            _emit(o, _toNorm(d.localPosition, size));
          },
          onPanEnd: (_) {
            _origin = null;
            _selectOnlyGesture = false;
          },
          child: CustomPaint(
            size: size,
            painter: _EditPainter(
              segments: widget.segments,
              selectedIndex: widget.selectedIndex,
            ),
          ),
        );
      },
    );
  }
}

class _EditPainter extends CustomPainter {
  _EditPainter({required this.segments, required this.selectedIndex});

  final List<SegmentSample> segments;
  final int? selectedIndex;

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
    final sel = selectedIndex;
    if (sel != null && sel >= 0 && sel < segments.length) {
      maskPath.addRect(_toPixel(segments[sel], size));
    } else {
      for (final s in segments) {
        maskPath.addRect(_toPixel(s, size));
      }
    }
    maskPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(
      maskPath,
      Paint()..color = const Color(0x99000000),
    );

    const idleStroke = Color(0x66FFFFFF);
    const activeStroke = Color(0xFF00B4FF);
    final labelStyle = TextStyle(
      color: activeStroke,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
    );

    for (var i = 0; i < segments.length; i++) {
      final r = _toPixel(segments[i], size);
      final isSel = i == sel;
      canvas.drawRect(
        r,
        Paint()
          ..color = isSel ? activeStroke : idleStroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSel ? 2.5 : 1.5,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: labelStyle.copyWith(
            color: isSel ? activeStroke : const Color(0xCCFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(r.left + 4, r.top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _EditPainter old) =>
      old.selectedIndex != selectedIndex || old.segments != segments;
}
