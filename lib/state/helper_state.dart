import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/segment_map_codec.dart';
import '../ipc/helper_client.dart';
import '../ipc/helper_status.dart';
import '../ipc/windows_com_ports.dart';
import 'config_state.dart';
import 'helper_ui_state.dart';

export 'helper_ui_state.dart';

part 'helper_segment_map_ipc.dart';
part 'helper_solid_gate.dart';
part 'helper_state_base.dart';
part 'helper_status_handlers.dart';
part 'helper_connect.dart';
part 'helper_ipc_setters.dart';
part 'helper_calibration.dart';

class HelperStateNotifier extends _HelperStateBase
    with
        _HelperSolidGate,
        _HelperStatusHandlers,
        _HelperSegmentMapIpc,
        _HelperConnect,
        _HelperIpcSetters,
        _HelperCalibration {
  @override
  HelperUiState build() {
    _statusSub ??= _client.statusStream.listen(_onStatusEvent);
    _disconnectSub ??= _client.disconnectStream.listen((_) {
      // 为什么：托盘完全退出已推 ui quit，勿开 auto-retry 再拉 helper
      if (_client.isQuitting) {
        _stopAutoRetry();
        return;
      }
      _cancelPendingSolid();
      _lastDisplay = HelperDisplayKind.idle;
      _outputsExpect = 0;
      _outputsBuf.clear();
      _patch(
        message: '暂时无法控制灯带',
        phase: HelperPhase.disconnected,
        hasDevice: false,
        currentCom: '',
        engineRunning: false,
        snapshotTimedOut: true,
        captureOutputs: const [],
        clearCurrentCapture: true,
      );
      _startAutoRetryIfNeeded();
    });
    ref.onDispose(() {
      _cancelPendingSolid();
      _stopAutoRetry();
      _statusSub?.cancel();
      _disconnectSub?.cancel();
    });
    // 为什么：界面起来只连 IPC + 扫口；开口等用户点「连接」（首启门闩）
    Future.microtask(() async {
      unawaited(scanPorts(background: true));
      await ensureHelperConnected();
    });
    final cfg = ref.read(configProvider);
    return HelperUiState(
      phase: HelperPhase.disconnected,
      message: '未连接',
      lastGoodCom: cfg.lastConnectedCom,
    );
  }

  bool get isReady => _client.isConnected && state.canControl;

  @override
  void selectComPort(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    ref.read(configProvider.notifier).setComPort(name);
    _patch(message: '已选择 $name');
    // 为什么：cfg end 前默认 serialConfigured=false，不能当成真·未配备去 set com
    if (!ref.read(configProvider.notifier).hasSnapshot) return;
    // 已连接时只改本地配置；真正切口点「换口连接」（同口恢复才用「重连串口」）
    sendComPort(name);
  }

  /// 前端关窗：发 `bye` 只断 Socket，**不是**关 helper（IPC `quit` 才退后台）。
  Future<void> quit() async {
    _cancelPendingSolid();
    await _client.quit();
  }
}

final helperStateProvider =
    NotifierProvider<HelperStateNotifier, HelperUiState>(
      HelperStateNotifier.new,
    );
