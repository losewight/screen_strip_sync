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

class HelperStateNotifier extends _HelperStateBase
    with _HelperSolidGate, _HelperStatusHandlers, _HelperSegmentMapIpc {
  @override
  HelperUiState build() {
    _statusSub ??= _client.statusStream.listen(_onStatusEvent);
    _disconnectSub ??= _client.disconnectStream.listen((_) {
      _cancelPendingSolid();
      _patch(
        message: 'helper 已断开',
        phase: HelperPhase.disconnected,
        hasDevice: false,
        currentCom: '',
        engineRunning: false,
      );
    });
    ref.onDispose(() {
      _cancelPendingSolid();
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

  bool get isReady => _client.isConnected && state.canControl;

  void selectComPort(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    ref.read(configProvider.notifier).setComPort(name);
    _patch(message: '已选择 $name');
    // 已连接时只改本地配置；真正切口点「换口连接」（同口恢复才用「重连串口」）
    sendComPort(name);
  }

  /// 只连 helper IPC（不开口）。界面启动 / 扫口前用。
  /// 为什么：connecting 相位只表示开串口；连后台不改顶栏，等 helper 推 status。
  Future<void> ensureHelperConnected() async {
    if (_ensureHelperInFlight || _client.isConnected) return;

    _ensureHelperInFlight = true;
    try {
      await _client.connect();
      unawaited(_ensureConfigSnapshot());
    } catch (e) {
      _patch(
        message: '$e',
        phase: HelperPhase.failed,
        hasDevice: false,
        currentCom: '',
      );
    } finally {
      _ensureHelperInFlight = false;
    }
  }

  /// 点「连接」：确保 IPC → `set com` + `reconnect`（写盘与门闩在 helper）。
  Future<void> connect() async {
    if (state.phase == HelperPhase.connecting) return;

    final cfg = ref.read(configProvider);
    final wanted = cfg.comPort.trim();
    final targetCom = _resolveConnectPort();
    final anchor = state.anchorCom;
    final portChanged =
        wanted.isNotEmpty &&
        anchor.isNotEmpty &&
        wanted.toUpperCase() != anchor.toUpperCase();

    if (targetCom.isEmpty) {
      _patch(message: '请先选择串口', phase: HelperPhase.failed);
      return;
    }

    // 已开口且口未变：忽略重复点「连接」
    if (_client.isConnected && state.canControl && !portChanged) return;

    if (!_client.isConnected) {
      await ensureHelperConnected();
      if (!_client.isConnected) return;
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
    Future<bool> waitSnapshot() async {
      for (var i = 0; i < 20; i++) {
        if (!_client.isConnected) return false;
        if (ref.read(configProvider.notifier).hasSnapshot) return true;
        await Future<void>.delayed(step);
      }
      return ref.read(configProvider.notifier).hasSnapshot;
    }

    if (!await waitSnapshot()) {
      if (!_client.isConnected) return;
      try {
        _sendIpc('sync');
        _patch(message: '后台配置超时，已请求同步…');
      } catch (e) {
        _patch(message: '$e');
        return;
      }
      if (!await waitSnapshot()) return;
    }

    if (!ref.read(configProvider).serialConfigured) {
      await scanPorts(background: true);
    }
  }

  /// 松手滑条后下发；helper 侧再 clamp。未连接则静默跳过。
  @override
  void sendEmaAlpha(double alpha) {
    if (!_client.isConnected) return;
    try {
      final v = alpha.clamp(0.05, 1.0);
      _sendIpc('set alpha ${v.toStringAsFixed(2)}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendNearBlack(int nearBlack) {
    if (!_client.isConnected) return;
    try {
      final v = nearBlack.clamp(0, 64);
      _sendIpc('set near_black $v');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendBlur(int blurStep) {
    if (!_client.isConnected) return;
    try {
      final v = blurStep.clamp(0, 8);
      _sendIpc('set blur $v');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendSaturation(double saturation) {
    if (!_client.isConnected) return;
    try {
      final v = saturation.clamp(0.5, 2.0);
      _sendIpc('set saturation ${v.toStringAsFixed(2)}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendMode(ColorMode mode) {
    if (!_client.isConnected) return;
    try {
      final letter = switch (mode) {
        ColorMode.a => 'a',
        ColorMode.b => 'b',
      };
      _sendIpc('set mode $letter');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// 屏幕氛围：独立于 `start`（map）的追色入口。
  @override
  void startRegion() {
    if (!_client.isConnected) return;
    try {
      _cancelPendingSolid();
      _engineWanted = true;
      _sendIpc('start_region');
      _patch(
        message: '屏幕氛围运行中',
        phase: HelperPhase.running,
        engineRunning: true,
      );
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendRegionAlgo(RegionAlgo algo) {
    if (!_client.isConnected) return;
    try {
      final word = switch (algo) {
        RegionAlgo.mean => 'mean',
        RegionAlgo.max => 'max',
      };
      _sendIpc('set region_algo $word');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendRegionBlur(int blur) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set region_blur ${blur.clamp(0, 20)}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendRegionSmooth(double smooth) {
    if (!_client.isConnected) return;
    try {
      final v = smooth.clamp(0.0, 0.99);
      _sendIpc('set region_smooth ${v.toStringAsFixed(2)}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendRegionDark(int dark) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set region_dark ${dark.clamp(0, 50)}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendRegionBBox(RegionBBox box) {
    if (!_client.isConnected) return;
    if (!box.isValid) return;
    try {
      _sendIpc('set region_bbox ${box.toIpcPayload()}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendLastCustomSolid(String rrggbb) {
    if (!_client.isConnected) return;
    final h = rrggbb.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) return;
    try {
      _sendIpc('set last_custom_solid $h');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendWallComp(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set wall_comp ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendWallColor(String rrggbb) {
    if (!_client.isConnected) return;
    final h = rrggbb.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) return;
    try {
      _sendIpc('set wall_color $h');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendComPort(String port) {
    if (!_client.isConnected) return;
    final name = port.trim();
    if (name.isEmpty) return;
    try {
      _sendIpc('set com $name');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// 休眠同步开关：已连接则下发；未连接静默。
  @override
  void sendSleepSync(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set sleep_sync ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// 开机自启：已连接则下发；未连接静默。
  @override
  void sendAutostart(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set autostart ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// 关机关灯：已连接则下发；未连接静默。
  @override
  void sendShutdownOff(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set shutdown_off ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

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

      // 仅未配备：用 CH340 推荐口填 comPort（不冲已配备用户的选中）
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
      await connect();
      return;
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

  /// UI「关灯」：发 `soft_off`（停引擎 + 纯黑一帧），不掉电。
  /// 勿与备用命令 `off`（`set_power 0`）混淆；真下电只走 `quit`。
  void softOff() {
    if (!_client.isConnected) return;
    try {
      _cancelPendingSolid();
      _lastSentSolid = null;
      _engineWanted = false;
      _sendIpc('soft_off');
      _patch(
        message: '已熄灯',
        phase: HelperPhase.poweredOff,
        hasDevice: true,
        engineRunning: false,
      );
    } catch (e) {
      _patch(message: '$e');
    }
  }

  void send(String cmd) {
    if (!_client.isConnected) return;
    try {
      if (cmd == 'start') {
        _cancelPendingSolid();
        _engineWanted = true;
        _patch(
          message: '引擎运行中',
          phase: HelperPhase.running,
          engineRunning: true,
        );
      } else if (cmd == 'stop') {
        _engineWanted = false;
        _patch(
          message: '引擎已停止',
          phase: HelperPhase.ready,
          engineRunning: false,
        );
      } else if (cmd == 'off') {
        // 备用真下电；UI 关灯请用 softOff()
        _cancelPendingSolid();
        _lastSentSolid = null;
        _engineWanted = false;
        _patch(
          message: '已下电',
          phase: HelperPhase.poweredOff,
          hasDevice: true,
          engineRunning: false,
        );
      }
      _sendIpc(cmd);
    } catch (e) {
      _patch(message: '$e');
    }
  }

  /// 校准开始前快照：取消时用 [restoreAfterCalibrationCancel] 还原。
  /// soft_off 会清空 [_lastSentSolid]，须在 soft_off 之前调用。
  ({bool wantEngine, String? solid}) captureSceneForCalibration() {
    final solid =
        !_engineWanted && _lastSentSolid != null && _lastSentSolid!.isNotEmpty
        ? _lastSentSolid
        : null;
    return (
      wantEngine: _engineWanted || state.engineRunning,
      solid: solid,
    );
  }

  /// 校准取消：恢复进入校准前的追色 / 纯色 / 熄灯。
  void restoreAfterCalibrationCancel({
    required bool wantEngine,
    String? solid,
  }) {
    if (!_client.isConnected) return;
    if (wantEngine) {
      send('start');
    } else if (solid != null && solid.isNotEmpty) {
      sendSolid(solid);
    } else {
      // ready 或 poweredOff：软关清掉 highlight 残段
      softOff();
    }
  }

  Future<void> quit() async {
    _cancelPendingSolid();
    await _client.quit();
  }
}

final helperStateProvider =
    NotifierProvider<HelperStateNotifier, HelperUiState>(
      HelperStateNotifier.new,
    );
