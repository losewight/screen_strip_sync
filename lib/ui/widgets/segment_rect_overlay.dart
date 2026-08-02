import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../config/segment_map_codec.dart';
import '../../config/segment_sample.dart';

/// 截图上拖框：输出相对图像的归一化矩形（整图可框）。
///
/// 调用：[onRectChanged] 在拖动/松手时回调；[committed] 为已确认段淡框。
class SegmentRectOverlay extends StatefulWidget {
  const SegmentRectOverlay({
    super.key,
    required this.image,
    required this.committed,
    required this.currentIndex,
    required this.currentRect,
    required this.onRectChanged,
  });

  final ui.Image image;
  final List<SegmentSample?> committed;
  final int currentIndex;
  final SegmentSample? currentRect;
  final ValueChanged<SegmentSample> onRectChanged;

  @override
  State<SegmentRectOverlay> createState() => _SegmentRectOverlayState();
}

class _SegmentRectOverlayState extends State<SegmentRectOverlay> {
  Offset? _origin;

  /// BoxFit.contain 下图像在 widget 内的实际矩形。
  Rect _imageDest(Size size) {
    final iw = widget.image.width.toDouble();
    final ih = widget.image.height.toDouble();
    final scale = (size.width / iw < size.height / ih)
        ? size.width / iw
        : size.height / ih;
    final w = iw * scale;
    final h = ih * scale;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  Offset? _toNorm(Offset local, Rect dest) {
    if (!dest.contains(local)) return null;
    final nx = ((local.dx - dest.left) / dest.width).clamp(0.0, 1.0);
    final ny = ((local.dy - dest.top) / dest.height).clamp(0.0, 1.0);
    return Offset(nx, ny);
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
        final dest = _imageDest(size);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            final n = _toNorm(d.localPosition, dest);
            if (n == null) return;
            _origin = n;
            _emit(n, n);
          },
          onPanUpdate: (d) {
            final o = _origin;
            if (o == null) return;
            final n = _toNorm(d.localPosition, dest);
            if (n == null) return;
            _emit(o, n);
          },
          onPanEnd: (_) => _origin = null,
          child: CustomPaint(
            size: size,
            painter: _SegmentRectPainter(
              image: widget.image,
              dest: dest,
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

class _SegmentRectPainter extends CustomPainter {
  _SegmentRectPainter({
    required this.image,
    required this.dest,
    required this.committed,
    required this.currentIndex,
    required this.currentRect,
  });

  final ui.Image image;
  final Rect dest;
  final List<SegmentSample?> committed;
  final int currentIndex;
  final SegmentSample? currentRect;

  Rect _sampleToDest(SegmentSample s) {
    return Rect.fromLTRB(
      dest.left + s.x0 * dest.width,
      dest.top + s.y0 * dest.height,
      dest.left + s.x1 * dest.width,
      dest.top + s.y1 * dest.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: dest,
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );

    for (var i = 0; i < committed.length; i++) {
      final s = committed[i];
      if (s == null || i == currentIndex) continue;
      final r = _sampleToDest(s);
      canvas.drawRect(
        r,
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final cur = currentRect;
    if (cur != null) {
      final r = _sampleToDest(cur);
      canvas.drawRect(
        r,
        Paint()
          ..color = const Color(0x6600B4FF)
          ..style = PaintingStyle.fill,
      );
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
  bool shouldRepaint(covariant _SegmentRectPainter old) =>
      old.image != image ||
      old.dest != dest ||
      old.currentIndex != currentIndex ||
      old.currentRect != currentRect ||
      old.committed != committed;
}
