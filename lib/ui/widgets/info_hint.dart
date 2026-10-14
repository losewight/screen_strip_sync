import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 悬停与点击都能弹出同一条说明（桌面悬停仍走 Tooltip 默认行为）。
class InfoHint extends StatefulWidget {
  const InfoHint({
    super.key,
    required this.message,
    this.icon = Icons.error_outline,
  });

  final String message;
  final IconData icon;

  @override
  State<InfoHint> createState() => _InfoHintState();
}

class _InfoHintState extends State<InfoHint> {
  final _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      key: _tooltipKey,
      message: widget.message,
      // 点击弹出后多留一会儿，方便读完；悬停离开仍会立刻收起。
      showDuration: const Duration(seconds: 4),
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: () => _tooltipKey.currentState?.ensureTooltipVisible(),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            widget.icon,
            size: 16,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
