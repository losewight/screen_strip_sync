import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../pages/control_page.dart';
import '../pages/lighting_schemes_page.dart';
import '../pages/settings_page.dart';
import '../widgets/store_sidebar.dart';
import '../widgets/store_title_bar.dart';

/// 顶栏 + 侧栏 + 内容区。Offstage 保活各页状态。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
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
                  // 即时切换；Offstage 保留各页 State（灯光方案取色 / 设置控件）
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
    );
  }
}
