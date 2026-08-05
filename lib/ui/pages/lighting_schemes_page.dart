import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/lighting_scheme_tab.dart';
import '../widgets/mode_tab_bar.dart';
import '../widgets/scheme_card.dart';
import '../widgets/screen_ambience_panel.dart';
import '../widgets/screen_sync_panel.dart';
import '../widgets/solid_scheme_panel.dart';

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

/// 灯光方案：按页签分派到独立面板；顶栏与进度条由壳层统一渲染。
class LightingSchemesPage extends ConsumerWidget {
  const LightingSchemesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(lightingSchemeTabProvider);

    return switch (tab) {
      0 => const ScreenSyncPanel(),
      1 => const ScreenAmbiencePanel(),
      2 => const SolidSchemePanel(),
      _ => SchemeComingSoonPanel(label: lightingSchemeTabs[tab].label),
    };
  }
}
