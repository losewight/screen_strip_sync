import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// WinUI 3 [SlideNavigationTransition] 风格：按索引方向横滑 + 淡入淡出。
///
/// 索引增大 → 新页自右入、旧页向左出；减小则相反。
/// 子树随 [child] 替换，不保活（适合页签内容）。
class WinUiSlideSwitcher extends StatefulWidget {
  const WinUiSlideSwitcher({
    super.key,
    required this.index,
    required this.child,
    this.duration = AppTheme.pageTransitionDuration,
    this.curve = AppTheme.pageTransitionCurve,
    this.slideFraction = 0.06,
  });

  final int index;
  final Widget child;
  final Duration duration;
  final Curve curve;

  /// 相对内容宽度的滑入距离（Fluent 短距滑入，非全页翻页）。
  final double slideFraction;

  @override
  State<WinUiSlideSwitcher> createState() => _WinUiSlideSwitcherState();
}

class _WinUiSlideSwitcherState extends State<WinUiSlideSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _t;
  late int _index;
  late Widget _incoming;
  Widget? _outgoing;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _index = widget.index;
    _incoming = widget.child;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed && _outgoing != null) {
        setState(() => _outgoing = null);
      }
    });
    _t = CurvedAnimation(parent: _controller, curve: widget.curve);
  }

  @override
  void didUpdateWidget(covariant WinUiSlideSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.curve != oldWidget.curve) {
      _t = CurvedAnimation(parent: _controller, curve: widget.curve);
    }
    if (widget.index != _index) {
      _forward = widget.index > _index;
      _outgoing = _incoming;
      _incoming = widget.child;
      _index = widget.index;
      _controller.forward(from: 0);
    } else {
      _incoming = widget.child;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final outgoing = _outgoing;
          final dx = widget.slideFraction;
          // 前进：新页从 +dx 入，旧页向 -dx 出；后退相反。
          final inFrom = _forward ? dx : -dx;
          final outTo = _forward ? -dx : dx;

          return Stack(
            fit: StackFit.expand,
            children: [
              if (outgoing != null && _t.value < 1)
                IgnorePointer(
                  child: Opacity(
                    opacity: 1 - _t.value,
                    child: FractionalTranslation(
                      translation: Offset(outTo * _t.value, 0),
                      child: outgoing,
                    ),
                  ),
                ),
              Opacity(
                opacity: _t.value.clamp(0.0, 1.0),
                child: FractionalTranslation(
                  translation: Offset(inFrom * (1 - _t.value), 0),
                  child: _incoming,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 与 [WinUiSlideSwitcher] 同动效，但子页始终挂载（Offstage 保活），
/// 适合壳层侧栏切页。
///
/// [axis] 为 [Axis.vertical] 时：索引增大 → 新页自下入、旧页向上出。
class WinUiSlideIndexedStack extends StatefulWidget {
  const WinUiSlideIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.axis = Axis.horizontal,
    this.duration = AppTheme.pageTransitionDuration,
    this.curve = AppTheme.pageTransitionCurve,
    this.slideFraction = 0.06,
  });

  final int index;
  final List<Widget> children;
  final Axis axis;
  final Duration duration;
  final Curve curve;
  final double slideFraction;

  @override
  State<WinUiSlideIndexedStack> createState() => _WinUiSlideIndexedStackState();
}

class _WinUiSlideIndexedStackState extends State<WinUiSlideIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _t;
  late int _index;
  int? _outgoingIndex;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _index = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed && _outgoingIndex != null) {
        setState(() => _outgoingIndex = null);
      }
    });
    _t = CurvedAnimation(parent: _controller, curve: widget.curve);
  }

  @override
  void didUpdateWidget(covariant WinUiSlideIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.curve != oldWidget.curve) {
      _t = CurvedAnimation(parent: _controller, curve: widget.curve);
    }
    if (widget.index != _index) {
      _forward = widget.index > _index;
      _outgoingIndex = _index;
      _index = widget.index;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Offset _offset(double delta) => widget.axis == Axis.horizontal
      ? Offset(delta, 0)
      : Offset(0, delta);

  @override
  Widget build(BuildContext context) {
    final d = widget.slideFraction;
    final inFrom = _forward ? d : -d;
    final outTo = _forward ? -d : d;

    return ClipRect(
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < widget.children.length; i++)
                _buildLayer(
                  index: i,
                  inFrom: inFrom,
                  outTo: outTo,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLayer({
    required int index,
    required double inFrom,
    required double outTo,
  }) {
    final isIncoming = index == _index;
    final isOutgoing =
        index == _outgoingIndex && _outgoingIndex != null && _t.value < 1;
    final active = isIncoming || isOutgoing;

    Widget child = widget.children[index];
    if (!active) {
      return Offstage(
        offstage: true,
        child: TickerMode(enabled: false, child: child),
      );
    }

    final opacity = isIncoming ? _t.value.clamp(0.0, 1.0) : 1 - _t.value;
    final translation = isIncoming
        ? _offset(inFrom * (1 - _t.value))
        : _offset(outTo * _t.value);

    child = Opacity(
      opacity: opacity,
      child: FractionalTranslation(
        translation: translation,
        child: child,
      ),
    );

    if (isOutgoing) {
      child = IgnorePointer(child: child);
    }

    return TickerMode(
      enabled: isIncoming,
      child: child,
    );
  }
}
