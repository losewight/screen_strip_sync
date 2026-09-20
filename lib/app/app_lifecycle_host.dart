import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../ipc/helper_client.dart';
import '../state/helper_state.dart';
import 'crash_log.dart';

/// App 级生命周期：关窗视觉立刻消失，后台 bye 后 exit(0)；托盘 `ui show` 置顶；
/// 托盘/IPC 完全退出推 `ui quit` 时同样 exit(0)。
class AppLifecycleHost extends ConsumerStatefulWidget {
  const AppLifecycleHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleHost> createState() => _AppLifecycleHostState();
}

class _AppLifecycleHostState extends ConsumerState<AppLifecycleHost>
    with WindowListener {
  static const _helperQuitTimeout = Duration(milliseconds: 300);

  bool _closing = false;
  StreamSubscription<void>? _uiShowSub;
  StreamSubscription<void>? _uiQuitSub;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // 为什么：不拦截则 close 立刻杀进程，bye 来不及写
    unawaited(_armPreventClose());
    final client = ref.read(helperClientProvider);
    // 托盘双击且客户端仍在：helper 推 ui show → 置顶
    _uiShowSub = client.uiShowStream.listen((_) {
      unawaited(_bringToFront());
    });
    // 托盘「退出」：helper 推 ui quit → 立刻关窗，禁止再拉 helper
    _uiQuitSub = client.uiQuitStream.listen((_) {
      if (_closing) return;
      _closing = true;
      unawaited(_shutdown());
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
    unawaited(_uiQuitSub?.cancel());
    _uiQuitSub = null;
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (_closing) return;
    _closing = true;
    unawaited(_shutdown());
  }

  /// 第一拍：立刻 hide（视觉零延迟）；第二拍：bye → exit(0)。
  /// hide 只服务观感，禁止停在藏后台态。
  Future<void> _shutdown() async {
    CrashLog.event('lifecycle', 'onWindowClose -> _shutdown');
    try {
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    } catch (_) {
      // 插件未就绪时忽略
    }

    try {
      await ref
          .read(helperStateProvider.notifier)
          .quit()
          .timeout(_helperQuitTimeout);
    } on TimeoutException {
      // helper 挂起：超时后仍 exit
    } catch (_) {
      // 未连接 / helper 已在退：忽略
    }

    CrashLog.event('lifecycle', 'exit(0)');
    exit(0);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
