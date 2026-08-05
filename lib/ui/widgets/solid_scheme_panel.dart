import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../state/helper_state.dart';
import 'color_swatch_button.dart';
import 'palette_color_picker.dart';
import 'scheme_card.dart';

/// 纯色模式面板。
class SolidSchemePanel extends ConsumerWidget {
  const SolidSchemePanel({super.key});

  static const _presets = <(String, Color)>[
    ('红', Color(0xFFFF0000)),
    ('绿', Color(0xFF00FF00)),
    ('蓝', Color(0xFF0000FF)),
    ('白', Color(0xFFFFFFFF)),
    ('橙', Color(0xFFFF8800)),
  ];

  Future<void> _pickColor(
    BuildContext context,
    HelperStateNotifier notifier,
  ) async {
    final picked = await showSolidColorPicker(context);
    if (picked == null || !context.mounted) return;
    notifier.sendSolid(colorToSolidHex(picked));
  }

  Future<void> _pickPalette(
    BuildContext context,
    HelperStateNotifier notifier,
  ) async {
    final picked = await showPaletteColorPicker(context);
    if (picked == null || !context.mounted) return;
    notifier.sendSolid(colorToSolidHex(picked));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final can = ui.canControl;

    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SchemeCard(
                title: '纯色',
                child: Wrap(
                  spacing: AppSpacing.text,
                  runSpacing: AppSpacing.text,
                  children: [
                    for (final (name, color) in _presets)
                      ColorSwatchButton(
                        color: color,
                        enabled: can,
                        tooltip: name,
                        onPressed: () =>
                            notifier.sendSolid(colorToSolidHex(color)),
                      ),
                    OutlinedButton.icon(
                      onPressed: can
                          ? () => _pickColor(context, notifier)
                          : null,
                      icon: const Icon(Icons.colorize, size: 18),
                      label: const Text('取色'),
                    ),
                    OutlinedButton.icon(
                      onPressed: can
                          ? () => _pickPalette(context, notifier)
                          : null,
                      icon: const Icon(Icons.palette_outlined, size: 18),
                      label: const Text('调色盘'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
