import 'package:flutter/material.dart';

/// 与 HTML `:root` CSS 变量一一对应。
abstract final class FluentTokens {
  static const Color sysBg = Color(0xFF1C1C1C);
  static const Color micaBg = Color(0xA6202020); // rgba(32,32,32,0.65)
  static const Color controlFill = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
  static const Color controlFillHover = Color(0x14FFFFFF); // 0.08
  static const Color accentDefault = Color(0xFF60CDFF);
  static const Color accentHover = Color(0xFF4CC2FF);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF); // 0.7
  static const Color strokeColor = Color(0x14FFFFFF); // 0.08
  static const Color layerBg = Color(0x08FFFFFF); // 0.03

  static const double radiusWindow = 12;
  static const double radiusControl = 6;
  static const double radiusCard = 8;

  static const double windowWidth = 1000;
  static const double windowHeight = 640;
  static const double titleBarHeight = 40;
  static const double navWidth = 240;

  static const String fontFamily = 'Segoe UI';

  /// body 桌面背景：radial-gradient(circle at top right, #003a70, #000 60%)
  static const LinearGradient desktopBackdrop = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF003A70), Color(0xFF000000)],
    stops: [0.0, 0.6],
  );
}
