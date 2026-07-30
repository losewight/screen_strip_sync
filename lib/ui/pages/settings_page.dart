import 'package:flutter/material.dart';

/// 设置页：串口相关已并入主控页的连接区，这里留给后续的应用级设置。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '暂无可配置项\n串口选择已移到「主控」页的连接区',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: Colors.white38),
      ),
    );
  }
}
