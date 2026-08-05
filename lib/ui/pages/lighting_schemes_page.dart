import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../../state/lighting_scheme_tab.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/mode_tab_bar.dart';
import '../widgets/palette_color_picker.dart';
import '../widgets/segment_map_calibrator.dart';
import 'region_bbox_pick_page.dart';

/// 灯光方案页签（壳层 [ModeTabBar] 与正文共用）。
const lightingSchemeTabs = <ModeTabItem>[
  ModeTabItem(
    icon: Icons.desktop_windows_outlined,
    selectedIcon: Icons.desktop_windows,
    label: '流光溢彩',
  ),
  ModeTabItem(
    icon: Icons.flare_outlined,
    selectedIcon: Icons.flare,
    label: '屏幕氛围',
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

  static const _algoMeanLabel = '柔和融合 (推荐日常/看电影)';
  static const _algoMaxLabel = '高亮追踪 (推荐竞技/打游戏)';

  Future<void> _pickColor(HelperStateNotifier notifier) async {
    final picked = await showSolidColorPicker(context);
    if (picked == null || !mounted) return;
    notifier.sendSolid(colorToSolidHex(picked));
  }

  Future<void> _pickPalette(HelperStateNotifier notifier) async {
    final picked = await showPaletteColorPicker(context);
    if (picked == null || !mounted) return;
    notifier.sendSolid(colorToSolidHex(picked));
  }

  Future<void> _pickRegionBBox() async {
    final ui = ref.read(helperStateProvider);
    if (!ui.canControl) return;
    final box = await Navigator.of(context).push<RegionBBox?>(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) => const RegionBBoxPickPage(),
      ),
    );
    if (box == null || !mounted) return;
    ref.read(configProvider.notifier).setRegionBBox(box);
    ref.read(helperStateProvider.notifier).sendRegionBBox(box);
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(lightingSchemeTabProvider);

    return switch (tab) {
      0 => _buildScreenSync(context),
      1 => _buildScreenAmbience(context),
      2 => _buildSolid(context),
      _ => _ComingSoonPanel(label: lightingSchemeTabs[tab].label),
    };
  }

  Widget _buildScreenSync(BuildContext context) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final can = ui.canControl;
    final canEdit = can && ref.watch(configReadyProvider);

    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SchemeCard(
                title: '引擎',
                actions: [
                  FilledButton(
                    onPressed: can ? () => notifier.send('start') : null,
                    child: const Text('开始'),
                  ),
                  OutlinedButton(
                    onPressed: can ? notifier.softOff : null,
                    child: const Text('关灯'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.text),
              _SchemeCard(
                title: '映射校准',
                titleTrailing: Tooltip(
                  message:
                      '逐段点亮灯带并框选屏幕区域，\n'
                      '把每段灯珠映射到对应画面位置，\n'
                      '用于跟色采样；未校准时按顶边均分。',
                  child: Icon(
                    Icons.error_outline,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
                child: const SegmentMapCalibrator(),
              ),
              const SizedBox(height: AppSpacing.text),
              _SchemeCard(
                title: '跟色参数',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _paramLabel(
                      '颜色跟进速度: ${cfg.emaAlpha.toStringAsFixed(2)}（越大越跟手）',
                    ),
                    Slider(
                      value: cfg.emaAlpha,
                      min: 0.05,
                      max: 1.0,
                      divisions: 19,
                      label: cfg.emaAlpha.toStringAsFixed(2),
                      onChanged: canEdit ? config.setEmaAlpha : null,
                      onChangeEnd: canEdit ? notifier.sendEmaAlpha : null,
                    ),
                    const SizedBox(height: AppSpacing.control),
                    _paramLabel(
                      '画面柔化: ${cfg.blurStep}（越大越稳，0 为不柔化）',
                    ),
                    Slider(
                      value: cfg.blurStep.toDouble(),
                      min: 0,
                      max: 8,
                      divisions: 8,
                      label: '${cfg.blurStep}',
                      onChanged: canEdit
                          ? (v) => config.setBlurStep(v.round())
                          : null,
                      onChangeEnd: canEdit
                          ? (v) => notifier.sendBlur(v.round())
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.control),
                    _paramLabel(
                      '暗部过滤: ${cfg.nearBlack}（越大越忽略黑边）',
                    ),
                    Slider(
                      value: cfg.nearBlack.toDouble(),
                      min: 0,
                      max: 64,
                      divisions: 64,
                      label: '${cfg.nearBlack}',
                      onChanged: canEdit
                          ? (v) => config.setNearBlack(v.round())
                          : null,
                      onChangeEnd: canEdit
                          ? (v) => notifier.sendNearBlack(v.round())
                          : null,
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

  /// 屏幕氛围：Python region 整块取色（与流光溢彩 map 正交）。
  Widget _buildScreenAmbience(BuildContext context) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final can = ui.canControl;
    final canEdit = can && ref.watch(configReadyProvider);
    final box = cfg.regionBBox;

    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SchemeCard(
                title: '屏幕氛围',
                actions: [
                  FilledButton(
                    onPressed: can ? notifier.startRegion : null,
                    child: const Text('开始屏幕氛围'),
                  ),
                  OutlinedButton(
                    onPressed: can ? notifier.softOff : null,
                    child: const Text('关灯'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.text),
              _SchemeCard(
                title: '取色区域',
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: canEdit ? _pickRegionBBox : null,
                      icon: const Icon(Icons.content_cut, size: 18),
                      label: const Text('划定取色区域'),
                    ),
                    const Spacer(),
                    Text(
                      '尺寸: ${box.w}%×${box.h}%',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.text),
              _SchemeCard(
                title: '跟色参数',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<RegionAlgo>(
                      key: ValueKey(cfg.regionAlgo),
                      initialValue: cfg.regionAlgo,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: RegionAlgo.mean,
                          child: Text(_algoMeanLabel),
                        ),
                        DropdownMenuItem(
                          value: RegionAlgo.max,
                          child: Text(_algoMaxLabel),
                        ),
                      ],
                      onChanged: canEdit
                          ? (v) {
                              if (v == null) return;
                              config.setRegionAlgo(v);
                              notifier.sendRegionAlgo(v);
                            }
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.control),
                    _paramLabel(
                      '画面模糊/降噪程度: ${cfg.regionBlur}（0为不模糊）',
                    ),
                    Slider(
                      value: cfg.regionBlur.toDouble(),
                      min: 0,
                      max: 20,
                      divisions: 20,
                      label: '${cfg.regionBlur}',
                      onChanged: canEdit
                          ? (v) => config.setRegionBlur(v.round())
                          : null,
                      onChangeEnd: canEdit
                          ? (v) => notifier.sendRegionBlur(v.round())
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.control),
                    _paramLabel(
                      '时间过渡平滑度: ${cfg.regionSmooth.toStringAsFixed(2)}',
                    ),
                    Slider(
                      value: cfg.regionSmooth.clamp(0.0, 0.99),
                      min: 0.0,
                      max: 0.99,
                      divisions: 99,
                      label: cfg.regionSmooth.toStringAsFixed(2),
                      onChanged: canEdit ? config.setRegionSmooth : null,
                      onChangeEnd: canEdit ? notifier.sendRegionSmooth : null,
                    ),
                    const SizedBox(height: AppSpacing.control),
                    _paramLabel(
                      '暗场断电阈值: ${cfg.regionDark}',
                    ),
                    Slider(
                      value: cfg.regionDark.toDouble(),
                      min: 0,
                      max: 50,
                      divisions: 50,
                      label: '${cfg.regionDark}',
                      onChanged: canEdit
                          ? (v) => config.setRegionDark(v.round())
                          : null,
                      onChangeEnd: canEdit
                          ? (v) => notifier.sendRegionDark(v.round())
                          : null,
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

  Widget _buildSolid(BuildContext context) {
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
              _SchemeCard(
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
                      onPressed: can ? () => _pickColor(notifier) : null,
                      icon: const Icon(Icons.colorize, size: 18),
                      label: const Text('取色'),
                    ),
                    OutlinedButton.icon(
                      onPressed: can ? () => _pickPalette(notifier) : null,
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

  Widget _paramLabel(String text) {
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

/// 与主控页同款的小卡片：圆角 + 描边 + [AppTheme.cardBg]。
///
/// - 传 [actions]：标题左、操作右（同主控「连接」条）
/// - 传 [child]：标题在上、内容在下
class _SchemeCard extends StatelessWidget {
  const _SchemeCard({
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

  static const _titleStyle = TextStyle(
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
                Text(title ?? '', style: _titleStyle),
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
                Text(title!, style: _titleStyle),
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

/// 尚未实现的模式占位面板。
class _ComingSoonPanel extends StatelessWidget {
  const _ComingSoonPanel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.pageInsets,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _SchemeCard(
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
