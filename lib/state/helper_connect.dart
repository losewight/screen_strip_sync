part of 'helper_state.dart';

/// IPC 连接、配置快照重试、扫口与串口重连。
mixin _HelperConnect on _HelperStatusHandlers {
  /// 点「连接」时实际传给 helper 的口。
  ///
  /// 有 [AppConfig.lastConnectedCom] 时走快速路径；用户显式换口则用 [AppConfig.comPort]。
  String _resolveConnectPort() {
    final cfg = ref.read(configProvider);
    final selected = cfg.comPort.trim();
    final last = cfg.lastConnectedCom.trim();
    final anchor = state.anchorCom;

    final portChanged =
        selected.isNotEmpty &&
        anchor.isNotEmpty &&
        selected.toUpperCase() != anchor.toUpperCase();

    if (portChanged) return selected;
    if (last.isNotEmpty) return last;
    return selected;
  }

  /// 只连 helper IPC（不开口）。界面启动 / 扫口前用。
  /// 为什么：connecting 相位只表示开串口；连 IPC 静默，不改顶栏黑话。
  Future<void> ensureHelperConnected() async {
    if (_client.isQuitting) return;
    if (_ensureHelperInFlight || _client.isConnected) return;

    _ensureHelperInFlight = true;
    try {
      await _client.connect();
      if (_client.isQuitting) return;
      unawaited(_ensureConfigSnapshot());
    } catch (_) {
      if (_client.isQuitting) return;
      _patch(
        message: '暂时无法控制灯带',
        phase: HelperPhase.failed,
        hasDevice: false,
        currentCom: '',
        snapshotTimedOut: true,
      );
      _startAutoRetryIfNeeded();
    } finally {
      _ensureHelperInFlight = false;
    }
  }

  /// 点「连接」：默认只确保 IPC；仅换口 / 未配备开口 / 开口失败才 `set com` + `reconnect`。
  ///
  /// 为什么：helper 已常驻且灯在跑时，无条件 reconnect 会打断 lastScene。
  Future<void> connect() async {
    if (state.phase == HelperPhase.connecting) return;

    final cfgReady = ref.read(configProvider.notifier).hasSnapshot;
    if (!cfgReady) {
      await ensureHelperConnected();
      return;
    }

    final cfg = ref.read(configProvider);
    final wanted = cfg.comPort.trim();
    final targetCom = _resolveConnectPort();
    final anchor = state.anchorCom;
    final portChanged =
        wanted.isNotEmpty &&
        anchor.isNotEmpty &&
        wanted.toUpperCase() != anchor.toUpperCase();

    final shouldOpenSerial =
        portChanged ||
        state.phase == HelperPhase.needConnect ||
        state.phase == HelperPhase.openFailed ||
        (!cfg.serialConfigured && !state.hasDevice);

    if (_client.isConnected && !shouldOpenSerial) return;

    if (!_client.isConnected) {
      await ensureHelperConnected();
      if (!_client.isConnected) return;
      if (!shouldOpenSerial) return;
    }

    if (!shouldOpenSerial) return;

    if (targetCom.isEmpty && wanted.isEmpty) {
      _patch(message: '请先选择串口', phase: HelperPhase.failed);
      return;
    }

    final port = wanted.isNotEmpty ? wanted : targetCom;
    _patch(
      message: portChanged ? '换口，打开串口…' : '正在打开串口…',
      phase: HelperPhase.connecting,
      hasDevice: false,
      currentCom: '',
    );
    try {
      sendComPort(port);
      _sendIpc('reconnect');
    } catch (e) {
      _patch(
        message: '$e',
        phase: HelperPhase.failed,
        hasDevice: false,
        currentCom: '',
      );
    }
  }

  /// 首包超时才发 `sync`；正常 accept 已推全量，不主动刷。
  /// 未配备时快照到达后再扫一次，避免 cfg 默认 COM10 盖掉推荐口。
  Future<void> _ensureConfigSnapshot() async {
    const step = Duration(milliseconds: 100);
    const waitTries = 20; // 约 2s 超时
    Future<bool> waitSnapshot() async {
      for (var i = 0; i < waitTries; i++) {
        if (ref.read(configProvider.notifier).hasSnapshot) return true;
        if (!_client.isConnected) return false;
        await Future<void>.delayed(step);
      }
      return ref.read(configProvider.notifier).hasSnapshot;
    }

    if (await waitSnapshot()) {
      _patch(snapshotTimedOut: false);
      _stopAutoRetry();
    } else {
      _patch(
        message: '暂时无法控制灯带',
        snapshotTimedOut: true,
      );
      _startAutoRetryIfNeeded();
      if (!_client.isConnected) return;
      try {
        _sendIpc('sync');
      } catch (_) {
        _patch(message: '暂时无法控制灯带');
        return;
      }
      if (!await waitSnapshot()) return;
      _patch(snapshotTimedOut: false);
      _stopAutoRetry();
    }

    if (!ref.read(configProvider).serialConfigured) {
      await scanPorts(background: true);
    }
  }

  /// 连不上时自动 / 手动重试；进行中合并成一次。
  /// 成功前不把 snapshotTimedOut 拉回 false，避免控件在灰显与可点之间闪。
  Future<void> retrySnapshot() {
    return _retrySnapshotInFlight ??= _retrySnapshotBody().whenComplete(() {
      _retrySnapshotInFlight = null;
    });
  }

  Future<void> _retrySnapshotBody() async {
    if (_client.isQuitting) return;
    // 为什么：重试过程静默，不刷「正在连接后台」；失败文案留给 snapshotTimedOut。
    if (state.phase == HelperPhase.failed) {
      _patch(phase: HelperPhase.disconnected);
    }
    if (!_client.isConnected) {
      await ensureHelperConnected();
    }
    if (_client.isQuitting) return;
    if (!_client.isConnected) {
      _startAutoRetryIfNeeded();
      return;
    }
    if (ref.read(configProvider.notifier).hasSnapshot) {
      _patch(snapshotTimedOut: false);
      _stopAutoRetry();
      return;
    }
    try {
      _sendIpc('sync');
    } catch (_) {
      _patch(message: '暂时无法控制灯带', snapshotTimedOut: true);
      _startAutoRetryIfNeeded();
      return;
    }
    await _ensureConfigSnapshot();
  }

  /// 快照超时后每 2s 静默重试，直到收到 cfg 或 dispose。
  void _startAutoRetryIfNeeded() {
    if (_client.isQuitting) return;
    if (_autoRetryTimer != null) return;
    if (!state.snapshotTimedOut) return;
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_client.isQuitting) {
        _stopAutoRetry();
        return;
      }
      if (!state.snapshotTimedOut ||
          ref.read(configProvider.notifier).hasSnapshot) {
        _stopAutoRetry();
        return;
      }
      unawaited(retrySnapshot());
    });
  }

  void _stopAutoRetry() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
  }

  /// 由 [HelperStateNotifier.selectComPort] 实现；扫口推荐口时回调。
  void selectComPort(String value);

  /// 刷新本机串口列表。[background] 为 true 时不改状态条文案、不触发 CH340 覆盖上次成功口。
  Future<void> scanPorts({bool background = false}) async {
    if (state.isScanningPorts) return;
    if (background) {
      _patch(isScanningPorts: true);
    } else {
      _patch(isScanningPorts: true, message: '正在扫描串口…');
    }
    try {
      final scanned = await scanWindowsComPorts();
      if (background) {
        _patch(ports: scanned);
      } else {
        _patch(
          message: scanned.isEmpty ? '未发现串口' : '已扫描 ${scanned.length} 个串口',
          ports: scanned,
        );
      }

      // 为什么：cfg end 前默认 serialConfigured=false，不能当成真·未配备去 set com
      if (!ref.read(configProvider.notifier).hasSnapshot) return;
      if (ref.read(configProvider).serialConfigured) return;

      final preferred = scanned.where((p) => p.preferred).toList();
      if (preferred.isEmpty) return;

      final current = ref.read(configProvider).comPort.trim().toUpperCase();
      if (!preferred.any((p) => p.port.toUpperCase() == current)) {
        selectComPort(preferred.first.port);
      }
    } finally {
      _patch(isScanningPorts: false);
    }
  }

  Future<void> reconnectSerial() async {
    if (!_client.isConnected) {
      await ensureHelperConnected();
      if (!_client.isConnected) return;
    }
    try {
      // 先把当前 UI 口推给 helper，再重开
      sendComPort(ref.read(configProvider).comPort);
      _patch(message: '正在重连串口…', phase: HelperPhase.connecting);
      _sendIpc('reconnect');
    } catch (e) {
      _patch(message: '$e');
    }
  }
}
