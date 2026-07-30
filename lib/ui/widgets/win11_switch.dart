import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Win11 风格开关：胶囊轨道 + 圆滑块；开=蓝底黑钮，关=灰底白钮。
class Win11Switch extends StatelessWidget {
  const Win11Switch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const double _w = 40;
  static const double _h = 20;
  static const double _thumb = 12;
  static const double _pad = 4;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final trackColor = value
        ? AppTheme.accent
        : const Color.fromARGB(255, 90, 94, 105);
    final thumbColor = value
        ? const Color.fromARGB(255, 20, 20, 20)
        : const Color.fromARGB(255, 240, 240, 240);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(!value) : null,
          child: SizedBox(
            width: _w,
            height: _h,
            child: AnimatedContainer(
              duration: AppTheme.navDuration,
              curve: AppTheme.navCurve,
              decoration: BoxDecoration(
                color: trackColor,
                borderRadius: BorderRadius.circular(_h / 2),
              ),
              child: AnimatedAlign(
                duration: AppTheme.navDuration,
                curve: AppTheme.navCurve,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _pad),
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      color: thumbColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
