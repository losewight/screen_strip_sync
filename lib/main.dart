import 'package:flutter/material.dart';

// 1. 就像 C++ 的 #include，把那两个页面“包含”进来
import 'ui/pages/light_control_page.dart';
import 'ui/pages/settings_page.dart';

void main() {
  runApp(const ZeerayApp());
}

class ZeerayApp extends StatelessWidget {
  const ZeerayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zeeray 氛围灯',
      theme: ThemeData.dark(),
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  // 2. 重点在这里！定义一个 Widget 数组，存放所有页面
  // 这就像 C++ 里的基类指针数组，通过索引来动态调用不同的界面实例
  final List<Widget> _pages = const [
    LightControlPage(), // 索引 0
    SettingsPage(), // 索引 1
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.lightbulb_outline),
                selectedIcon: Icon(Icons.lightbulb),
                label: Text('灯效'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('设置'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),

          // 3. 右侧内容区：直接通过 _selectedIndex 从数组中读取对应的页面渲染
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
    );
  }
}
