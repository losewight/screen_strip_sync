import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../pages/region_bbox_pick_page.dart';
import 'scheme_card.dart';

/// 屏幕氛围：整块 bbox 切 10 段；入口命令 `start_region`。
class ScreenAmbiencePanel extends ConsumerWidget {
  const ScreenAmbiencePanel({super.key});

  static const _algoMeanLabel = '柔和融合 (推荐日常/看电影)';
  static const _algoMaxLabel = '高亮追踪 (推荐竞技/打游戏)';

  Future<void> _pickRegionBBox(BuildContext context, WidgetRef ref) async {
    final ui = ref.read(helperStateProvider);
    if (!ui.canControl) return;
    final box = await Navigator.of(context).push<RegionBBox?>(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) => const RegionBBoxPickPage(),
      ),
    );
    if (box == null || !context.mounted) return;
    ref.read(configProvider.notifier).setRegionBBox(box);
    ref.read(helperStateProvider.notifier).sendRegionBBox(box);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              SchemeCard(
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
              SchemeCard(
                title: '取色区域',
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: canEdit
                          ? () => _pickRegionBBox(context, ref)
                          : null,
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
              SchemeCard(
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
                    SchemeParamLabel(
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
                    SchemeParamLabel(
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
                    SchemeParamLabel('暗场断电阈值: ${cfg.regionDark}'),
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
}
