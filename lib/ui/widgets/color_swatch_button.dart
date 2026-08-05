import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import 'screen_color_picker.dart';

/// 纯色预设色卡：点一下发 `solid RRGGBB`。
class ColorSwatchButton extends StatelessWidget {
  const ColorSwatchButton({
    super.key,
    required this.color,
    required this.enabled,
    required this.onPressed,
    this.tooltip,
    this.outlined = false,
  });

  final Color color;
  final bool enabled;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// 自定义色圈描边，与预设区分。
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: enabled ? color : color.withValues(alpha: 0.35),
      shape: CircleBorder(
        side: outlined
            ? const BorderSide(color: AppTheme.accent, width: 2)
            : BorderSide.none,
      ),
      elevation: enabled ? 2 : 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onPressed : null,
        child: const SizedBox(
          width: AppSpacing.page,
          height: AppSpacing.page,
        ),
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

/// 解析 6 位 hex；非法返回 `null`。
Color? colorFromSolidHex(String hex) {
  final h = hex.trim().toLowerCase();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

/// 屏幕取色器；确认返回选中色，取消返回 `null`。
Future<Color?> showSolidColorPicker(BuildContext context) {
  return showScreenColorPicker(context);
}
