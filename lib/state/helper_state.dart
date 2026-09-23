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
    // 为什么：cfg end 前默认 serialConfigured=false，不能当成真·未配备去 set com
    if (!ref.read(configProvider.notifier).hasSnapshot) return;
    // 已连接时只改本地配置；真正切口点「换口连接」（同口恢复才用「重连串口」）
    sendComPort(name);
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

  /// D1：连续够暗帧数才灭；helper clamp 1..10。不落盘。
  @override
  void sendDeadzoneN(int n) {
    if (!_client.isConnected) return;
    try {
      final v = n.clamp(1, 10);
      _sendIpc('set deadzone_n $v');
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
  void sendSampleAlgo(SampleAlgo algo) {
    if (!_client.isConnected) return;
    try {
      final word = switch (algo) {
        SampleAlgo.rms => 'rms',
        SampleAlgo.mean => 'mean',
      };
      _sendIpc('set sample_algo $word');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendNearBlackLuma(NearBlackLuma luma) {
    if (!_client.isConnected) return;
    try {
      final word = switch (luma) {
        NearBlackLuma.rec601 => 'rec601',
        NearBlackLuma.mean => 'mean',
      };
      _sendIpc('set near_black_luma $word');
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
      _lastDisplay = HelperDisplayKind.region;
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
  void sendLetterboxDetect(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set letterbox_detect ${enabled ? 1 : 0}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

  @override
  void sendLetterboxHold(bool hold) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set letterbox_hold ${hold ? 1 : 0}');
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

  @override
  void sendCaptureOutput(String name) {
    if (!_client.isConnected) return;
    final wanted = name.trim();
    if (wanted.isEmpty) return;
    ref.read(configProvider.notifier).setCaptureOutput(wanted);
    try {
      _sendIpc('set capture_output $wanted');
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

  /// 息屏关灯开关：已连接则下发；未连接静默。
  @override
  void sendScreenOffSync(bool enabled) {
    if (!_client.isConnected) return;
    try {
      _sendIpc('set screen_off_sync ${enabled ? 1 : 0}');
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

  /// UI「关灯」：发 `soft_off`（停引擎 + 纯黑一帧），不掉电。
  /// 勿与备用命令 `off`（`set_power 0`）混淆；真下电只走 `quit`。
  void softOff() {
    if (!_client.isConnected) return;
    try {
      _cancelPendingSolid();
      _lastSentSolid = null;
      _engineWanted = false;
      _lastDisplay = HelperDisplayKind.softOff;
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
        _lastDisplay = HelperDisplayKind.engine;
        _patch(
          message: '引擎运行中',
          phase: HelperPhase.running,
          engineRunning: true,
        );
      } else if (cmd == 'stop') {
        _engineWanted = false;
        _lastSentSolid = null;
        _lastDisplay = HelperDisplayKind.idle;
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
        _lastDisplay = HelperDisplayKind.softOff;
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
  CalibrationSceneSnapshot captureSceneForCalibration() {
    final kind = _calibrationKindNow();
    String? solid;
    if (kind == CalibrationSceneKind.solid) {
      solid = _lastSentSolid;
      if (solid == null || solid.isEmpty) {
        solid = _solidHexFromConfig();
      }
    }
    return CalibrationSceneSnapshot(kind: kind, solidHex: solid);
  }

  CalibrationSceneKind _calibrationKindNow() {
    switch (_lastDisplay) {
      case HelperDisplayKind.engine:
        return CalibrationSceneKind.engine;
      case HelperDisplayKind.region:
        return CalibrationSceneKind.region;
      case HelperDisplayKind.solid:
        return CalibrationSceneKind.solid;
      case HelperDisplayKind.softOff:
        return CalibrationSceneKind.off;
      case HelperDisplayKind.idle:
        break;
    }
    final scene = ref.read(configProvider).lastScene.trim();
    if (scene == 'engine') return CalibrationSceneKind.engine;
    if (scene == 'region') return CalibrationSceneKind.region;
    if (scene == 'off') return CalibrationSceneKind.off;
    if (scene.startsWith('solid ')) return CalibrationSceneKind.solid;
    if (_engineWanted || state.engineRunning) {
      return CalibrationSceneKind.engine;
    }
    if (_lastSentSolid != null && _lastSentSolid!.isNotEmpty) {
      return CalibrationSceneKind.solid;
    }
    return CalibrationSceneKind.off;
  }

  String? _solidHexFromConfig() {
    final cfg = ref.read(configProvider);
    const prefix = 'solid ';
    final scene = cfg.lastScene.trim();
    if (scene.startsWith(prefix)) {
      final h = scene.substring(prefix.length).trim().toLowerCase();
      if (RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) return h;
    }
    final custom = cfg.lastCustomSolid.trim().toLowerCase();
    if (RegExp(r'^[0-9a-f]{6}$').hasMatch(custom)) return custom;
    return null;
  }

  /// 校准取消：按进入前的 engine / region / solid / off 分别还原。
  void restoreAfterCalibrationCancel(CalibrationSceneSnapshot snap) {
    if (!_client.isConnected) return;
    switch (snap.kind) {
      case CalibrationSceneKind.engine:
        send('start');
      case CalibrationSceneKind.region:
        startRegion();
      case CalibrationSceneKind.solid:
        final hex = snap.solidHex;
        if (hex != null && hex.isNotEmpty) {
          sendSolid(hex);
        } else {
          softOff();
        }
      case CalibrationSceneKind.off:
        softOff();
    }
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
