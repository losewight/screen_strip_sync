import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config_state.dart';

/// 连接 / 引擎相位（按钮禁用态与徽标用）。
enum HelperPhase {
  disconnected,
  connecting,
  ready,
  running,

  /// IPC 仍通，但已 `off`（set_power 0）；可再 solid/start 唤醒。
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
    this.allPorts = const [],
    this.ch340Ports = const [],
    this.currentCom = '',
    this.hasDevice = false,
  });

  final HelperPhase phase;
  final String message;
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

/// UI 层 helper 状态；IPC 客户端已移除，方法仅更新本地快照供界面展示。
class HelperStateNotifier extends Notifier<HelperUiState> {
  static const _ipcRemovedMessage = 'IPC 通信未接入';

  @override
  HelperUiState build() {
    return const HelperUiState(
      phase: HelperPhase.disconnected,
      message: _ipcRemovedMessage,
    );
  }

  void _set(String message, {HelperPhase? phase}) {
    state = HelperUiState(
      phase: phase ?? state.phase,
      message: message,
      allPorts: state.allPorts,
      ch340Ports: state.ch340Ports,
      currentCom: state.currentCom,
      hasDevice: state.hasDevice,
    );
  }

  /// UI 选口：只写本地配置。
  void selectComPort(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    ref.read(configProvider.notifier).setComPort(name);
    _set('已选择 $name（IPC 未接入，暂无法连接）');
  }

  Future<void> connect() async {
    _set('连接不可用：IPC 通信未接入', phase: HelperPhase.failed);
  }

  void sendEmaAlpha(double _) {}

  void sendMode(ColorMode _) {}

  void sendComPort(String _) {}

  Future<void> scanPorts() async {
    _set('串口扫描不可用：IPC 通信未接入');
  }

  Future<void> reconnectSerial() async {
    await scanPorts();
  }

  void sendSolid(String _) {}

  void send(String _) {}

  Future<void> reconnectAfterResume() async {}

  bool get isReady => false;
}

final helperStateProvider =
    NotifierProvider<HelperStateNotifier, HelperUiState>(
      HelperStateNotifier.new,
    );
