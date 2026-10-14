import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
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
    final can = ui.canControl;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Win11SegmentedControl<MusicLightMode>(
                        segments: [
                          for (final mode in MusicLightMode.values)
                            Win11Segment(value: mode, label: mode.label),
                        ],
                        selected: _lightMode,
                        onChanged: (mode) =>
                            setState(() => _lightMode = mode),
                      ),
                      AnimatedSize(
                        duration: AppTheme.navDuration,
                        curve: AppTheme.navCurve,
                        alignment: Alignment.topCenter,
                        child: _lightMode == MusicLightMode.dualMirror
                            ? const _DualMirrorCalibratePanel()
                            : const SizedBox.shrink(),
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

/// 双条镜像下展开的个人矫正区（校准入口尚未接入）。
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
