import 'package:flutter/material.dart';

/// 应用级颜色 / 字体 / 导航动效时长（侧栏按钮用，非页面切换）。
abstract final class AppTheme {
  static const sidebarBg = Color.fromARGB(255, 26, 32, 51);
  static const contentBg = Color.fromARGB(255, 35, 39, 50);

  /// 内容区顶部模式条：比内容底略深，形成层级
  static const tabBarBg = Color.fromARGB(255, 30, 34, 44);
  static const divider = Color.fromARGB(255, 48, 53, 66);
  static const accent = Color.fromARGB(255, 96, 205, 255); // Win11 / 商店高亮蓝
  static const seed = Color.fromARGB(255, 148, 241, 255);

  /// 侧栏选中态色变时长（不是内容区翻页）
  static const navDuration = Duration(milliseconds: 220);
  static const navCurve = Curves.easeOutCubic;

  static const fontFamily = 'Microsoft YaHei'; // 微软雅黑（系统字体）

  static ThemeData get darkTheme => ThemeData(
    fontFamily: fontFamily,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ).copyWith(
          surface: contentBg,
          primary: accent,
        ),
    scaffoldBackgroundColor: contentBg,
  );
}
