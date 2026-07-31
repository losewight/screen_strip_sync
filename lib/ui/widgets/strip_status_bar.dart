import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../state/helper_state.dart';
import 'helper_phase_style.dart';

/// 主控顶部状态栏：与 [ModeTabBar] 同高同色，展示灯带当前工作状态。
class StripStatusBar extends StatelessWidget {
  const StripStatusBar({super.key, required this.phase});

  /// 与模式条对齐，避免两页顶部高度跳动
  static const double height = 64;

  final HelperPhase phase;

  @override
  Widget build(BuildContext context) {
    final style = HelperPhaseStyle.of(phase);
    final accent = style.accent;
    final icon = style.icon;
    final label = style.label;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: AppTheme.tabBarBg,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          AnimatedContainer(
            duration: AppTheme.navDuration,
            curve: AppTheme.navCurve,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 19, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '灯带$label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color.fromARGB(255, 240, 240, 240),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _StatusPill(color: accent, label: label),
        ],
      ),
    );
  }
}

/// 右侧状态胶囊：色点 + 短标签，Win11 风格弱底色。
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppTheme.navDuration,
      curve: AppTheme.navCurve,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
