import 'dart:convert';
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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // 存在 State 里：关掉页面前一直留着，不会每次按钮新建
  Process? _proc;
  Socket? _sock;
  bool _ready = false;
  bool _engineWanted = false; // 唤醒后是否自动 start
  bool _resumeBusy = false;
  String _status = '先点「连接」';
  final StringBuffer _rxBuf = StringBuffer();

  @override
  void initState() {
    super.initState();
    // 为什么：休眠唤醒走 AppLifecycleState.resumed，对应旧版电源恢复后拉起
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 为什么：从未连过就别自动起 helper；只恢复「用过 / 要跑引擎」的会话
      if (_proc != null || _engineWanted || _ready) {
        _robustAutoStart();
      }
    }
  }

  // 为什么：等 USB/串口驱动恢复；失败则 2s 后重试，对齐旧版 robust_auto_start
  Future<void> _robustAutoStart() async {
    if (_resumeBusy) return;
    _resumeBusy = true;
    try {
      if (!mounted) return;
      setState(() => _status = '系统唤醒，3 秒后重连…');
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      await _teardownIpc(killHelper: true);

      const maxAttempts = 5;
      for (int left = maxAttempts; left >= 1; --left) {
        if (!mounted) return;
        await _connect();
        if (_ready) {
          if (_engineWanted) {
            _send('start');
          }
          return;
        }
        if (left > 1) {
          setState(() => _status = '重连失败，2 秒后重试（剩 ${left - 1}）…');
          await Future.delayed(const Duration(seconds: 2));
        }
      }
      if (mounted) {
        setState(() => _status = '唤醒后重连失败，请手动点「连接」');
      }
    } finally {
      _resumeBusy = false;
    }
  }

  Future<void> _teardownIpc({required bool killHelper}) async {
    if (_sock != null) {
      try {
        _sock!.destroy();
      } catch (_) {}
      _sock = null;
    }
    _ready = false;
    _rxBuf.clear();

    if (killHelper && _proc != null) {
      // 为什么：休眠后旧 helper 可能仍占 9527/COM，必须杀掉再起新进程
      try {
        _proc!.kill();
      } catch (_) {}
      _proc = null;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // 「连接」按钮：只做一次 —— 启动 helper + 连 Socket，不关闭
  Future<void> _connect() async {
    if (_ready) return; // 已连过就别再开第二个 helper

    // 为什么：唤醒重连或重复点连接时，先清半死进程，避免双 PID / 内存翻倍
    if (_proc != null) {
      final stillRunning = -1;
      final exitCode = await _proc!.exitCode.timeout(
        Duration.zero,
        onTimeout: () => stillRunning,
      );
      if (exitCode == stillRunning) {
        await _teardownIpc(killHelper: true);
      } else {
        _proc = null;
      }
    }

    setState(() => _status = '启动 helper…');
    try {
      _proc = await Process.start(
        r'D:\Project\zeeray_ambilight\cpp_core\build\Release\helper.exe',
        [],
      );

      // 为什么：helper 先开串口再 listen；太早连会「连接被拒」，不是断网
      const maxTries = 10;
      const failMsg = '连接失败：helper 未就绪或已退出，请确认灯带已插上后重试「连接」';
      Socket? sock;
      Object? lastErr;
      for (int i = 1; i <= maxTries; ++i) {
        // 为什么：灯带未插时 helper 约 5s 就退出，不必再空等 Socket 重试
        const stillRunning = -1;
        final exitCode = await _proc!.exitCode.timeout(
          Duration.zero,
          onTimeout: () => stillRunning,
        );
        if (exitCode != stillRunning) {
          debugPrint('helper exited early: code=$exitCode');
          setState(() => _status = failMsg);
          _proc = null;
          return;
        }

        setState(() => _status = '等待 helper 就绪… ($i/$maxTries)');
        try {
          sock = await Socket.connect(
            InternetAddress.loopbackIPv4,
            9527,
            timeout: const Duration(milliseconds: 300),
          );
          break;
        } catch (e) {
          lastErr = e;
          if (i < maxTries) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
        }
      }
      if (sock == null) {
        // 不把 SocketException 原文甩给用户（乱码/「拒绝网络连接」会误导）
        debugPrint('Socket.connect failed: $lastErr');
        setState(() => _status = failMsg);
        try {
          _proc?.kill();
        } catch (_) {}
        _proc = null;
        return;
      }

      _sock = sock;
      // 为什么：同一条 Socket 双向；listen 收 helper 的 status 行
      _listenHelper(_sock!);

      setState(() {
        _ready = true;
        _status = '已连接，等待 helper 状态…';
      });
    } catch (e) {
      debugPrint('connect error: $e');
      setState(() {
        _status = '连接失败：无法启动 helper，请检查路径后重试';
      });
    }
  }

  void _listenHelper(Socket sock) {
    sock.listen(
      (data) {
        _rxBuf.write(utf8.decode(data));
        var chunk = _rxBuf.toString();
        int nl;
        while ((nl = chunk.indexOf('\n')) >= 0) {
          final line = chunk.substring(0, nl).trimRight();
          chunk = chunk.substring(nl + 1);
          _onHelperLine(line);
        }
        _rxBuf
          ..clear()
          ..write(chunk);
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _status = 'IPC 错误: $e');
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _ready = false;
          _status = 'helper 已断开';
        });
      },
      cancelOnError: true,
    );
  }

  void _onHelperLine(String line) {
    if (!mounted || line.isEmpty) return;
    if (!line.startsWith('status ')) return;
    final word = line.substring(7);
    setState(() {
      switch (word) {
        case 'ready':
          _status = '串口就绪';
        case 'reconnecting':
          _status = '正在重连串口…';
        case 'reconnect_ok':
          _status = '重连成功';
        case 'reconnect_fail':
          _status = '重连失败';
        default:
          _status = line;
      }
    });
  }

  // 「红 / 开始 / 停止」：只往已经打开的 Socket 写一行，不关连接
  void _send(String cmd) {
    if (!_ready || _sock == null) {
      setState(() => _status = '请先点「连接」');
      return;
    }
    if (cmd == 'start') {
      _engineWanted = true;
    } else if (cmd == 'stop' || cmd == 'off') {
      _engineWanted = false;
    }
    _sock!.write('$cmd\n');
    // reconnect 的文案由 helper 的 status 覆盖；其它命令先显示已发
    if (cmd != 'reconnect') {
      setState(() => _status = '已发: $cmd');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // App/页面销毁时：先礼貌发 quit，让 helper 关灯停线程再退出
    // （即使这步失败，关 Socket 也会触发 C++ 的 peer_gone 兜底）
    if (_sock != null) {
      try {
        _sock!.write('quit\n');
      } catch (_) {
        // 连接已断就忽略，别让 dispose 抛异常
      }
      _sock!.destroy();
      _sock = null;
    }
    _proc = null; // 不 kill：quit/断连后 helper 自己退
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Day 24 · 休眠/关机关灯')),
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
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _ready ? () => _send('reconnect') : null,
              child: const Text('重连串口'),
            ),
          ],
        ),
      ),
    );
  }
}
