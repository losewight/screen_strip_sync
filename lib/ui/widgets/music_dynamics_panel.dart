import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../ipc/helper_status.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import 'info_hint.dart';
import 'scheme_card.dart';
import 'win11_segmented_control.dart';
import 'win11_switch.dart';

/// 音乐动态面板：开始 / 停止与参数下发走 helper IPC。
class MusicDynamicsPanel extends ConsumerWidget {
  const MusicDynamicsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final can = ui.canControl;
    final canEdit = ui.canConfigure && ref.watch(configReadyProvider);
    // P2：尚无镜像校准字段；选双条镜像时视为未矫正，禁用开始。
    final mirrorNeedsCalibrate =
        cfg.musicLayout == MusicLightMode.dualMirror;
    final canStart = can && !mirrorNeedsCalibrate;

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
                  title: '音乐动态',
                  actions: [
                    if (ui.isMusicRunning)
                      OutlinedButton(
                        onPressed: can ? () => notifier.send('stop') : null,
                        child: const Text('停止'),
                      )
                    else
                      FilledButton(
                        onPressed: canStart ? notifier.startMusic : null,
                        child: const Text('开始音乐动态'),
                      ),
                    OutlinedButton(
                      onPressed: can ? notifier.softOff : null,
                      child: const Text('关灯'),
                    ),
                  ],
                ),
                if (mirrorNeedsCalibrate && !ui.isMusicRunning)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.compact),
                    child: Text(
                      '未矫正：请先完成个人矫正后再开始',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.text),
                SchemeCard(
                  title: '音频来源',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<MusicPickupSource>(
                        key: ValueKey(cfg.musicSource),
                        initialValue: cfg.musicSource,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final source in MusicPickupSource.values)
                            DropdownMenuItem(
                              value: source,
                              child: Text(source.label),
                            ),
                        ],
                        onChanged: canEdit
                            ? (v) {
                                if (v == null) return;
                                config.setMusicSource(v);
                                notifier.sendMusicSource(v);
                              }
                            : null,
                      ),
                      if (ui.musicAudio == HelperMusicAudioStatus.denied)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.text),
                          child: Text(
                            '麦克风权限被系统禁用',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      else if (ui.musicAudio ==
                          HelperMusicAudioStatus.noDevice)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.text),
                          child: Text(
                            '未找到音频设备',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.text),
                SchemeCard(
                  title: '灯光模式',
                  titleTrailing: const InfoHint(
                    message:
                        '按音量电平点亮灯段的排布方式。\n'
                        '从头到尾：从一端向另一端逐段点亮。\n'
                        '双条镜像：左右两边对称点亮（需要个人矫正）。',
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Win11SegmentedControl<MusicLightMode>(
                        segments: [
                          for (final mode in MusicLightMode.values)
                            Win11Segment(value: mode, label: mode.label),
                        ],
                        selected: cfg.musicLayout,
                        onChanged: (mode) {
                          if (!canEdit) return;
                          config.setMusicLayout(mode);
                          notifier.sendMusicLayout(mode);
                        },
                      ),
                      AnimatedSize(
                        duration: AppTheme.navDuration,
                        curve: AppTheme.navCurve,
                        alignment: Alignment.topCenter,
                        child: cfg.musicLayout == MusicLightMode.startToEnd
                            ? Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.text,
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: SchemeParamLabel('反向'),
                                    ),
                                    Win11Switch(
                                      value: cfg.musicReverse,
                                      onChanged: canEdit
                                          ? (v) {
                                              config.setMusicReverse(v);
                                              notifier.sendMusicReverse(v);
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              )
                            : const _DualMirrorCalibratePanel(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.text),
                SchemeCard(
                  title: '效果',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SchemeParamLabel('灵敏度: ${cfg.musicSensitivity}'),
                      Slider(
                        value: cfg.musicSensitivity.toDouble().clamp(0, 100),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: '${cfg.musicSensitivity}',
                        onChanged: canEdit
                            ? (v) => config.setMusicSensitivity(v.round())
                            : null,
                        onChangeEnd: canEdit
                            ? (v) =>
                                  notifier.sendMusicSensitivity(v.round())
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.control),
                      SchemeParamLabel('回落速度: ${cfg.musicDecay}'),
                      Slider(
                        value: cfg.musicDecay.toDouble().clamp(0, 100),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: '${cfg.musicDecay}',
                        onChanged: canEdit
                            ? (v) => config.setMusicDecay(v.round())
                            : null,
                        onChangeEnd: canEdit
                            ? (v) => notifier.sendMusicDecay(v.round())
                            : null,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '慢',
                              style: TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            Text(
                              '快',
                              style: TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.control),
                      Row(
                        children: [
                          const Expanded(child: SchemeParamLabel('静音表现')),
                          const InfoHint(
                            message:
                                '没有可听电平时灯带怎么显示。\n'
                                '全灭：静音时所有灯段熄灭。\n'
                                '保留最低一格：静音时仍点亮最低一档，避免完全暗掉。',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.compact),
                      Win11SegmentedControl<MusicSilence>(
                        segments: [
                          for (final s in MusicSilence.values)
                            Win11Segment(value: s, label: s.label),
                        ],
                        selected: cfg.musicSilence,
                        onChanged: (s) {
                          if (!canEdit) return;
                          config.setMusicSilence(s);
                          notifier.sendMusicSilence(s);
                        },
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

/// 双条镜像下展开的个人矫正区（P3 再接校准入口）。
class _DualMirrorCalibratePanel extends StatelessWidget {
  const _DualMirrorCalibratePanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.text),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '未矫正：请先完成个人矫正',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(width: 4),
              const InfoHint(
                icon: Icons.help_outline,
                message:
                    '双条镜像需要知道灯带左右分界，才能对称点亮。\n'
                    '完成个人矫正后，即可按音量从中间向两侧展开。',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.text),
          Wrap(
            spacing: AppSpacing.text,
            runSpacing: AppSpacing.text,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.center_focus_strong, size: 18),
                label: const Text('开始校准'),
              ),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑现有矫正框'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
