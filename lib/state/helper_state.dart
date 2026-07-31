import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ipc/helper_client.dart';
import '../ipc/helper_status.dart';
import '../ipc/windows_com_ports.dart';
import 'config_state.dart';

/// 连接 / 引擎相位（按钮禁用态与徽标用）。
enum HelperPhase {
  disconnected,
  connecting,
  ready,
  running,

  /// IPC 仍通，软关（黑帧、电源未断）；可再 solid/start 唤醒。
  /// 真下电（`set_power 0`）只在退进程 `quit` → helper_shutdown。
  poweredOff,

  /// IPC 通，但串口未打开（扫描无口 / 开口失败）。
  noDevice,
  failed,
}

/// 主控 UI 只读快照：相位 + 状态条文案 + 串口列表。
class HelperUiState {
  const HelperUiState({
    required this.phase,
    required this.message,
    this.ipcLine = '',
    this.allPorts = const [],
    this.ch340Ports = const [],
    this.currentCom = '',
    this.hasDevice = false,
  });

  final HelperPhase phase;
  final String message;

  /// 最近经 Socket 发出的 IPC 行（含 `\n`），供状态徽标小字展示。
  final String ipcLine;
  final List<String> allPorts;
  final List<String> ch340Ports;
  final String currentCom;
  final bool hasDevice;

  /// 已接通 IPC，可发控灯命令（含关灯后的 poweredOff）。
  bool get canControl =>
      phase == HelperPhase.ready ||
      phase == HelperPhase.running ||
      phase == HelperPhase.poweredOff;

  /// 除连接过程外都可点：已连通就重试串口，未连通则只刷新扫描列表。
  bool get canReconnectSerial => phase != HelperPhase.connecting;
}

class HelperStateNotifier extends Notifier<HelperUiState> {
  /// 与串口 ≥50ms 对齐；冷却期内只保留最新色。
  static const _solidCooldown = Duration(milliseconds: 70);

  StreamSubscription<HelperStatusWord>? _statusSub;
  StreamSubscription<void>? _disconnectSub;
  bool _engineWanted = false;
  bool _resumeBusy = false;
  String? _pendingSolid;
  Timer? _solidTimer;
  String? _lastSentSolid;

  HelperClient get _client => ref.read(helperClientProvider);

  @override
  HelperUiState build() {
    _statusSub ??= _client.statusStream.listen(_onStatusWord);
    _disconnectSub ??= _client.disconnectStream.listen((_) {
      _cancelPendingSolid();
      _patch(
        message: 'helper 已断开',
        phase: HelperPhase.disconnected,
        hasDevice: false,
      );
    });
    ref.onDispose(() {
      _cancelPendingSolid();
      _statusSub?.cancel();
      _disconnectSub?.cancel();
    });
    return const HelperUiState(
      phase: HelperPhase.disconnected,
      message: '未连接',
    );
  }

  /// 丢弃未发出的纯色，避免关窗/熄灯后补发走马灯。
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
    _solidTimer = Timer(_solidCooldown, _onSolidCooldownEnd);
  }

  bool get isReady => _client.isConnected && state.canControl;

  void _patch({
    String? message,
    String? ipcLine,
    HelperPhase? phase,
    List<String>? allPorts,
    List<String>? ch340Ports,
    String? currentCom,
    bool? hasDevice,
  }) {
    state = HelperUiState(
      phase: phase ?? state.phase,
      message: message ?? state.message,
      ipcLine: ipcLine ?? state.ipcLine,
      allPorts: allPorts ?? state.allPorts,
      ch340Ports: ch340Ports ?? state.ch340Ports,
      currentCom: currentCom ?? state.currentCom,
      hasDevice: hasDevice ?? state.hasDevice,
    );
  }

  void _sendIpc(String cmd) {
    _client.send(cmd);
    _patch(ipcLine: '$cmd\n');
  }

  void _onStatusWord(HelperStatusWord word) {
    switch (word) {
      case HelperStatusWord.ready:
        final com = ref.read(configProvider).comPort;
        _patch(
          message: '串口就绪',
          phase: HelperPhase.ready,
          currentCom: com,
          hasDevice: true,
        );
      case HelperStatusWord.reconnecting:
        _patch(message: '正在重连串口…');
      case HelperStatusWord.reconnectOk:
        _patch(message: '重连成功', hasDevice: true);
      case HelperStatusWord.reconnectFail:
        _patch(message: '重连失败', hasDevice: false);
      case HelperStatusWord.unknown:
        break;
    }
  }

  void selectComPort(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    ref.read(configProvider.notifier).setComPort(name);
    _patch(message: '已选择 $name');
  }

  Future<void> connect() async {
    if (state.phase == HelperPhase.connecting) return;
    if (_client.isConnected && state.canControl) return;

    if (_client.isConnected) {
      _cancelPendingSolid();
      await _client.quit();
      _patch(message: '重新连接…', phase: HelperPhase.disconnected);
    }

    _patch(message: '启动 helper…', phase: HelperPhase.connecting);
    try {
      await _client.connect();
      _patch(message: '已连接，等待 helper 状态…');
    } catch (e) {
      _patch(message: '$e', phase: HelperPhase.failed, hasDevice: false);
    }
  }

  void sendEmaAlpha(double _) {}

  void sendMode(ColorMode _) {}

  void sendComPort(String _) {}

  Future<void> scanPorts() async {
    final scanned = await scanWindowsComPorts();
    _patch(
      message: scanned.all.isEmpty ? '未发现串口' : '已扫描 ${scanned.all.length} 个串口',
      allPorts: scanned.all,
      ch340Ports: scanned.ch340,
    );
  }

  Future<void> reconnectSerial() async {
    if (!_client.isConnected) {
      await scanPorts();
      return;
    }
    try {
      _sendIpc('reconnect');
    } catch (e) {
      _patch(message: '$e');
    }
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
        _solidTimer = Timer(_solidCooldown, _onSolidCooldownEnd);
      }
      // else：冷却中只更新 pending，等 _onSolidCooldownEnd trailing
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
        _patch(message: '引擎运行中', phase: HelperPhase.running);
      } else if (cmd == 'stop') {
        _engineWanted = false;
        _patch(message: '引擎已停止', phase: HelperPhase.ready);
      } else if (cmd == 'off') {
        // 备用真下电；UI 关灯请用 softOff()
        _cancelPendingSolid();
        _lastSentSolid = null;
        _engineWanted = false;
        _patch(
          message: '已下电',
          phase: HelperPhase.poweredOff,
          hasDevice: true,
        );
      }
      _sendIpc(cmd);
    } catch (e) {
      _patch(message: '$e');
    }
  }

  Future<void> reconnectAfterResume() async {
    if (_resumeBusy) return;
    _resumeBusy = true;
    try {
      _cancelPendingSolid();
      _patch(message: '系统唤醒，3 秒后重连…');
      await Future<void>.delayed(const Duration(seconds: 3));

      final wantEngine = _engineWanted;
      await _client.quit();
      _engineWanted = false;
      _patch(message: '正在重连…', phase: HelperPhase.disconnected);

      const maxAttempts = 5;
      for (var left = maxAttempts; left >= 1; left--) {
        try {
          await connect();
          if (_client.isConnected && state.phase == HelperPhase.ready) {
            if (wantEngine) send('start');
            return;
          }
        } catch (_) {}
        if (left > 1) {
          _patch(message: '重连失败，2 秒后重试（剩 ${left - 1}）…');
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      _patch(
        message: '唤醒后重连失败，请手动点「连接」',
        phase: HelperPhase.failed,
      );
    } finally {
      _resumeBusy = false;
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
