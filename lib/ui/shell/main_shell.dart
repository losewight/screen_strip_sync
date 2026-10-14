import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../state/helper_state.dart';
import '../../state/lighting_scheme_tab.dart';
import '../../state/update_check_state.dart';
import '../pages/control_page.dart';
import '../pages/lighting_schemes_page.dart';
import '../pages/settings_page.dart';
import '../widgets/helper_phase_style.dart';
import '../widgets/mode_tab_bar.dart';
import '../widgets/store_sidebar.dart';
import '../widgets/store_title_bar.dart';
import '../widgets/strip_progress_bar.dart';
import '../widgets/strip_status_bar.dart';
import '../widgets/win_ui_slide_switcher.dart';

/// 顶栏 + 侧栏 + 内容区。进度条单实例挂壳层，切页不重建。
///
/// 首帧即出主控；cfg 未到时各页靠 canConfigure / canControl 灰显控件，
/// 静默连 helper，不对用户暴露双进程细节。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  /// 顶栏内容索引；进设置时保持离开前的页，避免收起过程中串页。
  int _chromeIndex = 0;

  static const _pages = [
    ControlPage(),
    LightingSchemesPage(),
    SettingsPage(),
  ];

  static const _settingsIndex = 2;

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      if (i != _settingsIndex) _chromeIndex = i;
    });
    // 一切到软件设置就消侧栏圆点（每个远端版本只提醒一次）。
    if (i == _settingsIndex) {
      ref.read(updateCheckProvider.notifier).acknowledgeBadge();
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(helperStateProvider).phase;
    final phaseStyle = HelperPhaseStyle.of(phase);
    final lightingTab = ref.watch(lightingSchemeTabProvider);
    final showUpdateBadge = ref.watch(updateCheckProvider).showBadge;

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
                  items: [
                    const StoreNavItem(
                      icon: Icons.lightbulb_outline,
                      selectedIcon: Icons.lightbulb,
                      label: '主控',
                    ),
                    const StoreNavItem(
                      icon: Icons.style_outlined,
                      selectedIcon: Icons.style,
                      label: '灯光方案',
                    ),
                    StoreNavItem(
                      icon: Icons.settings_outlined,
                      selectedIcon: Icons.settings,
                      label: '软件设置',
                      showBadge: showUpdateBadge,
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    children: [
                      // 与页切同时长收展顶栏，避免进设置时内容区高度骤变。
                      _CollapseHeight(
                        visible: _index != _settingsIndex,
                        child: SizedBox(
                          height: ModeTabBar.height,
                          child: _chromeIndex == 0
                              ? StripStatusBar(phase: phase)
                              : ModeTabBar(
                                  items: lightingSchemeTabs,
                                  selectedIndex: lightingTab,
                                  onSelected: ref
                                      .read(lightingSchemeTabProvider.notifier)
                                      .select,
                                  trailing: StripStatusPill(
                                    color: phaseStyle.accent,
                                    label: phaseStyle.label,
                                  ),
                                ),
                        ),
                      ),
                      // 进度条单实例保留；高度收起，不 Offstage 卸树。
                      _CollapseHeight(
                        visible: _index != _settingsIndex,
                        child: TickerMode(
                          enabled: _index != _settingsIndex,
                          child: SizedBox(
                            height: StripProgressBar.height,
                            child: StripProgressBar(
                              key: const ValueKey('shell-strip-progress'),
                              phase: phase,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: WinUiSlideIndexedStack(
                          index: _index,
                          axis: Axis.vertical,
                          children: _pages,
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

/// 用 [Align.heightFactor] 收展，避免把固定高度子组件硬压成 0 约束。
class _CollapseHeight extends StatelessWidget {
  const _CollapseHeight({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: AppTheme.pageTransitionDuration,
      curve: AppTheme.pageTransitionCurve,
      tween: Tween<double>(end: visible ? 1 : 0),
      builder: (context, factor, child) {
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: factor,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
