import 'package:flutter/material.dart';

import '../theme/fluent_tokens.dart';

/// 原版 `.preview-module`：20 灯顺时针 上7 / 右3 / 下7 / 左3。
class LedPreview extends StatelessWidget {
  const LedPreview({
    super.key,
    required this.ledColors,
    required this.monitorText,
    required this.wallpaper,
  });

  final List<Color> ledColors;
  final String monitorText;
  final Decoration wallpaper;

  static const _monitorW = 340.0;
  static const _monitorH = 190.0;

  @override
  Widget build(BuildContext context) {
    assert(ledColors.length == 20);

    final top = ledColors.sublist(0, 7);
    final right = ledColors.sublist(7, 10);
    final bottom = ledColors.sublist(10, 17);
    final left = ledColors.sublist(17, 20);

    return Container(
      height: 220,
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border.all(color: FluentTokens.strokeColor),
        borderRadius: BorderRadius.circular(FluentTokens.radiusCard),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 40,
            spreadRadius: -8,
            offset: Offset(0, 0),
          ),
        ],
      ),
      child: Center(
        child: SizedBox(
          width: _monitorW,
          height: _monitorH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 显示器边框
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF333333),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: DecoratedBox(
                      decoration: wallpaper,
                      child: Center(
                        child: Text(
                          monitorText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: FluentTokens.fontFamily,
                            fontSize: 12,
                            color: Color(0xFF666666),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // LED 容器 inset -14（相对 monitor）
              Positioned(
                left: -14,
                top: -14,
                right: -14,
                bottom: -14,
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      // top: top -6 relative to led-container → 8 from outer;
                      // HTML: .led-top { top:-6px; left:14px; right:14px }
                      Positioned(
                        top: 8,
                        left: 28,
                        right: 28,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: top.map(_led).toList(),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 28,
                        right: 28,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: bottom.map(_led).toList(),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        top: 28,
                        bottom: 28,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: left.map(_led).toList(),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 28,
                        bottom: 28,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: right.map(_led).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _led(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.9),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
    );
  }
}
