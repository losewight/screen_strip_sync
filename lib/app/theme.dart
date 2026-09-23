import 'package:flutter/material.dart';

/// 应用级颜色 / 字体 / 导航动效时长（侧栏按钮用，非页面切换）。
abstract final class AppTheme {
  static const sidebarBg = Color.fromARGB(255, 26, 32, 51);
  static const contentBg = Color.fromARGB(255, 35, 39, 50);

  /// 内容区顶部模式条：比内容底略深，形成层级
  static const tabBarBg = Color.fromARGB(255, 30, 34, 44);

  /// 卡片 / 输入框填充底
  static const cardBg = Color.fromARGB(255, 38, 43, 60);
  static const divider = Color.fromARGB(255, 48, 53, 66);
  static const accent = Color.fromARGB(255, 96, 205, 255); // Win11 / 商店高亮蓝
  static const seed = Color.fromARGB(255, 148, 241, 255);
  static const textPrimary = Color.fromARGB(255, 240, 240, 240);
  static const textSecondary = Color.fromARGB(255, 160, 164, 174);

  /// 全屏蒙版上的次要按钮（取消 / 返回）：淡蓝底，暗罩上更易辨认。
  static ButtonStyle get maskSecondaryButton => OutlinedButton.styleFrom(
    foregroundColor: textPrimary,
    backgroundColor: accent.withValues(alpha: 0.25),
    disabledForegroundColor: textSecondary.withValues(alpha: 0.5),
    disabledBackgroundColor: accent.withValues(alpha: 0.10),
    side: BorderSide(color: accent.withValues(alpha: 0.65)),
  );

  /// 侧栏选中态色变时长（不是内容区翻页）
  static const navDuration = Duration(milliseconds: 220);
  static const navCurve = Curves.easeOutCubic;

  static const fontFamily = 'Microsoft YaHei'; // 微软雅黑（系统字体）

  /// 弹出菜单 / 下拉列表圆角（与卡片 10 略小，避免过圆）
  static const menuRadius = 8.0;
  static final menuBorderRadius = BorderRadius.circular(menuRadius);

  static const _inputRadius = BorderRadius.all(Radius.circular(4));
  static const _inputBorderSide = BorderSide(color: divider);
  static const _inputFocusedBorderSide = BorderSide(color: accent);

  static InputDecorationTheme get _inputDecorationTheme => InputDecorationTheme(
    filled: true,
    fillColor: cardBg,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    labelStyle: const TextStyle(
      fontFamily: fontFamily,
      fontSize: 14,
      color: textSecondary,
    ),
    floatingLabelStyle: const TextStyle(
      fontFamily: fontFamily,
      fontSize: 12,
      color: accent,
    ),
    hintStyle: const TextStyle(
      fontFamily: fontFamily,
      fontSize: 14,
      color: textSecondary,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: _inputRadius,
      borderSide: _inputBorderSide,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: _inputRadius,
      borderSide: _inputFocusedBorderSide,
    ),
    border: OutlineInputBorder(
      borderRadius: _inputRadius,
      borderSide: _inputBorderSide,
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: _inputRadius,
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: _inputRadius,
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    fontFamily: fontFamily,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ).copyWith(
          surface: contentBg,
          primary: accent,
          onSurface: textPrimary,
        ),
    scaffoldBackgroundColor: contentBg,
    inputDecorationTheme: _inputDecorationTheme,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        color: textPrimary,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        color: textPrimary,
      ),
      bodySmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        color: textSecondary,
      ),
    ),
    iconTheme: const IconThemeData(color: textPrimary, size: 24),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: menuBorderRadius,
        border: Border.all(color: divider),
      ),
      textStyle: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        height: 1.45,
        color: textPrimary,
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(cardBg),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: menuBorderRadius,
            side: const BorderSide(color: divider),
          ),
        ),
      ),
      textStyle: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        color: textPrimary,
      ),
    ),
  );
}
