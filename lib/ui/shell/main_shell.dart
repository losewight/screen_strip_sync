import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../state/helper_state.dart';
import '../../state/lighting_scheme_tab.dart';
import '../pages/control_page.dart';
import '../pages/lighting_schemes_page.dart';
import '../pages/settings_page.dart';
import '../widgets/mode_tab_bar.dart';
import '../widgets/store_sidebar.dart';
import '../widgets/store_title_bar.dart';
import '../widgets/strip_progress_bar.dart';
import '../widgets/strip_status_bar.dart';

/// 顶栏 + 侧栏 + 内容区。进度条单实例挂壳层，切页不重建。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  static const _pages = [
    ControlPage(),
    LightingSchemesPage(),
    SettingsPage(),
  ];

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(helperStateProvider).phase;
    final lightingTab = ref.watch(lightingSchemeTabProvider);

    return Scaffold(
      backgroundColor: AppTheme.contentBg,
      body: Column(
        children: [
          const StoreTitleBar(),
          Expanded(
            child: Row(
              children: [
                StoreSidebar(
                  selectedIndex: _index,
                  onSelected: _select,
                  items: const [
                    StoreNavItem(
                      icon: Icons.lightbulb_outline,
                      selectedIcon: Icons.lightbulb,
                      label: '主控',
                    ),
                    StoreNavItem(
                      icon: Icons.style_outlined,
                      selectedIcon: Icons.style,
                      label: '灯光方案',
                    ),
                    StoreNavItem(
                      icon: Icons.settings_outlined,
                      selectedIcon: Icons.settings,
                      label: '软件设置',
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    children: [
                      if (_index == 0)
                        StripStatusBar(phase: phase)
                      else if (_index == 1)
                        ModeTabBar(
                          items: lightingSchemeTabs,
                          selectedIndex: lightingTab,
                          onSelected: ref
                              .read(lightingSchemeTabProvider.notifier)
                              .select,
                        ),
                      StripProgressBar(
                        key: const ValueKey('shell-strip-progress'),
                        phase: phase,
                      ),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            for (var i = 0; i < _pages.length; i++)
                              Offstage(
                                offstage: _index != i,
                                child: TickerMode(
                                  enabled: _index == i,
                                  child: _pages[i],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
