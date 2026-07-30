import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../app/theme.dart';

class StoreNavItem {
  const StoreNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 微软商店风格侧栏：蓝条 Squash & stretch + 弹簧进度。
class StoreSidebar extends StatefulWidget {
  const StoreSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<StoreNavItem> items;

  @override
  State<StoreSidebar> createState() => _StoreSidebarState();
}

class _StoreSidebarState extends State<StoreSidebar>
    with SingleTickerProviderStateMixin {
  static const double _width = 72;
  static const double _padV = 8;
  static const double _btnOuterH = 68; // 64 内容 + 上下各 2 padding
  static const double _indicatorH = 22;
  static const double _indicatorW = 5;

  /// STANDARDS：弹簧略带弹性（ratio < 1），导航切换保持克制
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 280,
    ratio: 0.78,
  );

  late final AnimationController _ctrl;
  late double _fromTop;
  late double _fromH;
  late double _toTop;
  late double _toH;
  double _railHeight = 0;

  double _restingTop(int index) =>
      _padV + index * _btnOuterH + (_btnOuterH - _indicatorH) / 2;

  void _snapToSelected() {
    if (_railHeight <= 0) return;
    _fromTop = _toTop = _restingTop(widget.selectedIndex);
    _fromH = _toH = _indicatorH;
    _ctrl.value = 1;
  }

  void _animateToSelected() {
    if (_railHeight <= 0) return;
    final cur = _stretchGeometry(_ctrl.value);
    _fromTop = cur.top;
    _fromH = cur.height;
    _toTop = _restingTop(widget.selectedIndex);
    _toH = _indicatorH;
    // 弹簧驱动进度 0→1：非匀速、可轻微过冲；保留速度便于中途改目标
    _ctrl.animateWith(
      SpringSimulation(_spring, 0, 1, _ctrl.velocity),
    );
  }

  @override
  void initState() {
    super.initState();
    _fromTop = _toTop = 0;
    _fromH = _toH = _indicatorH;
    _ctrl = AnimationController.unbounded(vsync: this)..value = 1;
  }

  @override
  void didUpdateWidget(covariant StoreSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex == oldWidget.selectedIndex) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _snapToSelected();
      return;
    }
    _animateToSelected();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 前沿先冲、后沿后跟上 → 中段拉长再收回；t 由弹簧驱动
  ({double top, double height}) _stretchGeometry(double t) {
    final leadT = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
    final trailT = Curves.easeInCubic.transform(t.clamp(0.0, 1.0));
    final overshoot = t > 1 ? (t - 1) : (t < 0 ? t : 0.0);

    final fromBottom = _fromTop + _fromH;
    final toBottom = _toTop + _toH;
    final movingDown = _toTop >= _fromTop;

    double top;
    double bottom;
    if (movingDown) {
      top = _fromTop + (_toTop - _fromTop) * trailT;
      bottom = fromBottom + (toBottom - fromBottom) * leadT;
    } else {
      top = _fromTop + (_toTop - _fromTop) * leadT;
      bottom = fromBottom + (toBottom - fromBottom) * trailT;
    }

    if (overshoot != 0) {
      final mid = (top + bottom) / 2;
      final half = (bottom - top) / 2 * (1 + overshoot.abs() * 0.35);
      top = mid - half;
      bottom = mid + half;
    }

    return (top: top, height: math.max(bottom - top, 1));
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return ColoredBox(
      color: AppTheme.sidebarBg,
      child: SizedBox(
        width: _width,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              if (h > 0 && h != _railHeight) {
                final firstLayout = _railHeight <= 0;
                _railHeight = h;
                if (firstLayout && !_ctrl.isAnimating) {
                  _fromTop = _toTop = _restingTop(widget.selectedIndex);
                  _fromH = _toH = _indicatorH;
                }
              }

              return Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: _padV),
                    child: Column(
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          _StoreNavButton(
                            item: widget.items[i],
                            selected: i == widget.selectedIndex,
                            onTap: () => widget.onSelected(i),
                          ),
                      ],
                    ),
                  ),
                  if (_railHeight > 0)
                    AnimatedBuilder(
                      animation: _ctrl,
                      builder: (context, _) {
                        final geo = reduceMotion
                            ? (
                                top: _restingTop(widget.selectedIndex),
                                height: _indicatorH,
                              )
                            : _stretchGeometry(_ctrl.value);
                        return Positioned(
                          left: 6,
                          top: geo.top,
                          child: IgnorePointer(
                            child: Container(
                              width: _indicatorW,
                              height: geo.height,
                              decoration: BoxDecoration(
                                color: AppTheme.accent,
                                borderRadius: BorderRadius.circular(
                                  _indicatorW / 2,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StoreNavButton extends StatelessWidget {
  const _StoreNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final StoreNavItem item;
  final bool selected;
  final VoidCallback onTap;

  static const _idleFg = Color.fromARGB(255, 230, 230, 230);
  // 相对侧栏 (26,32,51) 略提亮，贴近商店选中底
  static const _selectedBg = Color.fromARGB(255, 40, 50, 78);

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppTheme.accent : _idleFg;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: const Color.fromARGB(40, 255, 255, 255),
          child: AnimatedContainer(
            duration: AppTheme.navDuration,
            curve: AppTheme.navCurve,
            height: 64,
            decoration: BoxDecoration(
              color: selected ? _selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: TweenAnimationBuilder<Color?>(
                duration: AppTheme.navDuration,
                curve: AppTheme.navCurve,
                tween: ColorTween(end: fg),
                builder: (context, color, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selected ? item.selectedIcon : item.icon,
                        size: 22,
                        color: color,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: color,
                          fontSize: 11,
                          height: 1.1,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
