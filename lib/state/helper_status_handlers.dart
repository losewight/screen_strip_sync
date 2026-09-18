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
      case HelperStatusCaptureOutput():
        _onStatusCaptureOutput(event);
      case HelperStatusOutputsCount(:final count):
        _onStatusOutputsCount(count);
      case HelperStatusOutput():
        _onStatusOutput(event);
    }
  }

  /// helper 休眠恢复后的显示意图：对齐徽标，避免灯已亮而 UI 仍停在熄灯。
  void _onStatusDisplay(HelperDisplayKind kind) {
    _lastDisplay = kind;
    // 为什么：无 COM 仍会推 display idle；勿盖掉 needConnect / openFailed
    if (!state.hasDevice ||
        state.phase == HelperPhase.needConnect ||
        state.phase == HelperPhase.openFailed) {
      if (kind == HelperDisplayKind.idle) {
        _engineWanted = false;
        _patch(engineRunning: false);
      }
      return;
    }

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
      case HelperDisplayKind.region:
        _engineWanted = true;
        _patch(
          engineRunning: true,
          phase: HelperPhase.running,
          hasDevice: true,
          message: com.isEmpty ? '屏幕氛围运行中' : '$com · 屏幕氛围运行中',
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
    // engine 0：停追色。poweredOff / needConnect / openFailed / failed 等相位不动
    final keepPhase =
        state.phase == HelperPhase.poweredOff ||
        state.phase == HelperPhase.needConnect ||
        state.phase == HelperPhase.openFailed ||
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
        // 为什么：ready = 串口就绪，不是引擎已停。引擎以随后的
        // `status engine` / `status display` 为准，切勿在此强制 engineRunning: false。
        _patch(
          message: state.engineRunning ? state.message : '串口就绪',
          phase: state.engineRunning ? HelperPhase.running : HelperPhase.ready,
          hasDevice: true,
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
        final cfg = ref.read(configProvider);
        if (!cfg.serialConfigured) {
          _patch(
            message: '灯带未连接，请选择串口后点「连接」',
            hasDevice: false,
            phase: HelperPhase.needConnect,
            currentCom: '',
            engineRunning: false,
          );
        } else {
          _patch(
            message: '无法打开 ${cfg.comPort}，请检查灯带连接',
            hasDevice: false,
            phase: HelperPhase.openFailed,
            currentCom: '',
            engineRunning: false,
          );
        }
      case HelperStatusWord.unknown:
        break;
    }
  }

  String _formatReadyMessage({required String com, required bool engine}) {
    if (com.isEmpty) return '串口就绪';
    if (engine) return '$com · 追色运行中';
    return '串口就绪（$com）';
  }

  void _onStatusCaptureOutput(HelperStatusCaptureOutput e) {
    _patch(
      currentCapture: CaptureOutputInfo(
        name: e.name,
        width: e.width,
        height: e.height,
        left: e.left,
        top: e.top,
        isCurrent: true,
        friendlyName: e.friendlyName,
      ),
    );
  }

  void _onStatusOutputsCount(int count) {
    _outputsExpect = count;
    _outputsBuf.clear();
    if (count == 0) {
      _patch(captureOutputs: const []);
    }
  }

  void _onStatusOutput(HelperStatusOutput e) {
    if (_outputsExpect <= 0) return;
    _outputsBuf.add(
      CaptureOutputInfo(
        name: e.name,
        width: e.width,
        height: e.height,
        left: e.left,
        top: e.top,
        isPrimary: e.isPrimary,
        isCurrent: e.isCurrent,
        friendlyName: e.friendlyName,
      ),
    );
    if (_outputsBuf.length >= _outputsExpect) {
      _patch(captureOutputs: List<CaptureOutputInfo>.unmodifiable(_outputsBuf));
      _outputsExpect = 0;
      _outputsBuf.clear();
    }
  }

  // 由 HelperStateNotifier 实现（UI 改参时下发）。
  void sendEmaAlpha(double alpha);
  void sendNearBlack(int nearBlack);
  void sendBlur(int blurStep);
  void sendSaturation(double saturation);
  void sendMode(ColorMode mode);
  void sendComPort(String port);
  void sendCaptureOutput(String name);
  void sendSleepSync(bool enabled);
  void sendAutostart(bool enabled);
  void sendShutdownOff(bool enabled);
  void syncSegmentMapFromConfig();
  void startRegion();
  void sendRegionAlgo(RegionAlgo algo);
  void sendRegionBlur(int blur);
  void sendRegionSmooth(double smooth);
  void sendRegionDark(int dark);
  void sendRegionBBox(RegionBBox box);
  void sendLastCustomSolid(String rrggbb);
  void sendWallComp(bool enabled);
  void sendWallColor(String rrggbb);
}
