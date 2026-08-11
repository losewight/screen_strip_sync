import '../ipc/windows_com_ports.dart';

/// 连接 / 引擎相位（按钮禁用态与徽标用）。
enum HelperPhase {
  disconnected,
  connecting,
  ready,
  running,

  /// IPC 仍通，软关（黑帧、电源未断）；可再 solid/start 唤醒。
  /// 真下电（`set_power 0`）只在退进程 `quit` → helper_shutdown。
  poweredOff,

  /// IPC 已通，串口尚未打开（含首启未配备，等用户点「连接」）。
  needConnect,

  /// 已配备但开口 / 握手失败。
  openFailed,
  failed,
}

/// 主控 UI 只读快照：相位 + 状态条文案 + 串口列表。
class HelperUiState {
  const HelperUiState({
    required this.phase,
    required this.message,
    this.ports = const [],
    this.currentCom = '',
    this.lastGoodCom = '',
    this.hasDevice = false,
    this.isScanningPorts = false,
    this.engineRunning = false,
  });

  final HelperPhase phase;
  final String message;

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
