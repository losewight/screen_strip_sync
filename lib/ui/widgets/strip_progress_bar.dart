import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../state/helper_state.dart';
import 'helper_phase_style.dart';

enum _StripProgressMode {
  hidden,
  marquee,
  fill,
}

/// 顶栏与内容区之间的 Win11 风格状态条；单实例挂在壳层，切页不重建。
///
/// - [HelperPhase.connecting]：不定进度跑马灯
/// - 其它已连接相位：自左向右缓入铺满
class StripProgressBar extends StatefulWidget {
  const StripProgressBar({super.key, required this.phase});

  static const double height = 3;
  static const Duration fillDuration = Duration(milliseconds: 800);
  static const Duration drainDuration = Duration(milliseconds: 320);
  static const Duration marqueeDuration = Duration(milliseconds: 1800);

  final HelperPhase phase;

  @override
  State<StripProgressBar> createState() => _StripProgressBarState();
}

_StripProgressMode _progressMode(HelperPhase phase) => switch (phase) {
  HelperPhase.disconnected ||
  HelperPhase.needConnect ||
  HelperPhase.openFailed => _StripProgressMode.hidden,
  HelperPhase.connecting => _StripProgressMode.marquee,
  _ => _StripProgressMode.fill,
};

class _StripProgressBarState extends State<StripProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fill;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _fill = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInCubic,
    );
    _syncToPhase(animate: false);
  }

  @override
  void didUpdateWidget(covariant StripProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _syncToPhase(animate: true);
    }
  }

  void _syncToPhase({required bool animate}) {
    final mode = _progressMode(widget.phase);
    switch (mode) {
      case _StripProgressMode.hidden:
        _controller.stop();
        if (!animate) {
          _controller.value = 0;
          return;
        }
        _controller.animateTo(
          0,
          duration: StripProgressBar.drainDuration,
          curve: Curves.easeOutCubic,
        );
      case _StripProgressMode.marquee:
        _controller
          ..duration = StripProgressBar.marqueeDuration
          ..repeat();
      case _StripProgressMode.fill:
        _controller.stop();
        _controller.duration = StripProgressBar.fillDuration;
        if (!animate) {
          _controller.value = 1;
          return;
        }
        _controller
          ..value = 0
          ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = _progressMode(widget.phase);
    final accent = HelperPhaseStyle.of(widget.phase).accent;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (mode == _StripProgressMode.hidden && _controller.value <= 0) {
          return const ColoredBox(
            color: AppTheme.divider,
            child: SizedBox(height: 1, width: double.infinity),
          );
        }

        return ClipRect(
          child: SizedBox(
            height: StripProgressBar.height,
            width: double.infinity,
            child: mode == _StripProgressMode.marquee
                ? CustomPaint(
                    painter: _IndeterminatePainter(
                      color: accent,
                      progress: _controller.value,
                    ),
                  )
                : CustomPaint(
                    painter: _FillPainter(
                      fillColor: accent,
                      fraction: _fill.value,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// 连接中：Win11 不定进度跑马灯。
class _IndeterminatePainter extends CustomPainter {
  const _IndeterminatePainter({
    required this.color,
    required this.progress,
  });

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppTheme.divider,
    );

    final segmentWidth = size.width * 0.34;
    final x = (size.width + segmentWidth) * progress - segmentWidth;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, 0, segmentWidth, size.height),
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _IndeterminatePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.progress != progress;
}

/// 就绪 / 运行 / 关灯等：轨道 + 自左向右缓入铺满。
class _FillPainter extends CustomPainter {
  const _FillPainter({
    required this.fillColor,
    required this.fraction,
  });

  final Color fillColor;
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppTheme.divider,
    );

    if (fraction <= 0) return;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * fraction.clamp(0, 1), size.height),
      Paint()..color = fillColor,
    );
  }

  @override
  bool shouldRepaint(covariant _FillPainter oldDelegate) =>
      oldDelegate.fillColor != fillColor || oldDelegate.fraction != fraction;
}
