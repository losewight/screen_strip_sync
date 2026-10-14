import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../ipc/helper_status.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import 'color_swatch_button.dart';
import 'info_hint.dart';
import 'music_mirror_calibrator.dart';
import 'palette_color_picker.dart';
import 'scheme_card.dart';
import 'win11_segmented_control.dart';
import 'win11_switch.dart';

/// 音乐动态面板：开始 / 停止与参数下发走 helper IPC。
class MusicDynamicsPanel extends ConsumerWidget {
  const MusicDynamicsPanel({super.key});

  static const _defaultMusicColor = Color(0xFF00AAFF);

  Future<void> _pickMusicColor(
    BuildContext context,
    AppConfig cfg,
    ConfigNotifier config,
    HelperStateNotifier notifier,
  ) async {
    final initial =
        colorFromSolidHex(cfg.musicColor) ?? _defaultMusicColor;
    final picked = await showPaletteColorPicker(
      context,
      initial: initial,
      title: '自选单色',
    );
    if (picked == null || !context.mounted) return;
    final hex = colorToSolidHex(picked);
    if (hex == '000000') return;
    config.setMusicColor(hex);
    notifier.sendMusicColor(hex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfg = ref.watch(configProvider);
    final config = ref.read(configProvider.notifier);
    final can = ui.canControl;
    final canEdit = ui.canConfigure && ref.watch(configReadyProvider);
    final mirrorNeedsCalibrate = cfg.musicLayout == MusicLightMode.dualMirror &&
        !cfg.musicMirror.isValid;
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
                            : const MusicMirrorCalibrator(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.text),
                SchemeCard(
                  title: '配色',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<MusicPalette>(
                        key: ValueKey(cfg.musicPalette),
                        initialValue: cfg.musicPalette,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final palette in MusicPalette.values)
                            DropdownMenuItem(
                              value: palette,
                              child: Text(palette.label),
                            ),
                        ],
                        onChanged: canEdit
                            ? (v) {
                                if (v == null) return;
                                config.setMusicPalette(v);
                                notifier.sendMusicPalette(v);
                              }
                            : null,
                      ),
                      if (cfg.musicPalette == MusicPalette.fixed) ...[
                        const SizedBox(height: AppSpacing.text),
                        Row(
                          children: [
                            const Expanded(child: SchemeParamLabel('颜色')),
                            ColorSwatchButton(
                              color: colorFromSolidHex(cfg.musicColor) ??
                                  _defaultMusicColor,
                              enabled: canEdit,
                              outlined: true,
                              tooltip: '自选单色',
                              onPressed: () => _pickMusicColor(
                                context,
                                cfg,
                                config,
                                notifier,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (cfg.musicPalette == MusicPalette.screen)
                        const Padding(
                          padding: EdgeInsets.only(top: AppSpacing.text),
                          child: Row(
                            children: [
                              InfoHint(
                                message:
                                    '会同时抓屏，帧率略降；颜色来自流光溢彩的段映射',
                              ),
                              SizedBox(width: AppSpacing.compact),
                              Expanded(
                                child: Text(
                                  '会同时抓屏，帧率略降；颜色来自流光溢彩的段映射',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontFamily,
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppSpacing.text),
                      _MusicPalettePreview(
                        palette: cfg.musicPalette,
                        fixedHex: cfg.musicColor,
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

/// 满电平 10 格静态预览（Screen 用 Vu 占位）。
class _MusicPalettePreview extends StatelessWidget {
  const _MusicPalettePreview({
    required this.palette,
    required this.fixedHex,
  });

  final MusicPalette palette;
  final String fixedHex;

  @override
  Widget build(BuildContext context) {
    final colors = musicPalettePreviewColors(palette, fixedHex: fixedHex);
    return SizedBox(
      height: 14,
      child: Row(
        children: [
          for (var i = 0; i < colors.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.fromARGB(
                    255,
                    colors[i].r,
                    colors[i].g,
                    colors[i].b,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
