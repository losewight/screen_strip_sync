import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../widgets/scheme_card.dart';
import '../widgets/segment_map_calibrator.dart';

/// 流光溢彩：逐段 map / 顶边均分 + EMA 参数；入口命令 `start`。
class ScreenSyncPanel extends ConsumerWidget {
  const ScreenSyncPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final can = ui.canControl;
    final canEdit = can && ref.watch(configReadyProvider);
    // 与 regionSmooth 同概念、极性相反：UI 平滑度 = 1 − α（α∈[0.05,1] → 平滑∈[0,0.95]）。
    final smooth = (1.0 - cfg.emaAlpha).clamp(0.0, 0.95);

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
                  title: '流光溢彩引擎',
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
                SchemeCard(
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
                SchemeCard(
                  title: '跟色参数',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SchemeParamLabel(
                        '时间过渡平滑度: ${smooth.toStringAsFixed(2)}',
                      ),
                      Slider(
                        value: smooth,
                        min: 0.0,
                        max: 0.95,
                        divisions: 19,
                        label: smooth.toStringAsFixed(2),
                        onChanged: canEdit
                            ? (v) => config.setEmaAlpha(1.0 - v)
                            : null,
                        onChangeEnd: canEdit
                            ? (v) => notifier.sendEmaAlpha(1.0 - v)
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.control),
                      SchemeParamLabel(
                        '画面模糊/降噪程度: ${cfg.blurStep}（0为不模糊）',
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
                      SchemeParamLabel(
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
      ),
    );
  }
}
