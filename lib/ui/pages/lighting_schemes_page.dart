import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/helper_status_badge.dart';
import '../widgets/mode_tab_bar.dart';

/// 灯光方案：顶部模式页签 + 各模式面板；状态由 Provider 驱动。
class LightingSchemesPage extends ConsumerStatefulWidget {
  const LightingSchemesPage({super.key});

  @override
  ConsumerState<LightingSchemesPage> createState() =>
      _LightingSchemesPageState();
}

class _LightingSchemesPageState extends ConsumerState<LightingSchemesPage> {
  static const _presets = <(String, Color)>[
    ('红', Color(0xFFFF0000)),
    ('绿', Color(0xFF00FF00)),
    ('蓝', Color(0xFF0000FF)),
    ('白', Color(0xFFFFFFFF)),
    ('橙', Color(0xFFFF8800)),
  ];

  static const _tabs = <ModeTabItem>[
    ModeTabItem(
      icon: Icons.desktop_windows_outlined,
      selectedIcon: Icons.desktop_windows,
      label: '屏幕同步',
    ),
    ModeTabItem(
      icon: Icons.palette_outlined,
      selectedIcon: Icons.palette,
      label: '纯色模式',
    ),
    ModeTabItem(
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
      label: '动态特效',
    ),
    ModeTabItem(
      icon: Icons.music_note_outlined,
      selectedIcon: Icons.music_note,
      label: '音乐律动',
    ),
  ];

  int _tab = 0;

  Color _lastPicked = const Color(0xFFFF0000);

  Future<void> _pickColor(HelperStateNotifier notifier) async {
    final picked = await showSolidColorPicker(
      context,
      initial: _lastPicked,
    );
    if (picked == null || !mounted) return;
    setState(() => _lastPicked = picked);
    notifier.sendSolid(colorToSolidHex(picked));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ModeTabBar(
          items: _tabs,
          selectedIndex: _tab,
          onSelected: (i) {
            if (i == _tab) return;
            setState(() => _tab = i);
          },
        ),
        Expanded(
          child: switch (_tab) {
            0 => _buildScreenSync(context),
            1 => _buildSolid(context),
            _ => _ComingSoonPanel(label: _tabs[_tab].label),
          },
        ),
      ],
    );
  }

  Widget _buildScreenSync(BuildContext context) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final can = ui.canControl;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HelperStatusBadge(phase: ui.phase, message: ui.message),
              const SizedBox(height: 28),
              _sectionLabel(context, '引擎'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: can ? () => notifier.send('start') : null,
                    child: const Text('开始'),
                  ),
                  OutlinedButton(
                    onPressed: can ? () => notifier.send('stop') : null,
                    child: const Text('停止'),
                  ),
                  OutlinedButton(
                    onPressed: can ? () => notifier.send('off') : null,
                    child: const Text('关灯'),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _sectionLabel(context, '平滑（EMA α）'),
              const SizedBox(height: 4),
              Text(
                cfg.emaAlpha.toStringAsFixed(2),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: cfg.emaAlpha,
                min: 0.05,
                max: 1.0,
                divisions: 19,
                label: cfg.emaAlpha.toStringAsFixed(2),
                onChanged: config.setEmaAlpha,
                // 拖动中只改本地值，松手才下发，避免刷屏式发命令
                onChangeEnd: notifier.sendEmaAlpha,
              ),
              const SizedBox(height: 20),
              _sectionLabel(context, '调色方案'),
              const SizedBox(height: 10),
              SegmentedButton<ColorMode>(
                segments: const [
                  ButtonSegment(
                    value: ColorMode.a,
                    label: Text('方案 A'),
                    tooltip: '高亮度 + RGB 跟屏色',
                  ),
                  ButtonSegment(
                    value: ColorMode.b,
                    label: Text('方案 B'),
                    tooltip: '亮度跟 luma（阶段 C）',
                  ),
                ],
                selected: {cfg.mode},
                onSelectionChanged: (set) {
                  if (set.isEmpty) return;
                  config.setMode(set.first);
                  notifier.sendMode(set.first);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSolid(BuildContext context) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final can = ui.canControl;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HelperStatusBadge(phase: ui.phase, message: ui.message),
              const SizedBox(height: 28),
              _sectionLabel(context, '纯色'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
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
                    onPressed: can ? () => _pickColor(notifier) : null,
                    icon: const Icon(Icons.colorize, size: 18),
                    label: const Text('取色'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Colors.white54,
        letterSpacing: 0.6,
      ),
    );
  }
}

/// 尚未实现的模式占位面板。
class _ComingSoonPanel extends StatelessWidget {
  const _ComingSoonPanel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction, size: 36, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            '$label 还没做',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}
