import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../state/helper_state.dart';
import 'scheme_card.dart';

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

/// 音乐动态面板（控灯入口尚未接入，顶栏小卡先与其它方案对齐）。
class MusicDynamicsPanel extends ConsumerStatefulWidget {
  const MusicDynamicsPanel({super.key});

  @override
  ConsumerState<MusicDynamicsPanel> createState() => _MusicDynamicsPanelState();
}

class _MusicDynamicsPanelState extends ConsumerState<MusicDynamicsPanel> {
  MusicPickupSource _pickup = MusicPickupSource.speaker;

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
