import 'package:flutter/material.dart';

import '../../app/theme.dart';

Offset _axisOffset(Axis axis, double pixels) {
  final snapped = pixels.roundToDouble();
  return axis == Axis.horizontal ? Offset(snapped, 0) : Offset(0, snapped);
}

/// WinUI 3 [SlideNavigationTransition] 风格：按索引方向横滑 + 淡入淡出。
///
/// 索引增大 → 新页自右入、旧页向左出；减小则相反。
/// 子树随 [child] 替换，不保活（适合页签内容）。
class WinUiSlideSwitcher extends StatefulWidget {
  const WinUiSlideSwitcher({
    super.key,
    required this.index,
    required this.child,
    this.axis = Axis.horizontal,
    this.duration = AppTheme.pageTransitionDuration,
    this.curve = AppTheme.pageTransitionCurve,
    this.slideFraction = 0.06,
  });

  final int index;
  final Widget child;
  final Axis axis;
  final Duration duration;
  final Curve curve;

  /// 相对内容主轴长度的滑入距离（Fluent 短距滑入，非全页翻页）。
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = widget.axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final travel = extent * widget.slideFraction;

        return ClipRect(
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final outgoing = _outgoing;
              final t = _t.value.clamp(0.0, 1.0);
              final inFrom = _forward ? travel : -travel;
              final outTo = _forward ? -travel : travel;

              return Stack(
                fit: StackFit.expand,
                children: [
                  if (outgoing != null && t < 1)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _SlideFadeLayer(
                          opacity: 1 - t,
                          offset: _axisOffset(widget.axis, outTo * t),
                          child: outgoing,
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: _SlideFadeLayer(
                      opacity: t,
                      offset: _axisOffset(widget.axis, inFrom * (1 - t)),
                      child: _incoming,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = widget.axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final travel = extent * widget.slideFraction;
        final inFrom = _forward ? travel : -travel;
        final outTo = _forward ? -travel : travel;

        return ClipRect(
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final t = _t.value.clamp(0.0, 1.0);
              // 始终先画旧页、再画新页，避免切到较小索引时旧页盖住新页造成横抖感。
              final outgoing = _outgoingIndex;
              final stackChildren = <Widget>[
                for (var i = 0; i < widget.children.length; i++)
                  if (i != _index && i != outgoing)
                    Positioned.fill(
                      child: _buildLayer(
                        index: i,
                        t: t,
                        inFrom: inFrom,
                        outTo: outTo,
                      ),
                    ),
                if (outgoing != null)
                  Positioned.fill(
                    child: _buildLayer(
                      index: outgoing,
                      t: t,
                      inFrom: inFrom,
                      outTo: outTo,
                    ),
                  ),
                Positioned.fill(
                  child: _buildLayer(
                    index: _index,
                    t: t,
                    inFrom: inFrom,
                    outTo: outTo,
                  ),
                ),
              ];
              return Stack(
                fit: StackFit.expand,
                children: stackChildren,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildLayer({
    required int index,
    required double t,
    required double inFrom,
    required double outTo,
  }) {
    final isIncoming = index == _index;
    final isOutgoing =
        index == _outgoingIndex && _outgoingIndex != null && t < 1;
    final active = isIncoming || isOutgoing;
    final child = widget.children[index];

    if (!active) {
      return Offstage(
        offstage: true,
        child: TickerMode(enabled: false, child: child),
      );
    }

    final opacity = isIncoming ? t : 1 - t;
    final pixels = isIncoming ? inFrom * (1 - t) : outTo * t;

    return TickerMode(
      enabled: isIncoming,
      child: IgnorePointer(
        ignoring: isOutgoing,
        child: _SlideFadeLayer(
          opacity: opacity,
          offset: _axisOffset(widget.axis, pixels),
          child: child,
        ),
      ),
    );
  }
}

/// 整像素位移 + 淡入淡出。
///
/// 铺不透明 [AppTheme.contentBg]，避免居中内容四周镂空把另一页透出来。
class _SlideFadeLayer extends StatelessWidget {
  const _SlideFadeLayer({
    required this.opacity,
    required this.offset,
    required this.child,
  });

  final double opacity;
  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget layer = ColoredBox(
      color: AppTheme.contentBg,
      child: SizedBox.expand(
        child: RepaintBoundary(child: child),
      ),
    );
    final o = opacity.clamp(0.0, 1.0);
    if (o < 1) {
      layer = Opacity(opacity: o, child: layer);
    }
    return Transform.translate(
      offset: offset,
      filterQuality: FilterQuality.none,
      child: layer,
    );
  }
}
