import 'package:flutter/material.dart';

/// WinUI / Fluent Design 间距 token（epx）。
abstract final class AppSpacing {
  /// 紧凑尺寸（开关内边距、标题与副标题等）。
  static const double compact = 4;

  /// 控件之间、控件与标签。
  static const double control = 8;

  /// 控件与标题、文本段落、卡片纵向内边距。
  static const double text = 12;

  /// 列表项 / 卡片内边距。
  static const double card = 16;

  /// 内容区块之间。
  static const double section = 24;

  /// 页面水平边距；也用于固定尺寸控件（色块、顶栏高度等）。
  static const double page = 36;

  /// 带标题的页面区块之间；也用于模式条 Tab 高度等。
  static const double pageSection = 48;

  /// 页面内容区：左右 [page]，上下 [card]（顶栏下方不必再留满 page）。
  static const EdgeInsets pageInsets = EdgeInsets.symmetric(
    horizontal: page,
    vertical: card,
  );

  /// 卡片 / 面板标准内边距。
  static const EdgeInsets cardInsets = EdgeInsets.symmetric(
    horizontal: card,
    vertical: text,
  );
}
