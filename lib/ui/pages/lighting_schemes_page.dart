import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/lighting_scheme_tab.dart';
import '../widgets/mode_tab_bar.dart';
import '../widgets/music_dynamics_panel.dart';
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
    icon: Icons.graphic_eq,
    selectedIcon: Icons.graphic_eq,
    label: '音乐动态',
  ),
  ModeTabItem(
    icon: Icons.palette_outlined,
    selectedIcon: Icons.palette,
    label: '纯色模式',
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
      2 => const MusicDynamicsPanel(),
      3 => const SolidSchemePanel(),
      _ => const SizedBox.shrink(),
    };
  }
}
