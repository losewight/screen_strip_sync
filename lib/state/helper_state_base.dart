part of 'helper_state.dart';

/// 共享字段与 `_patch` / `_sendIpc`，供各 mixin 挂载。
abstract class _HelperStateBase extends Notifier<HelperUiState> {
  /// 与串口 ≥50ms 对齐；冷却期内只保留最新色。
  static const _solidCooldown = Duration(milliseconds: 70);

  StreamSubscription<HelperStatusEvent>? _statusSub;
  StreamSubscription<void>? _disconnectSub;
  bool _ensureHelperInFlight = false;
  bool _engineWanted = false;
  HelperDisplayKind _lastDisplay = HelperDisplayKind.idle;
  String? _pendingSolid;
  Timer? _solidTimer;
  String? _lastSentSolid;
  int _outputsExpect = 0;
  final List<CaptureOutputInfo> _outputsBuf = [];

  HelperClient get _client => ref.read(helperClientProvider);

  void _patch({
    String? message,
    HelperPhase? phase,
    List<ComPortInfo>? ports,
    String? currentCom,
    String? lastGoodCom,
    bool? hasDevice,
    bool? isScanningPorts,
    bool? engineRunning,
    bool? snapshotTimedOut,
    List<CaptureOutputInfo>? captureOutputs,
    CaptureOutputInfo? currentCapture,
    bool clearCurrentCapture = false,
  }) {
    state = HelperUiState(
      phase: phase ?? state.phase,
      message: message ?? state.message,
      ports: ports ?? state.ports,
      currentCom: currentCom ?? state.currentCom,
      lastGoodCom: lastGoodCom ?? state.lastGoodCom,
      hasDevice: hasDevice ?? state.hasDevice,
      isScanningPorts: isScanningPorts ?? state.isScanningPorts,
      engineRunning: engineRunning ?? state.engineRunning,
      snapshotTimedOut: snapshotTimedOut ?? state.snapshotTimedOut,
      captureOutputs: captureOutputs ?? state.captureOutputs,
      currentCapture: clearCurrentCapture
          ? null
          : (currentCapture ?? state.currentCapture),
    );
  }

  void _sendIpc(String cmd) {
    _client.send(cmd);
  }
}
