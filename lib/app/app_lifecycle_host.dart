import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../state/helper_state.dart';

/// App 级生命周期：关窗销毁窗口；休眠唤醒后按需重连（IPC 未接入时跳过）。
class AppLifecycleHost extends ConsumerStatefulWidget {
  const AppLifecycleHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleHost> createState() => _AppLifecycleHostState();
}

class _AppLifecycleHostState extends ConsumerState<AppLifecycleHost>
    with WidgetsBindingObserver, WindowListener {
  AppLifecycleState? _lastLifecycle;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    // 为什么：不拦截则 close 立刻杀进程，quit 来不及写，helper 易僵尸占 COM
    windowManager.setPreventClose(true);
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
    _shutdownThenClose();
  }

  Future<void> _shutdownThenClose() async {
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {
      // 插件未就绪时忽略；进程仍会随 Flutter 退出
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
