part of 'helper_state.dart';

/// 共享字段与 `_patch` / `_sendIpc`，供各 mixin 挂载。
abstract class _HelperStateBase extends Notifier<HelperUiState> {
  /// 与串口 ≥50ms 对齐；冷却期内只保留最新色。
  static const _solidCooldown = Duration(milliseconds: 70);

  StreamSubscription<HelperStatusEvent>? _statusSub;
  StreamSubscription<void>? _disconnectSub;
  bool _engineWanted = false;
  String? _pendingSolid;
  Timer? _solidTimer;
  String? _lastSentSolid;

  HelperClient get _client => ref.read(helperClientProvider);

  void _patch({
    String? message,
    String? ipcLine,
    HelperPhase? phase,
    List<ComPortInfo>? ports,
    String? currentCom,
    String? lastGoodCom,
    bool? hasDevice,
    bool? isScanningPorts,
    bool? engineRunning,
  }) {
    state = HelperUiState(
      phase: phase ?? state.phase,
      message: message ?? state.message,
      ipcLine: ipcLine ?? state.ipcLine,
      ports: ports ?? state.ports,
      currentCom: currentCom ?? state.currentCom,
      lastGoodCom: lastGoodCom ?? state.lastGoodCom,
      hasDevice: hasDevice ?? state.hasDevice,
      isScanningPorts: isScanningPorts ?? state.isScanningPorts,
      engineRunning: engineRunning ?? state.engineRunning,
    );
  }

  void _sendIpc(String cmd) {
    _client.send(cmd);
    _patch(ipcLine: '$cmd\n');
  }
}
