import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../../state/lighting_scheme_tab.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/helper_status_badge.dart';
import '../widgets/mode_tab_bar.dart';
import '../widgets/segment_map_calibrator.dart';

/// 灯光方案页签（壳层 [ModeTabBar] 与正文共用）。
const lightingSchemeTabs = <ModeTabItem>[
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

/// 灯光方案：模式面板；顶栏与进度条由壳层统一渲染。
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

  Future<void> _pickColor(HelperStateNotifier notifier) async {
    final picked = await showSolidColorPicker(context);
    if (picked == null || !mounted) return;
    notifier.sendSolid(colorToSolidHex(picked));
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(lightingSchemeTabProvider);

    return switch (tab) {
      0 => _buildScreenSync(context),
      1 => _buildSolid(context),
      _ => _ComingSoonPanel(label: lightingSchemeTabs[tab].label),
    };
  }

  Widget _buildScreenSync(BuildContext context) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final can = ui.canControl;

    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HelperStatusBadge(
                phase: ui.phase,
                message: ui.message,
                ipcLine: ui.ipcLine,
              ),
              const SizedBox(height: AppSpacing.pageSection),
              _sectionLabel(context, '引擎'),
              const SizedBox(height: AppSpacing.text),
              Wrap(
                spacing: AppSpacing.text,
                runSpacing: AppSpacing.text,
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
                    onPressed: can ? notifier.softOff : null,
                    child: const Text('关灯'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.pageSection),
              _sectionLabel(context, '映射校准'),
              const SizedBox(height: AppSpacing.text),
              const SegmentMapCalibrator(),
              const SizedBox(height: AppSpacing.pageSection),
              _sectionLabel(
                context,
                '颜色跟进速度: ${cfg.emaAlpha.toStringAsFixed(2)}（越大越跟手）',
              ),
              Slider(
                value: cfg.emaAlpha,
                min: 0.05,
                max: 1.0,
                divisions: 19,
                label: cfg.emaAlpha.toStringAsFixed(2),
                onChanged: config.setEmaAlpha,
                onChangeEnd: notifier.sendEmaAlpha,
              ),
              const SizedBox(height: AppSpacing.section),
              _sectionLabel(
                context,
                '画面柔化: ${cfg.blurStep}（越大越稳，0 为不柔化）',
              ),
              Slider(
                value: cfg.blurStep.toDouble(),
                min: 0,
                max: 8,
                divisions: 8,
                label: '${cfg.blurStep}',
                onChanged: (v) => config.setBlurStep(v.round()),
                onChangeEnd: (v) => notifier.sendBlur(v.round()),
              ),
              const SizedBox(height: AppSpacing.section),
              _sectionLabel(
                context,
                '暗部过滤: ${cfg.nearBlack}（越大越忽略黑边）',
              ),
              Slider(
                value: cfg.nearBlack.toDouble(),
                min: 0,
                max: 64,
                divisions: 64,
                label: '${cfg.nearBlack}',
                onChanged: (v) => config.setNearBlack(v.round()),
                onChangeEnd: (v) => notifier.sendNearBlack(v.round()),
              ),
              const SizedBox(height: AppSpacing.section),
              _sectionLabel(context, '调色方案'),
              const SizedBox(height: AppSpacing.text),
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
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HelperStatusBadge(
                phase: ui.phase,
                message: ui.message,
                ipcLine: ui.ipcLine,
              ),
              const SizedBox(height: AppSpacing.pageSection),
              _sectionLabel(context, '纯色'),
              const SizedBox(height: AppSpacing.text),
              Wrap(
                spacing: AppSpacing.text,
                runSpacing: AppSpacing.text,
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
          const Icon(
            Icons.construction,
            size: AppSpacing.page,
            color: Colors.white24,
          ),
          const SizedBox(height: AppSpacing.text),
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
