import 'package:flutter/material.dart';

import 'theme/fluent_tokens.dart';
import 'widgets/fluent_app_window.dart';

/// 草稿入口：还原 HTML Fluent Pro 内容区，系统窗即外壳（不再套一层模拟窗）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UiDraftApp());
}

class UiDraftApp extends StatelessWidget {
  const UiDraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zeeray Ambilight 控制台',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: FluentTokens.fontFamily,
        scaffoldBackgroundColor: FluentTokens.sysBg,
        useMaterial3: true,
      ),
      // 外层系统标题栏负责壳；这里只铺 mica 内容，对齐 .app-window 背景。
      home: const Scaffold(
        backgroundColor: Color(0xFF202020),
        body: FluentAppWindow(),
      ),
    );
  }
}
