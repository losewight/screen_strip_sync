import 'package:flutter/material.dart';

// 定义灯效控制页面类
class LightControlPage extends StatelessWidget {
  const LightControlPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 以后你的毛玻璃滑块、模式切换按钮，全都在这里组装
    return const Center(
      child: Text(
        '【灯效控制页】\n\n我是从独立文件加载出来的',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20),
      ),
    );
  }
}
