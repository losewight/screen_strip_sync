import 'package:flutter/material.dart';

// 定义系统设置页面类
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 以后你的 COM 端口选择、波特率显示、抓屏帧率设置，全都在这里组装
    return const Center(
      child: Text(
        '【系统设置页】\n\n我也是从独立文件加载出来的',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20),
      ),
    );
  }
}
