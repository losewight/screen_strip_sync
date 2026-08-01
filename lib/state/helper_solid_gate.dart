part of 'helper_state.dart';

/// 纯色节流：与串口 ≥50ms 对齐；冷却期内只保留最新色。
mixin _HelperSolidGate on _HelperStateBase {
  void _cancelPendingSolid() {
    _solidTimer?.cancel();
    _solidTimer = null;
    _pendingSolid = null;
  }

  void _flushPendingSolid() {
    final color = _pendingSolid;
    _pendingSolid = null;
    if (color == null || !_client.isConnected) return;
    if (color == _lastSentSolid) return;
    _lastSentSolid = color;
    _sendIpc('solid $color');
  }

  void _onSolidCooldownEnd() {
    _solidTimer = null;
    if (_pendingSolid == null) return;
    _flushPendingSolid();
    // 冷却期内又攒了色：发出后继续冷却，保证最快约 70ms 一帧
    _solidTimer = Timer(_HelperStateBase._solidCooldown, _onSolidCooldownEnd);
  }

  /// 点色卡/取色：若追色引擎在跑（[_engineWanted]），先立即 `stop`。
  /// 纯色走 **方案 A**：首击立刻发；冷却 70ms 内只记最新色，结束再补发。
  /// 最快约一帧/70ms，避免人手切色卡仍把每色都塞进队列。
  void sendSolid(String rrggbb) {
    if (!_client.isConnected) return;
    try {
      if (_engineWanted) {
        _engineWanted = false;
        _sendIpc('stop');
      }
      _patch(
        message: '纯色运行中',
        phase: HelperPhase.running,
        hasDevice: true,
      );
      _pendingSolid = rrggbb;
      if (_solidTimer == null) {
        // leading：冷却空闲 → 马上发，再进入冷却
        _flushPendingSolid();
        _solidTimer = Timer(
          _HelperStateBase._solidCooldown,
          _onSolidCooldownEnd,
        );
      }
      // else：冷却中只更新 pending，等 _onSolidCooldownEnd trailing
    } catch (e) {
      _patch(message: '$e');
    }
  }
}
