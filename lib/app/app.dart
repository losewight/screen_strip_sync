import 'package:flutter/material.dart';

import '../ui/shell/main_shell.dart';
import 'app_lifecycle_host.dart';
import 'theme.dart';

class ScreenStripSyncApp extends StatelessWidget {
  const ScreenStripSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Screen Strip Sync',
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      // 为什么：关窗 quit / 唤醒重连挂在 App 级，不绑某一页
      home: const AppLifecycleHost(child: MainShell()),
    );
  }
}
