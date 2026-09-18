import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../state/config_state.dart';
import '../../state/helper_state.dart';
import '../../state/lighting_scheme_tab.dart';
import '../pages/control_page.dart';
import '../pages/lighting_schemes_page.dart';
import '../pages/settings_page.dart';
import '../widgets/helper_phase_style.dart';
import '../widgets/mode_tab_bar.dart';
import '../widgets/store_sidebar.dart';
import '../widgets/store_title_bar.dart';
import '../widgets/strip_progress_bar.dart';
import '../widgets/strip_status_bar.dart';

/// 顶栏 + 侧栏 + 内容区。进度条单实例挂壳层，切页不重建。
///
/// 首帧等 helper `cfg end`：未就绪时 loading，超时显示「后台服务未运行」+ 启动。
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
    final cfgReady = ref.watch(configReadyProvider);
    final snapshotTimedOut = ref.watch(
      helperStateProvider.select((s) => s.snapshotTimedOut),
    );

    if (!cfgReady) {
      return Scaffold(
        backgroundColor: AppTheme.contentBg,
        body: Column(
          children: [
            const StoreTitleBar(),
            Expanded(
              child: snapshotTimedOut
                  ? _SnapshotUnresponsive(
                      onRetry: () =>
                          ref.read(helperStateProvider.notifier).retrySnapshot(),
                    )
                  : const _SnapshotLoading(),
            ),
          ],
        ),
      );
    }

    final phase = ref.watch(helperStateProvider).phase;
    final phaseStyle = HelperPhaseStyle.of(phase);
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
                          trailing: StripStatusPill(
                            color: phaseStyle.accent,
                            label: phaseStyle.label,
                          ),
                        ),
                      // 软件设置无顶栏，进度条一并藏起；Offstage 保单实例状态
                      Offstage(
                        offstage: _index == 2,
                        child: TickerMode(
                          enabled: _index != 2,
                          child: StripProgressBar(
                            key: const ValueKey('shell-strip-progress'),
                            phase: phase,
                          ),
                        ),
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

class _SnapshotLoading extends StatelessWidget {
  const _SnapshotLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: AppSpacing.text),
          Text(
            '正在连接后台服务…',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotUnresponsive extends StatefulWidget {
  const _SnapshotUnresponsive({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  State<_SnapshotUnresponsive> createState() => _SnapshotUnresponsiveState();
}

class _SnapshotUnresponsiveState extends State<_SnapshotUnresponsive> {
  static const _retryGap = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    unawaited(_autoRetryLoop());
  }

  Future<void> _autoRetryLoop() async {
    while (mounted) {
      await widget.onRetry();
      if (!mounted) return;
      await Future<void>.delayed(_retryGap);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: AppSpacing.pageInsets,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.desktop_access_disabled,
                size: 40,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(height: AppSpacing.text),
              const Text(
                '后台服务未运行',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.compact),
              const Text(
                '灯光由本机托盘程序控制。正在自动尝试启动，也可以点下面按钮。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              FilledButton(
                onPressed: () => unawaited(widget.onRetry()),
                child: const Text('启动后台服务'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
