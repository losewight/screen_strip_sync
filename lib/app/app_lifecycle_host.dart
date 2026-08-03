import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../ipc/helper_client.dart';
import '../state/helper_state.dart';
import 'crash_log.dart';

/// App 级生命周期：关窗先 hide 再清理；休眠唤醒仅靠 armed 标志重连（方案三）。
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
  StreamSubscription<void>? _uiShowSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    // 为什么：不拦截则 close 立刻杀进程，quit 来不及写，helper 易僵尸占 COM
    unawaited(_armPreventClose());
    // H5：托盘双击推 ui show → 置顶现有窗口（完整关窗 bye 语义仍属 F3）
    _uiShowSub = ref.read(helperClientProvider).uiShowStream.listen((_) {
      unawaited(_bringToFront());
    });
  }

  Future<void> _bringToFront() async {
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      CrashLog.error('lifecycle ui show', e, st);
    }
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
    unawaited(_uiShowSub?.cancel());
    _uiShowSub = null;
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final prev = _lastLifecycle;
    _lastLifecycle = state;

    // 为什么：仅后台→前台；最小化若不断开 socket 则 armed 为 false，不会误连
    final cameFromBackground = switch (prev) {
      AppLifecycleState.paused ||
      AppLifecycleState.hidden ||
      AppLifecycleState.detached => true,
      _ => false,
    };

    if (state == AppLifecycleState.resumed && cameFromBackground) {
      ref.read(helperStateProvider.notifier).reconnectAfterResume();
    }
  }

  @override
  void onWindowFocus() {
    // 仅当 _wakeReconnectArmed（休眠硬关断连）时才会真正重连；最小化不断开则无操作
    ref.read(helperStateProvider.notifier).reconnectAfterResume();
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
    CrashLog.event('lifecycle', 'exit(0)');
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
    await ref.read(helperStateProvider.notifier).quit();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
