import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import 'color_swatch_button.dart';

/// 弹出 HSV 调色盘；确定返回选中色，取消返回 `null`。
Future<Color?> showPaletteColorPicker(
  BuildContext context, {
  Color initial = const Color(0xFFFF0000),
  String title = '调色盘',
}) {
  return showDialog<Color>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _PaletteColorDialog(initial: initial, title: title),
  );
}

class _PaletteColorDialog extends StatefulWidget {
  const _PaletteColorDialog({required this.initial, required this.title});

  final Color initial;
  final String title;

  @override
  State<_PaletteColorDialog> createState() => _PaletteColorDialogState();
}

class _PaletteColorDialogState extends State<_PaletteColorDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  void _setHsv(HSVColor next) => setState(() => _hsv = next);

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    final hex = colorToSolidHex(color).toUpperCase();

    return Dialog(
      backgroundColor: AppTheme.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.divider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: AppSpacing.cardInsets,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.text),
              AspectRatio(
                aspectRatio: 1.2,
                child: _SvSquare(
                  hsv: _hsv,
                  onChanged: _setHsv,
                ),
              ),
              const SizedBox(height: AppSpacing.text),
              _HueBar(
                hue: _hsv.hue,
                onChanged: (h) => _setHsv(_hsv.withHue(h)),
              ),
              const SizedBox(height: AppSpacing.text),
              Row(
                children: [
                  Container(
                    width: AppSpacing.pageSection,
                    height: AppSpacing.page,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.divider),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.text),
                  Text(
                    '#$hex',
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: AppSpacing.control),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(color),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 饱和度 × 明度面板（横向 S，纵向 V）。
class _SvSquare extends StatelessWidget {
  const _SvSquare({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _emit(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = 1.0 - (local.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => _emit(d.localPosition, size),
            onPanUpdate: (d) => _emit(d.localPosition, size),
            child: CustomPaint(
              size: size,
              painter: _SvPainter(hsv: hsv),
            ),
          ),
        );
      },
    );
  }
}

class _SvPainter extends CustomPainter {
  _SvPainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();

    // 白 → 纯色（饱和度）
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hueColor],
        ).createShader(rect),
    );
    // 透明 → 黑（明度）
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );

    final dx = hsv.saturation * size.width;
    final dy = (1.0 - hsv.value) * size.height;
    canvas.drawCircle(
      Offset(dx, dy),
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      Offset(dx, dy),
      8,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SvPainter old) => old.hsv != hsv;
}

/// 色相条（0..360）。
class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  static const _hues = <Color>[
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  void _emit(Offset local, double width) {
    onChanged(((local.dx / width).clamp(0.0, 1.0) * 360.0));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => _emit(d.localPosition, w),
              onPanUpdate: (d) => _emit(d.localPosition, w),
              child: CustomPaint(
                size: Size(w, 20),
                painter: _HuePainter(hue: hue),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HuePainter extends CustomPainter {
  _HuePainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          colors: _HueBar._hues,
        ).createShader(rect),
    );

    final x = (hue / 360.0).clamp(0.0, 1.0) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, size.height / 2),
          width: 6,
          height: size.height,
        ),
        const Radius.circular(2),
      ),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _HuePainter old) => old.hue != hue;
}
