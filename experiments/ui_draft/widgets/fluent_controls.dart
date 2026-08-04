import 'package:flutter/material.dart';

import '../theme/fluent_tokens.dart';

class FluentCard extends StatelessWidget {
  const FluentCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FluentTokens.controlFill,
        border: Border.all(color: FluentTokens.strokeColor),
        borderRadius: BorderRadius.circular(FluentTokens.radiusCard),
      ),
      child: child,
    );
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    required this.desc,
    required this.trailing,
    this.showDivider = true,
    this.compactBottom = false,
  });

  final String title;
  final String desc;
  final Widget trailing;
  final bool showDivider;
  final bool compactBottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 12,
        bottom: compactBottom ? 0 : 12,
      ),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: FluentTokens.strokeColor),
              ),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: FluentTokens.fontFamily,
                    fontSize: 14,
                    color: FluentTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    fontFamily: FluentTokens.fontFamily,
                    fontSize: 12,
                    color: FluentTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          trailing,
        ],
      ),
    );
  }
}

/// Fluent Toggle：44×22，拇指 14，开时强调色 + 黑拇指。
class FluentToggle extends StatelessWidget {
  const FluentToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 22,
        decoration: BoxDecoration(
          color: value
              ? FluentTokens.accentDefault
              : const Color(0x33FFFFFF), // rgba(255,255,255,0.2)
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: value
                ? FluentTokens.accentDefault
                : const Color(0x1AFFFFFF), // 0.1
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: const Cubic(0.4, 0, 0.2, 1),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: value ? Colors.black : Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class FluentSlider extends StatelessWidget {
  const FluentSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 4,
          activeTrackColor: const Color(0x33FFFFFF),
          inactiveTrackColor: const Color(0x33FFFFFF),
          thumbColor: FluentTokens.accentDefault,
          overlayShape: SliderComponentShape.noOverlay,
          thumbShape: const _FluentThumbShape(),
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// 拇指 16px + 4px 边框色 #2d2d2d（对齐 webkit-slider-thumb）。
class _FluentThumbShape extends SliderComponentShape {
  const _FluentThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(16, 16);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(center, 8, Paint()..color = const Color(0xFF2D2D2D));
    canvas.drawCircle(center, 4, Paint()..color = FluentTokens.accentDefault);
  }
}

class FluentButton extends StatefulWidget {
  const FluentButton({
    super.key,
    required this.label,
    this.primary = false,
    this.onPressed,
  });

  final String label;
  final bool primary;
  final VoidCallback? onPressed;

  @override
  State<FluentButton> createState() => _FluentButtonState();
}

class _FluentButtonState extends State<FluentButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.primary
        ? (_hover ? FluentTokens.accentHover : FluentTokens.accentDefault)
        : (_hover ? FluentTokens.controlFillHover : FluentTokens.controlFill);
    final fg = widget.primary ? Colors.black : FluentTokens.textPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: widget.primary
                ? null
                : Border.all(color: FluentTokens.strokeColor),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: FluentTokens.fontFamily,
              fontSize: 14,
              fontWeight: widget.primary ? FontWeight.w500 : FontWeight.w400,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, this.onRestart});

  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x1A27AE60), // rgba(39,174,96,0.1)
        border: Border.all(color: const Color(0x3327AE60)), // 0.2
        borderRadius: BorderRadius.circular(FluentTokens.radiusCard),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✓ 核心已连接',
                  style: TextStyle(
                    fontFamily: FluentTokens.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2ECC71),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'C++ Helper 进程正常运行 | COM3 通信中 | 延时 2ms',
                  style: TextStyle(
                    fontFamily: FluentTokens.fontFamily,
                    fontSize: 12,
                    color: Color(0xCC2ECC71), // opacity 0.8 on green text area
                  ),
                ),
              ],
            ),
          ),
          FluentButton(label: '重启服务', onPressed: onRestart),
        ],
      ),
    );
  }
}

class FluentSelect<T> extends StatelessWidget {
  const FluentSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      decoration: BoxDecoration(
        color: FluentTokens.controlFill,
        border: Border.all(color: FluentTokens.strokeColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: const Color(0xFF2D2D2D),
          style: const TextStyle(
            fontFamily: FluentTokens.fontFamily,
            fontSize: 14,
            color: Colors.white,
          ),
          iconEnabledColor: FluentTokens.textSecondary,
          items: items
              .map(
                (e) => DropdownMenuItem<T>(
                  value: e,
                  child: Text('$e'),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: FluentTokens.fontFamily,
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: FluentTokens.textPrimary,
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: FluentTokens.fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: FluentTokens.textPrimary,
        ),
      ),
    );
  }
}
