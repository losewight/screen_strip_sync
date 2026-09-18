import '../ipc/windows_com_ports.dart';

/// 校准开始前的灯效场景；取消时按此还原（完成校准仍走 `start`）。
enum CalibrationSceneKind { engine, region, solid, off }

/// 进入校准前的快照。须在 `soft_off` 之前采集。
class CalibrationSceneSnapshot {
  const CalibrationSceneSnapshot({required this.kind, this.solidHex});

  final CalibrationSceneKind kind;

  /// [CalibrationSceneKind.solid] 时的 6 位 hex；其它场景可空。
  final String? solidHex;
}

/// helper 枚举 / 当前抓取的一块屏（桌面矩形为虚拟桌面物理像素）。
class CaptureOutputInfo {
  const CaptureOutputInfo({
    required this.name,
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    this.isPrimary = false,
    this.isCurrent = false,
    this.friendlyName = '',
  });

  /// DXGI DeviceName，如 `\\.\DISPLAY1`。选屏身份用这个，不要用友好名。
  final String name;
  final int width;
  final int height;
  final int left;
  final int top;
  final bool isPrimary;
  final bool isCurrent;

  /// CCD/EDID 友好名（如 `Q27G4SL_WS`）；查不到为空。
  final String friendlyName;

  /// 去掉 `\\.\` 前缀后的短名，如 `DISPLAY1`。
  static String toShortName(String name) {
    const prefix = r'\\.\';
    final t = name.trim();
    return t.startsWith(prefix) ? t.substring(prefix.length) : t;
  }

  String get shortName => toShortName(name);

  /// 下拉 / 跟随文案：有友好名用友好名，否则 DISPLAY1。
  String get displayLabel {
    final f = friendlyName.trim();
    if (f.isNotEmpty) return f;
    return shortName;
  }
}

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
    this.snapshotTimedOut = false,
    this.captureOutputs = const [],
    this.currentCapture,
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

  /// 已连上 IPC 但约 2s 内未收到 `cfg end`（壳层显示「后台服务未响应」）。
  final bool snapshotTimedOut;

  /// helper 当前 adapter 能 duplicate 的屏（`status output` 收齐后落盘）。
  final List<CaptureOutputInfo> captureOutputs;

  /// 当前真正抓的那块（`status capture_output`）；未上报为 null。
  final CaptureOutputInfo? currentCapture;

  /// 换口判断锚点：优先当前打开口，否则用上次成功口。
  String get anchorCom => currentCom.isNotEmpty ? currentCom : lastGoodCom;

  /// 已接通 IPC，可发控灯命令（含关灯后的 poweredOff）。
  bool get canControl =>
      phase == HelperPhase.ready ||
      phase == HelperPhase.running ||
      phase == HelperPhase.poweredOff;

  /// 框选/校准时提示正在跟哪块屏；优先 status 真值，否则 cfg。
  String? followCaptureLabel(String cfgCapture) {
    final cur = currentCapture;
    if (cur != null) {
      final label = cur.displayLabel;
      if (label.isNotEmpty) return label;
    }
    final c = cfgCapture.trim();
    if (c.isEmpty || c == 'auto') return null;
    for (final o in captureOutputs) {
      if (o.name == c) return o.displayLabel;
    }
    return CaptureOutputInfo.toShortName(c);
  }
}
