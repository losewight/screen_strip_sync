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
    this.ports = const [],
    this.currentCom = '',
    this.lastGoodCom = '',
    this.hasDevice = false,
    this.isScanningPorts = false,
    this.engineRunning = false,
  });

  final HelperPhase phase;
  final String message;

  /// 最近经 Socket 发出的 IPC 行（含 `\n`），供状态徽标小字展示。
  final String ipcLine;

  /// 本机扫描结果（preferred 已排前）。
  final List<ComPortInfo> ports;

  /// helper 当前打开的口；换口 quit 后会暂时清空。
  final String currentCom;

  /// 最近一次成功打开的口；换口失败后仍保留，供文案 / 换口判断。
  final String lastGoodCom;
  final bool hasDevice;

  /// 正在枚举本机 COM（刷新钮改加载圈）。
  final bool isScanningPorts;

  /// helper 追色发帧线程是否在跑（来自 `status engine`）。
  final bool engineRunning;

  /// 换口判断锚点：优先当前打开口，否则用上次成功口。
  String get anchorCom => currentCom.isNotEmpty ? currentCom : lastGoodCom;

  /// 已接通 IPC，可发控灯命令（含关灯后的 poweredOff）。
  bool get canControl =>
      phase == HelperPhase.ready ||
      phase == HelperPhase.running ||
      phase == HelperPhase.poweredOff;
}

class HelperStateNotifier extends Notifier<HelperUiState> {
  /// 与串口 ≥50ms 对齐；冷却期内只保留最新色。
  static const _solidCooldown = Duration(milliseconds: 70);

  StreamSubscription<HelperStatusEvent>? _statusSub;
  StreamSubscription<void>? _disconnectSub;
  bool _engineWanted = false;
  bool _resumeBusy = false;
  String? _pendingSolid;
  Timer? _solidTimer;
  String? _lastSentSolid;

  HelperClient get _client => ref.read(helperClientProvider);

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
    // 为什么：后台扫口刷新列表，不阻塞连接、不覆盖连接态文案
    Future.microtask(() async {
      unawaited(scanPorts(background: true));
      await _maybeConnectOnBoot();
    });
    final cfg = ref.read(configProvider);
    return HelperUiState(
      phase: HelperPhase.disconnected,
      message: '未连接',
      lastGoodCom: cfg.lastConnectedCom,
    );
  }

  /// 主控「开机时灯带自动启动」：进程起来后直连上次成功口，不等扫描。
  /// Windows 注册表自启仍属阶段 C；此处只响应 [AppConfig.startOnBoot]。
  Future<void> _maybeConnectOnBoot() async {
    final cfg = ref.read(configProvider);
    if (!cfg.startOnBoot) return;
    if (cfg.lastConnectedCom.trim().isEmpty) {
      _patch(message: '已开启开机启动，但尚无上次成功口，请先手动连接一次');
      return;
    }
    await connect();
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

  String _formatReadyMessage({required String com, required bool engine}) {
    if (com.isEmpty) return '串口就绪';
    if (engine) return '$com · 追色运行中';
    return '串口就绪（$com）';
  }

  void _onStatusEvent(HelperStatusEvent event) {
    switch (event) {
      case HelperStatusPhase(:final word):
        _onStatusPhase(word);
      case HelperStatusCom(:final port):
        _onStatusCom(port);
      case HelperStatusEngine(:final running):
        _onStatusEngine(running);
    }
  }

  /// helper 真值 COM：更新 UI 并落盘，供下次快速连接。
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
        final cfg = ref.read(configProvider);
        // 为什么：COM 真值等随后的 status com，此处不猜 cfg.comPort
        _patch(
          message: '串口就绪',
          phase: HelperPhase.ready,
          hasDevice: true,
          engineRunning: false,
        );
        sendEmaAlpha(cfg.emaAlpha);
        sendMode(cfg.mode);
        sendComPort(cfg.comPort);
      case HelperStatusWord.reconnecting:
        _patch(
          message: '正在重连串口…',
          phase: HelperPhase.connecting,
          hasDevice: false,
          engineRunning: false,
        );
      case HelperStatusWord.reconnectOk:
        // COM 真值由随后的 status com 写入
        _patch(
          message: '重连成功',
          hasDevice: true,
          phase: HelperPhase.ready,
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

  void selectComPort(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    ref.read(configProvider.notifier).setComPort(name);
    _patch(message: '已选择 $name');
    // 已连接时只改本地配置；真正切口点「换口连接」（同口恢复才用「重连串口」）
    sendComPort(name);
  }

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

    // 已连通且口未变：忽略重复点「连接」；换口 / 失败后重连要往下走
    if (_client.isConnected && state.canControl && !portChanged) return;

    if (_client.isConnected) {
      _cancelPendingSolid();
      await _client.quit();
      _patch(
        message: portChanged ? '换口，重启 helper…' : '重新连接…',
        phase: HelperPhase.disconnected,
        hasDevice: false,
        currentCom: '',
        // lastGoodCom 保留：新口失败后仍知道「上次成功是哪口」
      );
    }

    _patch(message: '启动 helper…', phase: HelperPhase.connecting);
    try {
      await _client.connect(comPort: targetCom);
      _patch(message: '已连接 IPC，等待串口状态…');
    } catch (e) {
      _patch(
        message: '$e',
        phase: HelperPhase.failed,
        hasDevice: false,
        currentCom: '',
      );
    }
  }

  /// 松手滑条后下发；helper 侧再 clamp。未连接则静默跳过（配置已由 ConfigNotifier 落盘）。
  void sendEmaAlpha(double alpha) {
    if (!_client.isConnected) return;
    try {
      final v = alpha.clamp(0.05, 1.0);
      _sendIpc('set alpha ${v.toStringAsFixed(2)}');
    } catch (e) {
      _patch(message: '$e');
    }
  }

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

      // 仅首装：无上次成功口时才用 CH340 推荐口填 comPort
      final last = ref.read(configProvider).lastConnectedCom.trim();
      if (last.isNotEmpty) return;

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
