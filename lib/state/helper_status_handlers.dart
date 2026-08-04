part of 'helper_state.dart';

/// helper `status …` 行 → 相位 / COM / 引擎 / 显示意图。
mixin _HelperStatusHandlers on _HelperStateBase {
  void _onStatusEvent(HelperStatusEvent event) {
    switch (event) {
      case HelperStatusPhase(:final word):
        _onStatusPhase(word);
      case HelperStatusCom(:final port):
        _onStatusCom(port);
      case HelperStatusEngine(:final running):
        _onStatusEngine(running);
      case HelperStatusDisplay(:final kind):
        _onStatusDisplay(kind);
    }
  }

  /// helper 休眠恢复后的显示意图：对齐徽标，避免灯已亮而 UI 仍停在熄灯。
  void _onStatusDisplay(HelperDisplayKind kind) {
    final com = state.currentCom;
    switch (kind) {
      case HelperDisplayKind.engine:
        _engineWanted = true;
        _patch(
          engineRunning: true,
          phase: HelperPhase.running,
          hasDevice: true,
          message: com.isEmpty ? '追色运行中' : '$com · 追色运行中',
        );
      case HelperDisplayKind.solid:
        _engineWanted = false;
        _patch(
          engineRunning: false,
          phase: HelperPhase.running,
          hasDevice: true,
          message: '纯色运行中',
        );
      case HelperDisplayKind.softOff:
        _engineWanted = false;
        _lastSentSolid = null;
        _patch(
          engineRunning: false,
          phase: HelperPhase.poweredOff,
          hasDevice: true,
          message: '已熄灯',
        );
      case HelperDisplayKind.idle:
        _engineWanted = false;
        _patch(
          engineRunning: false,
          phase: HelperPhase.ready,
          hasDevice: true,
          message: _formatReadyMessage(com: com, engine: false),
        );
    }
  }

  /// helper 真值 COM：更新 UI 内存配置，供下次快速连接展示。
  void _onStatusCom(String port) {
    final name = port.trim();
    if (name.isEmpty) return;
    ref.read(configProvider.notifier).setLastConnectedCom(name);
    _patch(
      message: _formatReadyMessage(com: name, engine: state.engineRunning),
      currentCom: name,
      lastGoodCom: name,
      hasDevice: true,
      phase:
          state.phase == HelperPhase.connecting ||
              state.phase == HelperPhase.disconnected
          ? HelperPhase.ready
          : null,
    );
  }

  void _onStatusEngine(bool running) {
    _engineWanted = running;
    final com = state.currentCom;
    if (running) {
      _patch(
        engineRunning: true,
        message: com.isEmpty ? '追色运行中' : '$com · 追色运行中',
        phase: HelperPhase.running,
        hasDevice: true,
      );
      return;
    }
    // engine 0：停追色。poweredOff / noDevice / failed 等相位不动
    final keepPhase =
        state.phase == HelperPhase.poweredOff ||
        state.phase == HelperPhase.noDevice ||
        state.phase == HelperPhase.failed ||
        state.phase == HelperPhase.disconnected ||
        state.phase == HelperPhase.connecting;
    _patch(
      engineRunning: false,
      message: keepPhase
          ? state.message
          : _formatReadyMessage(com: com, engine: false),
      phase: keepPhase ? null : HelperPhase.ready,
    );
  }

  void _onStatusPhase(HelperStatusWord word) {
    switch (word) {
      case HelperStatusWord.ready:
        // 为什么：配置真源是 helper 已推的 cfg 快照；此处不再回推本地值
        _patch(
          message: '串口就绪',
          phase: HelperPhase.ready,
          hasDevice: true,
          engineRunning: false,
        );
      case HelperStatusWord.reconnecting:
        _patch(
          message: '正在重连串口…',
          phase: state.canControl ? null : HelperPhase.connecting,
          hasDevice: state.canControl ? true : false,
          engineRunning: false,
        );
      case HelperStatusWord.reconnectOk:
        _patch(
          message: '重连成功',
          hasDevice: true,
          phase: state.canControl ? null : HelperPhase.ready,
          engineRunning: false,
        );
      case HelperStatusWord.reconnectFail:
        _patch(
          message: '重连失败：打不开 ${ref.read(configProvider).comPort}',
          hasDevice: false,
          phase: HelperPhase.noDevice,
          currentCom: '',
          engineRunning: false,
        );
      case HelperStatusWord.unknown:
        break;
    }
  }

  String _formatReadyMessage({required String com, required bool engine}) {
    if (com.isEmpty) return '串口就绪';
    if (engine) return '$com · 追色运行中';
    return '串口就绪（$com）';
  }

  // 由 HelperStateNotifier 实现（UI 改参时下发）。
  void sendEmaAlpha(double alpha);
  void sendNearBlack(int nearBlack);
  void sendBlur(int blurStep);
  void sendMode(ColorMode mode);
  void sendComPort(String port);
  void sendSleepSync(bool enabled);
  void sendAutostart(bool enabled);
  void sendShutdownOff(bool enabled);
  void syncSegmentMapFromConfig();
}
