import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Win11 风格分段切换：胶囊轨道 + 选中块滑动动画。
class Win11SegmentedControl<T> extends StatelessWidget {
  const Win11SegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<Win11Segment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  static const double _height = 32;
  /// 轨道与选中块之间的缝，贴近 Win11（约 2epx）。
  static const double _inset = 2;
  static const Color _track = Color.fromARGB(255, 30, 34, 44);
  static const Color _thumb = Color.fromARGB(255, 56, 60, 72);

  int get _selectedIndex {
    final i = segments.indexWhere((s) => s.value == selected);
    return i < 0 ? 0 : i;
  }

  /// [Align] 在等分宽度子项下的 x：左端 -1，右端 +1，中间按段均分。
  static double _alignX(int index, int count) {
    if (count <= 1) return 0;
    return 2 * index / (count - 1) - 1;
  }

  @override
  Widget build(BuildContext context) {
    final n = segments.length;
    assert(n > 0);
    final trackRadius = _height / 2;
    final thumbRadius = (_height - _inset * 2) / 2;

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: _track,
        borderRadius: BorderRadius.circular(trackRadius),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: const EdgeInsets.all(_inset),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: AppTheme.navDuration,
            curve: AppTheme.navCurve,
            alignment: Alignment(_alignX(_selectedIndex, n), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _thumb,
                  borderRadius: BorderRadius.circular(thumbRadius),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final segment in segments)
                Expanded(
                  child: _SegmentLabel(
                    label: segment.label,
                    selected: segment.value == selected,
                    onTap: () {
                      if (segment.value != selected) {
                        onChanged(segment.value);
                      }
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class Win11Segment<T> {
  const Win11Segment({required this.value, required this.label});

  final T value;
  final String label;
}

class _SegmentLabel extends StatefulWidget {
  const _SegmentLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SegmentLabel> createState() => _SegmentLabelState();
}

class _SegmentLabelState extends State<_SegmentLabel> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.selected
        ? AppTheme.accent
        : _hover
        ? AppTheme.textPrimary
        : AppTheme.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: AppTheme.navDuration,
            curve: AppTheme.navCurve,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 13,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
              color: fg,
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
