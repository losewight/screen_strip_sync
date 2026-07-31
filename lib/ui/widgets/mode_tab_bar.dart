import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';

/// 顶部模式页签的一项：图标 + 文案 + 图标专属色。
class ModeTabItem {
  const ModeTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 内容区顶部的模式切换条（屏幕同步 / 纯色 / 特效 / 音乐）。
class ModeTabBar extends StatelessWidget {
  const ModeTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const double height = 64;

  final List<ModeTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: AppTheme.tabBarBg,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.text),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              _ModeTab(
                item: items[i],
                selected: i == selectedIndex,
                onTap: () => onSelected(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatefulWidget {
  const _ModeTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ModeTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ModeTab> createState() => _ModeTabState();
}

class _ModeTabState extends State<_ModeTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? const Color.fromARGB(255, 56, 60, 72)
        : _hover
        ? const Color.fromARGB(26, 255, 255, 255)
        : Colors.transparent;
    final fg = widget.selected
        ? AppTheme.accent
        : const Color.fromARGB(255, 230, 230, 230);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.compact,
        vertical: AppSpacing.control,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppTheme.navDuration,
            curve: AppTheme.navCurve,
            height: AppSpacing.pageSection,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.selected ? widget.item.selectedIcon : widget.item.icon,
                  size: 20,
                  color: fg,
                ),
                const SizedBox(width: AppSpacing.control),
                AnimatedDefaultTextStyle(
                  duration: AppTheme.navDuration,
                  curve: AppTheme.navCurve,
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 13,
                    color: fg,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  child: Text(widget.item.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
