import 'dart:io';

import 'package:flutter/material.dart';

void main() {
  runApp(const ZeerayApp());
}

class ZeerayApp extends StatelessWidget {
  const ZeerayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Zeeray App',
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 存在 State 里：关掉页面前一直留着，不会每次按钮新建
  Process? _proc;
  Socket? _sock;
  bool _ready = false;
  String _status = '先点「连接」';

  // 「连接」按钮：只做一次 —— 启动 helper + 连 Socket，不关闭
  Future<void> _connect() async {
    if (_ready) return; // 已连过就别再开第二个 helper
    setState(() => _status = '启动 helper…');
    try {
      _proc = await Process.start(
        r'D:\Project\zeeray_ambilight\cpp_core\build\Release\helper.exe',
        [],
      );
      await Future.delayed(const Duration(milliseconds: 300));

      setState(() => _status = '连接中…');
      _sock = await Socket.connect(
        InternetAddress.loopbackIPv4,
        9527,
        timeout: const Duration(seconds: 3),
      );
      // 等 helper 开串口、握手完
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _ready = true;
        _status = '已连接，可以点下面按钮';
      });
    } catch (e) {
      setState(() => _status = '失败: $e');
    }
  }

  // 「红 / 开始 / 停止」：只往已经打开的 Socket 写一行，不关连接
  void _send(String cmd) {
    if (!_ready || _sock == null) {
      setState(() => _status = '请先点「连接」');
      return;
    }
    _sock!.write('$cmd\n');
    setState(() => _status = '已发: $cmd');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Day 17 · Socket 常驻')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _ready ? null : _connect, // 连上后灰掉
              child: const Text('连接'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _ready ? () => _send('solid ff0000') : null,
              child: const Text('红'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _ready ? () => _send('start') : null,
              child: const Text('开始'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _ready ? () => _send('stop') : null,
              child: const Text('停止'),
            ),
          ],
        ),
      ),
    );
  }
}
