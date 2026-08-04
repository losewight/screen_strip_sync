import 'segment_map_codec.dart';
import 'segment_sample.dart';

export 'segment_sample.dart';

/// 双调色方案（阶段 C 才真正进引擎；此处只存用户意图）。
enum ColorMode {
  /// 方案 A：高亮度 + RGB 跟屏色
  a,

  /// 方案 B：luma → Brightness + 亮度 EMA
  b,
}

/// 用户可改参数快照（由 helper `cfg …` 驱动；Flutter 不写盘）。
///
/// 帧长 / 50ms 节流永不进此类。
class AppConfig {
  const AppConfig({
    this.emaAlpha = 0.3,
    this.nearBlack = 12,
    this.blurStep = 2,
    this.mode = ColorMode.a,
    this.comPort = 'COM10',
    this.lastConnectedCom = '',
    this.autoSleepSync = true,
    this.turnOffOnShutdown = true,
    this.startOnBoot = false,
    this.segmentMap,
    this.lastScene = 'idle',
  });

  /// EMA 平滑系数；取值域约 0.05..1.0。
  final double emaAlpha;

  /// 丢近黑阈值（`(R+G+B)/3` 低于此跳过）；0..64。
  final int nearBlack;

  /// 采样邻域半宽（空间降噪）；0..8，0=不扩邻域。
  final int blurStep;

  final ColorMode mode;

  /// 串口名，如 `COM10`；下拉/手输的当前选中。
  final String comPort;

  /// helper 曾成功打开的口；空表示从未连上过，不走快速连接。
  final String lastConnectedCom;

  /// 系统休眠时软关；唤醒后由 helper 按 lastScene 恢复。
  final bool autoSleepSync;

  /// Windows 关机时是否自动关闭灯带；经 `set shutdown_off` 下发。
  final bool turnOffOnShutdown;

  /// 随 Windows 开机自启 helper（注册表 Run）；经 `set autostart` 下发。
  final bool startOnBoot;

  /// 10 段屏幕采样矩形；`null` = 未校准，helper 用顶边均分默认。
  final List<SegmentSample>? segmentMap;

  /// helper `cfg scene`；H8 前仅展示/记账用。
  final String lastScene;

  bool get hasSegmentMap =>
      segmentMap != null && segmentMap!.length == kSegmentCount;

  AppConfig copyWith({
    double? emaAlpha,
    int? nearBlack,
    int? blurStep,
    ColorMode? mode,
    String? comPort,
    String? lastConnectedCom,
    bool? autoSleepSync,
    bool? turnOffOnShutdown,
    bool? startOnBoot,
    List<SegmentSample>? segmentMap,
    bool clearSegmentMap = false,
    String? lastScene,
  }) {
    return AppConfig(
      emaAlpha: emaAlpha ?? this.emaAlpha,
      nearBlack: nearBlack ?? this.nearBlack,
      blurStep: blurStep ?? this.blurStep,
      mode: mode ?? this.mode,
      comPort: comPort ?? this.comPort,
      lastConnectedCom: lastConnectedCom ?? this.lastConnectedCom,
      autoSleepSync: autoSleepSync ?? this.autoSleepSync,
      turnOffOnShutdown: turnOffOnShutdown ?? this.turnOffOnShutdown,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      segmentMap: clearSegmentMap ? null : (segmentMap ?? this.segmentMap),
      lastScene: lastScene ?? this.lastScene,
    );
  }

  /// 解析 helper 推送的 `cfg …` 行（可含或不含 `cfg ` 前缀）；非法行忽略。
  ///
  /// 缺字段保留 [AppConfig] 默认值。不以 `cfg end` 为输入（调用方在 end 处组包）。
  factory AppConfig.fromCfgLines(Iterable<String> lines) {
    var alpha = 0.3;
    var nearBlack = 12;
    var blurStep = 2;
    var mode = ColorMode.a;
    var com = 'COM10';
    var lastCom = '';
    var sleepSync = true;
    var shutdownOff = true;
    var autostart = false;
    List<SegmentSample>? map;
    var scene = 'idle';

    for (final raw in lines) {
      var line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('cfg ')) {
        line = line.substring(4).trimLeft();
      }
      if (line == 'end') continue;

      final sp = line.indexOf(' ');
      final key = sp < 0 ? line : line.substring(0, sp);
      final val = sp < 0 ? '' : line.substring(sp + 1).trim();

      switch (key) {
        case 'alpha':
          final v = double.tryParse(val);
          if (v != null) alpha = v.clamp(0.05, 1.0);
        case 'near_black':
          final v = int.tryParse(val);
          if (v != null) nearBlack = v.clamp(0, 64);
        case 'blur':
          final v = int.tryParse(val);
          if (v != null) blurStep = v.clamp(0, 8);
        case 'mode':
          mode = switch (val) {
            'b' || 'B' => ColorMode.b,
            _ => ColorMode.a,
          };
        case 'com':
          if (val.isNotEmpty) com = val;
        case 'last_com':
          lastCom = val;
        case 'sleep_sync':
          if (val == '0' || val == '1') sleepSync = val == '1';
        case 'shutdown_off':
          if (val == '0' || val == '1') shutdownOff = val == '1';
        case 'autostart':
          if (val == '0' || val == '1') autostart = val == '1';
        case 'map':
          if (val == 'default' || val.isEmpty) {
            map = null;
          } else {
            map = SegmentMapCodec.decodeIpcPayload(val);
          }
        case 'scene':
          if (val.isNotEmpty) scene = val;
        default:
          break;
      }
    }

    return AppConfig(
      emaAlpha: alpha,
      nearBlack: nearBlack,
      blurStep: blurStep,
      mode: mode,
      comPort: com,
      lastConnectedCom: lastCom,
      autoSleepSync: sleepSync,
      turnOffOnShutdown: shutdownOff,
      startOnBoot: autostart,
      segmentMap: map,
      lastScene: scene,
    );
  }
}
