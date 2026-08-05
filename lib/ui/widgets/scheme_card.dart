import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';

/// 灯光方案页共用小卡片：圆角 + 描边 + [AppTheme.cardBg]。
///
/// - 传 [actions]：标题左、操作右
/// - 传 [child]：标题在上、内容在下
class SchemeCard extends StatelessWidget {
  const SchemeCard({
    super.key,
    this.title,
    this.titleTrailing,
    this.actions,
    this.child,
  }) : assert(actions != null || child != null);

  static const double radius = 10;

  final String? title;
  final Widget? titleTrailing;
  final List<Widget>? actions;
  final Widget? child;

  static const titleStyle = TextStyle(
    fontFamily: AppTheme.fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppTheme.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (actions != null) {
      body = Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(title ?? '', style: titleStyle),
                if (titleTrailing != null) ...[
                  const SizedBox(width: AppSpacing.compact),
                  titleTrailing!,
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.text),
          for (var i = 0; i < actions!.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.control),
            actions![i],
          ],
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Text(title!, style: titleStyle),
                if (titleTrailing != null) ...[
                  const SizedBox(width: AppSpacing.compact),
                  titleTrailing!,
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.text),
          ],
          child!,
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: AppSpacing.cardInsets,
      child: body,
    );
  }
}

/// 参数滑条上方的次要说明文字。
class SchemeParamLabel extends StatelessWidget {
  const SchemeParamLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 12,
        color: AppTheme.textSecondary,
        letterSpacing: 0.4,
      ),
    );
  }
}

/// 尚未实现的模式占位。
class SchemeComingSoonPanel extends StatelessWidget {
  const SchemeComingSoonPanel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SchemeCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.construction,
                  size: AppSpacing.page,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(height: AppSpacing.text),
                Text(
                  '$label 还没做',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
