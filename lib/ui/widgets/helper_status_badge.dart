import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../state/helper_state.dart';

/// 连接/引擎相位徽标：圆点色 + 短标签；下方可跟详细文案。
class HelperStatusBadge extends StatelessWidget {
  const HelperStatusBadge({
    super.key,
    required this.phase,
    required this.message,
    this.ipcLine = '',
  });

  final HelperPhase phase;
  final String message;

  /// 最近发出的 IPC 行；非空时优先显示在小字区。
  final String ipcLine;

  @override
  Widget build(BuildContext context) {
    final (dot, label) = switch (phase) {
      HelperPhase.disconnected => (Colors.blueGrey.shade300, '未连接'),
      HelperPhase.connecting => (Colors.amber.shade400, '连接中'),
      HelperPhase.ready => (Colors.lightGreenAccent.shade400, '就绪'),
      HelperPhase.running => (AppTheme.accent, '运行中'),
      HelperPhase.poweredOff => (Colors.orangeAccent.shade200, '已熄灯'),
      HelperPhase.noDevice => (Colors.orangeAccent.shade200, '无设备'),
      HelperPhase.failed => (Colors.redAccent.shade200, '失败'),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dot.withValues(alpha: 0.45),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.control),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.control),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.section),
          child: Text(
            ipcLine.isNotEmpty ? ipcLine : message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: ipcLine.isNotEmpty ? 'Consolas' : null,
              color: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }
}
