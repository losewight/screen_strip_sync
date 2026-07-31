import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../state/helper_state.dart';

/// 各 [HelperPhase] 的强调色与展示文案（状态栏 / 进度条共用）。
class HelperPhaseStyle {
  const HelperPhaseStyle({
    required this.accent,
    required this.icon,
    required this.label,
  });

  final Color accent;
  final IconData icon;
  final String label;

  static HelperPhaseStyle of(HelperPhase phase) => switch (phase) {
    HelperPhase.disconnected => const HelperPhaseStyle(
      accent: Color(0xFF8A93A6),
      icon: Icons.power_off_outlined,
      label: '未连接',
    ),
    HelperPhase.connecting => const HelperPhaseStyle(
      accent: Color(0xFFFFC53D),
      icon: Icons.sync,
      label: '连接中',
    ),
    HelperPhase.ready => const HelperPhaseStyle(
      accent: Color(0xFF6BD98A),
      icon: Icons.check_circle_outline,
      label: '就绪',
    ),
    HelperPhase.running => HelperPhaseStyle(
      accent: AppTheme.accent,
      icon: Icons.lightbulb,
      label: '运行中',
    ),
    HelperPhase.poweredOff => const HelperPhaseStyle(
      accent: Color(0xFFFFA05C),
      icon: Icons.lightbulb_outline,
      label: '已熄灯',
    ),
    HelperPhase.noDevice => const HelperPhaseStyle(
      accent: Color(0xFFFFA05C),
      icon: Icons.usb_off_outlined,
      label: '无设备',
    ),
    HelperPhase.failed => const HelperPhaseStyle(
      accent: Color(0xFFFF6B6B),
      icon: Icons.error_outline,
      label: '连接失败',
    ),
  };
}
