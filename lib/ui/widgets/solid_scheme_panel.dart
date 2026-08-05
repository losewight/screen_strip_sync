import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import 'color_swatch_button.dart';
import 'palette_color_picker.dart';
import 'scheme_card.dart';

/// 纯色模式面板。
class SolidSchemePanel extends ConsumerStatefulWidget {
  const SolidSchemePanel({super.key});

  static const _presets = <(String, Color)>[
    ('红', Color(0xFFFF0000)),
    ('绿', Color(0xFF00FF00)),
    ('蓝', Color(0xFF0000FF)),
    ('白', Color(0xFFFFFFFF)),
    ('橙', Color(0xFFFF8800)),
  ];

  static const _defaultCustom = Color(0xFF9C27B0);

  @override
  ConsumerState<SolidSchemePanel> createState() => _SolidSchemePanelState();
}

class _SolidSchemePanelState extends ConsumerState<SolidSchemePanel> {
  late Color _customColor;
  late Color _activeColor;

  @override
  void initState() {
    super.initState();
    final seeded = _seedColor(ref.read(configProvider).lastScene);
    _customColor = seeded;
    _activeColor = seeded;
  }

  static Color _seedColor(String lastScene) {
    const prefix = 'solid ';
    if (!lastScene.startsWith(prefix)) return SolidSchemePanel._defaultCustom;
    final c = colorFromSolidHex(lastScene.substring(prefix.length));
    return c ?? SolidSchemePanel._defaultCustom;
  }

  void _sendSolid(HelperStateNotifier notifier, Color color) {
    setState(() => _activeColor = color);
    notifier.sendSolid(colorToSolidHex(color));
  }

  void _applyCustom(HelperStateNotifier notifier, Color picked) {
    setState(() {
      _customColor = picked;
      _activeColor = picked;
    });
    notifier.sendSolid(colorToSolidHex(picked));
  }

  Future<void> _pickColor(
    BuildContext context,
    HelperStateNotifier notifier,
  ) async {
    final picked = await showSolidColorPicker(context);
    if (picked == null || !context.mounted) return;
    _applyCustom(notifier, picked);
  }

  Future<void> _pickPalette(
    BuildContext context,
    HelperStateNotifier notifier,
  ) async {
    final picked = await showPaletteColorPicker(
      context,
      initial: _customColor,
    );
    if (picked == null || !context.mounted) return;
    _applyCustom(notifier, picked);
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final can = ui.canControl;

    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SchemeCard(
                  title: '纯色',
                  actions: [
                    FilledButton(
                      onPressed: can
                          ? () => _sendSolid(notifier, _activeColor)
                          : null,
                      child: const Text('开始使用纯色'),
                    ),
                    OutlinedButton(
                      onPressed: can ? notifier.softOff : null,
                      child: const Text('关灯'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.text),
                SchemeCard(
                  title: '色卡',
                  child: Row(
                    children: [
                      for (final (name, color)
                          in SolidSchemePanel._presets) ...[
                        ColorSwatchButton(
                          color: color,
                          enabled: can,
                          tooltip: name,
                          onPressed: () => _sendSolid(notifier, color),
                        ),
                        const SizedBox(width: AppSpacing.text),
                      ],
                      ColorSwatchButton(
                        color: _customColor,
                        enabled: can,
                        outlined: true,
                        tooltip: '自定义',
                        onPressed: () => _pickPalette(context, notifier),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: can
                            ? () => _pickColor(context, notifier)
                            : null,
                        icon: const Icon(Icons.colorize, size: 18),
                        label: const Text('取色'),
                      ),
                      const SizedBox(width: AppSpacing.control),
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
      ),
    );
  }
}
