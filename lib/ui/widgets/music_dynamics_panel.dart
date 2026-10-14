import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import 'info_hint.dart';
import 'scheme_card.dart';
import 'win11_segmented_control.dart';

/// 音乐动态音频来源（UI 先落地；尚未写入 helper 配置）。
enum MusicPickupSource {
  speaker,
  microphone,
  both,
}

extension on MusicPickupSource {
  String get label => switch (this) {
    MusicPickupSource.speaker => '系统声音',
    MusicPickupSource.microphone => '麦克风',
    MusicPickupSource.both => '系统声音 + 麦克风',
  };
}

/// 音乐动态灯光模式（UI 先落地；尚未写入 helper 配置）。
enum MusicLightMode {
  /// 从一端向另一端按电平逐段点亮。
  startToEnd,

  /// 左右两半镜像点亮。
  dualMirror,
}

extension on MusicLightMode {
  String get label => switch (this) {
    MusicLightMode.startToEnd => '从头到尾',
    MusicLightMode.dualMirror => '双条镜像',
  };
}

/// 音乐动态面板（控灯入口尚未接入，顶栏小卡先与其它方案对齐）。
class MusicDynamicsPanel extends ConsumerStatefulWidget {
  const MusicDynamicsPanel({super.key});

  @override
  ConsumerState<MusicDynamicsPanel> createState() => _MusicDynamicsPanelState();
}

class _MusicDynamicsPanelState extends ConsumerState<MusicDynamicsPanel> {
  MusicPickupSource _pickup = MusicPickupSource.speaker;
  MusicLightMode _lightMode = MusicLightMode.startToEnd;

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(helperStateProvider);
    final notifier = ref.read(helperStateProvider.notifier);
    final cfg = ref.watch(configProvider);
    final can = ui.canControl;
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
                  title: '音乐动态',
                  actions: [
                    FilledButton(
                      // 后端未接：按钮先占位，保持与其它方案同款布局。
                      onPressed: null,
                      child: const Text('开始音乐动态'),
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
                      // UI 占位：校准 / 编辑入口尚未接入音乐动态。
                      Text(
                        cfg.hasSegmentMap
                            ? '已校准自定义映射（10 段）'
                            : '未校准：使用顶边均分默认',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
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
                            label: Text(
                              cfg.hasSegmentMap ? '重新矫正' : '开始校准',
                            ),
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
                ),
                const SizedBox(height: AppSpacing.text),
                SchemeCard(
                  title: '音频来源',
                  child: DropdownButtonFormField<MusicPickupSource>(
                    key: ValueKey(_pickup),
                    initialValue: _pickup,
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
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _pickup = v);
                    },
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
                  child: Win11SegmentedControl<MusicLightMode>(
                    segments: [
                      for (final mode in MusicLightMode.values)
                        Win11Segment(value: mode, label: mode.label),
                    ],
                    selected: _lightMode,
                    onChanged: (mode) => setState(() => _lightMode = mode),
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
