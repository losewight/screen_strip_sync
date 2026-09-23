import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../widgets/info_hint.dart';
import '../widgets/scheme_card.dart';
import '../widgets/segment_map_calibrator.dart';

/// 屏幕跟色：逐段 map / 顶边均分 + EMA 参数；入口命令 `start`。
class ScreenSyncPanel extends ConsumerWidget {
  const ScreenSyncPanel({super.key});

  static const _algoRmsLabel = 'RMS（偏亮，对比色更冲）';
  static const _algoMeanLabel = '算术平均（更接近光学混合）';
  static const _lumaRec601Label = 'Rec.601（绿权重大，暗绿更易剔）';
  static const _lumaMeanLabel = '(R+G+B)/3（三通道等权）';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final can = ui.canControl;
    final canEdit = ui.canConfigure && ref.watch(configReadyProvider);
    // 与 regionSmooth 同概念、极性相反：UI 平滑度 = 1 − α（α∈[0.05,1] → 平滑∈[0,0.95]）。
    final smooth = (1.0 - cfg.emaAlpha).clamp(0.0, 0.95);
    final follow = ui.followCaptureLabel(cfg.captureOutput);

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
                  title: '流光溢彩',
                  actions: [
                    // 应用中：Filled → Outlined +「停止」，点按发 stop（与旁侧「关灯」soft_off 区分）。
                    if (ui.isMapRunning)
                      OutlinedButton(
                        onPressed: can ? () => notifier.send('stop') : null,
                        child: const Text('停止'),
                      )
                    else
                      FilledButton(
                        onPressed: can ? () => notifier.send('start') : null,
                        child: const Text('开始流光溢彩'),
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
                  titleTrailing: const InfoHint(
                    message:
                        '逐段点亮灯带并框选屏幕区域，\n'
                        '把每段灯珠映射到对应画面位置，\n'
                        '用于跟色采样；未校准时按顶边均分。',
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (follow != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.text,
                          ),
                          child: Text(
                            '当前跟随 $follow',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const SegmentMapCalibrator(),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.text),
                SchemeCard(
                  title: '跟色参数',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<SampleAlgo>(
                        key: ValueKey(cfg.sampleAlgo),
                        initialValue: cfg.sampleAlgo,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: SampleAlgo.rms,
                            child: Text(_algoRmsLabel),
                          ),
                          DropdownMenuItem(
                            value: SampleAlgo.mean,
                            child: Text(_algoMeanLabel),
                          ),
                        ],
                        onChanged: canEdit
                            ? (v) {
                                if (v == null) return;
                                config.setSampleAlgo(v);
                                notifier.sendSampleAlgo(v);
                              }
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.control),
                      DropdownButtonFormField<NearBlackLuma>(
                        key: ValueKey(cfg.nearBlackLuma),
                        initialValue: cfg.nearBlackLuma,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          labelText: '暗部亮度算法',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: NearBlackLuma.rec601,
                            child: Text(_lumaRec601Label),
                          ),
                          DropdownMenuItem(
                            value: NearBlackLuma.mean,
                            child: Text(_lumaMeanLabel),
                          ),
                        ],
                        onChanged: canEdit
                            ? (v) {
                                if (v == null) return;
                                config.setNearBlackLuma(v);
                                notifier.sendNearBlackLuma(v);
                              }
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.control),
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
                        '色彩饱和度: ${(cfg.saturation * 100).round()}%'
                        '（100%=原色，越高越艳）',
                      ),
                      Slider(
                        value: cfg.saturation.clamp(0.5, 2.0),
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        label: '${(cfg.saturation * 100).round()}%',
                        onChanged: canEdit
                            ? (v) => config.setSaturation(v)
                            : null,
                        onChangeEnd: canEdit
                            ? (v) => notifier.sendSaturation(v)
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
