import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../ipc/helper_client.dart';
import '../state/helper_state.dart';
import 'crash_log.dart';

/// App 级生命周期：关窗先 hide（视觉秒关）再后台清理；休眠唤醒后按需重连。
class AppLifecycleHost extends ConsumerStatefulWidget {
  const AppLifecycleHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleHost> createState() => _AppLifecycleHostState();
}

class _AppLifecycleHostState extends ConsumerState<AppLifecycleHost>
    with WidgetsBindingObserver, WindowListener {
  static const _helperQuitTimeout = Duration(milliseconds: 300);

  AppLifecycleState? _lastLifecycle;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    // 为什么：不拦截则 close 立刻杀进程，quit 来不及写，helper 易僵尸占 COM
    unawaited(_armPreventClose());
  }

  Future<void> _armPreventClose() async {
    try {
      await windowManager.setPreventClose(true);
    } catch (e, st) {
      CrashLog.error('lifecycle', e, st);
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final prev = _lastLifecycle;
    _lastLifecycle = state;

    // 为什么：最小化/失焦也会 resumed，连接仍活时绝不能 teardown
    final cameFromBackground = switch (prev) {
      AppLifecycleState.paused ||
      AppLifecycleState.hidden ||
      AppLifecycleState.detached => true,
      _ => false,
    };

    if (state == AppLifecycleState.resumed &&
        cameFromBackground &&
        !ref.read(helperStateProvider.notifier).isReady) {
      ref.read(helperStateProvider.notifier).reconnectAfterResume();
    }
  }

  @override
  void onWindowClose() {
    if (_closing) return;
    _closing = true;
    unawaited(_hideThenShutdown());
  }

  Future<void> _hideThenShutdown() async {
    CrashLog.event('lifecycle', 'onWindowClose -> _hideThenShutdown');
    // 为什么：用户点关闭后立刻藏窗，清理在后台做，避免等 destroy 才消失
    try {
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    } catch (_) {
      // 插件未就绪时忽略
    }

    await _cleanupHelper();

    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {
      // destroy 失败时仍 exit 兜底
    }

    // 为什么：Timer/Socket 等未释放时 VM 可能不退，显式杀主进程
    exit(0);
  }

  Future<void> _cleanupHelper() async {
    try {
      await _quitHelperIfConnected().timeout(_helperQuitTimeout);
    } on TimeoutException {
      // helper 挂起或串口卡死：超时后仍走 destroy + exit
    } catch (_) {
      // 未连接等：忽略
    }
  }

  Future<void> _quitHelperIfConnected() async {
    await ref.read(helperClientProvider).quit();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
