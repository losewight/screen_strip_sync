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
  late Color _activeColor;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);
    _activeColor = _seedActive(cfg);
  }

  static Color _seedActive(AppConfig cfg) {
    const prefix = 'solid ';
    if (cfg.lastScene.startsWith(prefix)) {
      final c = colorFromSolidHex(cfg.lastScene.substring(prefix.length));
      if (c != null) return c;
    }
    return _customFromCfg(cfg);
  }

  static Color _customFromCfg(AppConfig cfg) {
    return colorFromSolidHex(cfg.lastCustomSolid) ??
        SolidSchemePanel._defaultCustom;
  }

  void _sendSolid(HelperStateNotifier notifier, Color color) {
    setState(() => _activeColor = color);
    notifier.sendSolid(colorToSolidHex(color));
  }

  void _applyCustom(
    ConfigNotifier config,
    HelperStateNotifier notifier,
    Color picked,
  ) {
    final hex = colorToSolidHex(picked);
    setState(() => _activeColor = picked);
    config.setLastCustomSolid(hex);
    notifier.sendLastCustomSolid(hex);
    notifier.sendSolid(hex);
  }

  Future<void> _pickColor(
    BuildContext context,
    ConfigNotifier config,
    HelperStateNotifier notifier,
  ) async {
    final picked = await showSolidColorPicker(context);
    if (picked == null || !context.mounted) return;
    _applyCustom(config, notifier, picked);
  }

  Future<void> _pickPalette(
    BuildContext context,
    ConfigNotifier config,
    HelperStateNotifier notifier,
    Color initial,
  ) async {
    final picked = await showPaletteColorPicker(context, initial: initial);
    if (picked == null || !context.mounted) return;
    _applyCustom(config, notifier, picked);
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final can = ui.canControl;
    final customColor = _customFromCfg(cfg);

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
                        color: customColor,
                        enabled: can,
                        outlined: true,
                        tooltip: '自定义',
                        onPressed: () => _pickPalette(
                          context,
                          config,
                          notifier,
                          customColor,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: can
                            ? () => _pickColor(context, config, notifier)
                            : null,
                        icon: const Icon(Icons.colorize, size: 18),
                        label: const Text('取色'),
                      ),
                      const SizedBox(width: AppSpacing.control),
                      OutlinedButton.icon(
                        onPressed: can
                            ? () => _pickPalette(
                                context,
                                config,
                                notifier,
                                customColor,
                              )
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
