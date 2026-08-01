part of 'helper_state.dart';

/// 休眠硬关断连后的唤醒自动重连（方案三）。
mixin _HelperWakeReconnect on _HelperSolidGate {
  Future<void> connect();
  void send(String cmd);
  void softOff();

  /// 方案三：仅 armed（休眠硬关导致断连）时拉起 helper，并按快照恢复现场。
  Future<void> reconnectAfterResume() async {
    if (_resumeBusy) return;
    final cfg = ref.read(configProvider);
    if (!cfg.autoSleepSync) return;
    if (!_wakeReconnectArmed) return;
    if (_client.isConnected) return;

    _resumeBusy = true;
    try {
      _cancelPendingSolid();
      final wantEngine = _resumeWantEngine;
      final solid = _resumeSolid;
      final wasPoweredOff = _resumePoweredOff;

      _patch(message: '系统唤醒，3 秒后重连…');
      await Future<void>.delayed(const Duration(seconds: 3));

      _intentionalDisconnect = true;
      try {
        await _client.quit();
      } finally {
        _intentionalDisconnect = false;
      }
      _engineWanted = false;
      _patch(message: '正在重连…', phase: HelperPhase.disconnected);

      const maxAttempts = 5;
      for (var left = maxAttempts; left >= 1; left--) {
        try {
          // 上次卡在 connecting 时先拆掉，否则 connect() 会空返回
          if (state.phase == HelperPhase.connecting && _client.isConnected) {
            _intentionalDisconnect = true;
            try {
              await _client.quit();
            } finally {
              _intentionalDisconnect = false;
            }
            _patch(phase: HelperPhase.disconnected);
          }

          await connect();
          if (!_client.isConnected) {
            throw StateError('IPC 未接通');
          }

          final ready = await _waitUntilCanControl(
            const Duration(seconds: 8),
          );
          if (ready) {
            if (wantEngine) {
              send('start');
            } else if (wasPoweredOff) {
              softOff();
            } else if (solid != null && solid.length == 6) {
              sendSolid(solid);
            }
            _wakeReconnectArmed = false;
            return;
          }
        } catch (_) {}
        if (left > 1) {
          _patch(message: '重连失败，2 秒后重试（剩 ${left - 1}）…');
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      _wakeReconnectArmed = false;
      _patch(
        message: '唤醒后重连失败，请手动点「连接」',
        phase: HelperPhase.failed,
      );
    } finally {
      _resumeBusy = false;
    }
  }

  /// 等 status ready（或已可控）；超时返回 false。
  Future<bool> _waitUntilCanControl(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (state.canControl) return true;
      if (state.phase == HelperPhase.failed ||
          state.phase == HelperPhase.noDevice) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return state.canControl;
  }
}
