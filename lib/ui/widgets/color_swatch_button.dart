import 'package:flutter/material.dart';

/// 纯色预设色卡：点一下发 `solid RRGGBB`。
class ColorSwatchButton extends StatelessWidget {
  const ColorSwatchButton({
    super.key,
    required this.color,
    required this.enabled,
    required this.onPressed,
    this.tooltip,
  });

  final Color color;
  final bool enabled;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: enabled ? color : color.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      elevation: enabled ? 2 : 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onPressed : null,
        child: const SizedBox(width: 36, height: 36),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

/// `Color` → 协议用的 6 位小写 hex（无 `#`）。
String colorToSolidHex(Color c) {
  final r = (c.r * 255.0).round().clamp(0, 255);
  final g = (c.g * 255.0).round().clamp(0, 255);
  final b = (c.b * 255.0).round().clamp(0, 255);
  return '${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';
}

/// 简单 RGB 滑条取色；确认返回选中色，取消返回 `null`。
Future<Color?> showSolidColorPicker(
  BuildContext context, {
  Color initial = const Color(0xFFFF0000),
}) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) => _SolidColorPickerDialog(initial: initial),
  );
}

class _SolidColorPickerDialog extends StatefulWidget {
  const _SolidColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_SolidColorPickerDialog> createState() =>
      _SolidColorPickerDialogState();
}

class _SolidColorPickerDialogState extends State<_SolidColorPickerDialog> {
  late double _r;
  late double _g;
  late double _b;

  @override
  void initState() {
    super.initState();
    _r = widget.initial.r * 255.0;
    _g = widget.initial.g * 255.0;
    _b = widget.initial.b * 255.0;
  }

  Color get _color => Color.fromARGB(
    255,
    _r.round().clamp(0, 255),
    _g.round().clamp(0, 255),
    _b.round().clamp(0, 255),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('取色'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              colorToSolidHex(_color).toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            _channelSlider(
              label: 'R',
              value: _r,
              activeColor: Colors.redAccent,
              onChanged: (v) => setState(() => _r = v),
            ),
            _channelSlider(
              label: 'G',
              value: _g,
              activeColor: Colors.greenAccent,
              onChanged: (v) => setState(() => _g = v),
            ),
            _channelSlider(
              label: 'B',
              value: _b,
              activeColor: Colors.lightBlueAccent,
              onChanged: (v) => setState(() => _b = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('应用'),
        ),
      ],
    );
  }

  Widget _channelSlider({
    required String label,
    required double value,
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 20, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            activeColor: activeColor,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('${value.round()}', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
