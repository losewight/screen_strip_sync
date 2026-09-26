import 'region_bbox.dart';
import 'segment_map_codec.dart';
import 'segment_sample.dart';

export 'region_bbox.dart';
export 'segment_sample.dart';

/// 双调色方案字段保留存盘兼容；亮度模型已废弃，引擎不读。
enum ColorMode {
  /// 历史方案 A（废弃）
  a,

  /// 历史方案 B（废弃）
  b,
}

/// map 采样聚合（与 helper `sample_algo rms|mean` 对齐）。
enum SampleAlgo {
  rms,
  mean,
}

/// map 饱和度算法（UI 已撤；固定减去中性色）。
enum SaturationAlgo {
  /// 保持亮度：Rec.601 亮度守恒，拉开偏离灰的距离，亮度轴不动（仅旧兼容）。
  luma,

  /// 减去三通道共有的中性分量；sat>1 时 k=sat-1（当前固定）。
  neutral,
}

/// 近黑亮度算法（与 helper 对齐；UI 已撤，固定 Rec.601）。
enum NearBlackLuma {
  /// Rec.601 加权；绿权重大，暗绿更易被剔、暗蓝更易保留。
  rec601,

  /// (R+G+B)/3；三通道等权（仅旧 JSON 兼容，加载时钳为 rec601）。
  mean,
}

/// 用户可改参数快照（由 helper `cfg …` 驱动；Flutter 不写盘）。
///
/// 帧长 / 50ms 节流永不进此类。
class AppConfig {
  const AppConfig({
    this.emaAlpha = 1.0,
    this.nearBlack = 30,
    this.blurStep = 0,
    this.saturation = 1.0,
    this.saturationAlgo = SaturationAlgo.neutral,
    this.sampleAlgo = SampleAlgo.mean,
    this.nearBlackLuma = NearBlackLuma.rec601,
    this.mode = ColorMode.a,
    this.comPort = 'COM10',
    this.captureOutput = 'auto',
    this.lastConnectedCom = '',
    this.serialConfigured = false,
    this.autoSleepSync = true,
    this.screenOffSync = false,
    this.turnOffOnShutdown = true,
    this.startOnBoot = false,
    this.segmentMap,
    this.regionAlgo = RegionAlgo.mean,
    this.regionBlur = 3,
    this.regionSmooth = 0.8,
    this.regionDark = 15,
    this.regionBBox = const RegionBBox(),
    this.lastScene = 'idle',
    this.lastCustomSolid = '',
    this.wallCompEnabled = false,
    this.wallColor = '',
    this.letterboxDetect = true,
  });

  /// EMA 平滑系数；取值域约 0.05..1.0（屏幕跟色 map 路径）。
  final double emaAlpha;

  /// 丢近黑像素（亮度低于此跳过）；0..64；亮度算法固定 Rec.601。
  final int nearBlack;

  /// 采样邻域半宽（空间降噪）；0..8，0=不扩邻域。
  final int blurStep;

  /// 饱和度增益 0.5..2.0；1.0=原色，默认 1.0（100%）。
  final double saturation;

  /// 饱和度算法：固定减去中性色；luma 仅旧 cfg 兼容。
  final SaturationAlgo saturationAlgo;

  /// map 采样聚合：固定算术平均（更接近光学混合）；RMS 仅旧 JSON 兼容。
  final SampleAlgo sampleAlgo;

  /// 近黑亮度：固定 Rec.601；mean 仅旧 JSON 兼容。
  final NearBlackLuma nearBlackLuma;

  final ColorMode mode;

  /// 串口名，如 `COM10`；下拉/手输的当前选中。
  final String comPort;

  /// DXGI 抓屏目标；`auto` = 主屏再序号 0，否则为 DeviceName（如 `\\.\DISPLAY1`）。
  final String captureOutput;

  /// helper 曾成功打开的口；空表示从未连上过，不走快速连接。
  final String lastConnectedCom;

  /// 首启门闩：false=须点「连接」才开口；true=helper 启动可自动开口。
  final bool serialConfigured;

  /// 系统休眠时软关；唤醒后由 helper 按 lastScene 恢复。
  final bool autoSleepSync;

  /// 息屏时自动熄灭灯带，亮屏后恢复（与 sleep_sync 独立）。
  final bool screenOffSync;

  /// Windows 关机时是否自动关闭灯带；经 `set shutdown_off` 下发。
  final bool turnOffOnShutdown;

  /// 随 Windows 开机自启 helper（注册表 Run）；经 `set autostart` 下发。
  final bool startOnBoot;

  /// 10 段屏幕采样矩形；`null` = 未校准，helper 用顶边均分默认。
  final List<SegmentSample>? segmentMap;

  /// 屏幕氛围：均值 / 最大值聚合。
  final RegionAlgo regionAlgo;

  /// 屏幕氛围空间模糊 0..20。
  final int regionBlur;

  /// 屏幕氛围时间惯性 0..0.99（高=更钝）。
  final double regionSmooth;

  /// 屏幕氛围暗场阈值 0..50（RGB 皆低于此 → 段置黑）。
  final int regionDark;

  /// 屏幕氛围取色框（被抓那块屏的百分比）。
  final RegionBBox regionBBox;

  /// helper `cfg scene`；含 `engine` / `region` / …
  final String lastScene;

  /// 纯色「自定义」色圈；6 位小写 hex，空=未设。
  final String lastCustomSolid;

  /// 墙面色彩补偿开关；无 [wallColor] 时 helper 启用也 no-op。
  final bool wallCompEnabled;

  /// 墙面底色；6 位小写 hex，空=未校正。
  final String wallColor;

  /// 智能忽略电影黑边（letterbox）；采样 Y 映射进内容窗。
  final bool letterboxDetect;

  bool get hasSegmentMap =>
      segmentMap != null && segmentMap!.length == kSegmentCount;

  bool get hasWallColor =>
      RegExp(r'^[0-9a-f]{6}$').hasMatch(wallColor.trim().toLowerCase());

  AppConfig copyWith({
    double? emaAlpha,
    int? nearBlack,
    int? blurStep,
    double? saturation,
    SaturationAlgo? saturationAlgo,
    SampleAlgo? sampleAlgo,
    NearBlackLuma? nearBlackLuma,
    ColorMode? mode,
    String? comPort,
    String? captureOutput,
    String? lastConnectedCom,
    bool? serialConfigured,
    bool? autoSleepSync,
    bool? screenOffSync,
    bool? turnOffOnShutdown,
    bool? startOnBoot,
    List<SegmentSample>? segmentMap,
    bool clearSegmentMap = false,
    RegionAlgo? regionAlgo,
    int? regionBlur,
    double? regionSmooth,
    int? regionDark,
    RegionBBox? regionBBox,
    String? lastScene,
    String? lastCustomSolid,
    bool? wallCompEnabled,
    String? wallColor,
    bool? letterboxDetect,
  }) {
    return AppConfig(
      emaAlpha: emaAlpha ?? this.emaAlpha,
      nearBlack: nearBlack ?? this.nearBlack,
      blurStep: blurStep ?? this.blurStep,
      saturation: saturation ?? this.saturation,
      saturationAlgo: saturationAlgo ?? this.saturationAlgo,
      sampleAlgo: sampleAlgo ?? this.sampleAlgo,
      nearBlackLuma: nearBlackLuma ?? this.nearBlackLuma,
      mode: mode ?? this.mode,
      comPort: comPort ?? this.comPort,
      captureOutput: captureOutput ?? this.captureOutput,
      lastConnectedCom: lastConnectedCom ?? this.lastConnectedCom,
      serialConfigured: serialConfigured ?? this.serialConfigured,
      autoSleepSync: autoSleepSync ?? this.autoSleepSync,
      screenOffSync: screenOffSync ?? this.screenOffSync,
      turnOffOnShutdown: turnOffOnShutdown ?? this.turnOffOnShutdown,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      segmentMap: clearSegmentMap ? null : (segmentMap ?? this.segmentMap),
      regionAlgo: regionAlgo ?? this.regionAlgo,
      regionBlur: regionBlur ?? this.regionBlur,
      regionSmooth: regionSmooth ?? this.regionSmooth,
      regionDark: regionDark ?? this.regionDark,
      regionBBox: regionBBox ?? this.regionBBox,
      lastScene: lastScene ?? this.lastScene,
      lastCustomSolid: lastCustomSolid ?? this.lastCustomSolid,
      wallCompEnabled: wallCompEnabled ?? this.wallCompEnabled,
      wallColor: wallColor ?? this.wallColor,
      letterboxDetect: letterboxDetect ?? this.letterboxDetect,
    );
  }

  /// 解析 helper 推送的 `cfg …` 行（可含或不含 `cfg ` 前缀）；非法行忽略。
  ///
  /// 缺字段保留 [AppConfig] 默认值。不以 `cfg end` 为输入（调用方在 end 处组包）。
  factory AppConfig.fromCfgLines(Iterable<String> lines) {
    var alpha = 1.0;
    var nearBlack = 30;
    var blurStep = 0;
    var saturation = 1.0;
    var saturationAlgo = SaturationAlgo.neutral;
    var sampleAlgo = SampleAlgo.mean;
    var nearBlackLuma = NearBlackLuma.rec601;
    var mode = ColorMode.a;
    var com = 'COM10';
    var capture = 'auto';
    var lastCom = '';
    var serialConfigured = false;
    var sleepSync = true;
    var screenOffSync = false;
    var shutdownOff = true;
    var autostart = false;
    List<SegmentSample>? map;
    var regionAlgo = RegionAlgo.mean;
    var regionBlur = 3;
    var regionSmooth = 0.8;
    var regionDark = 15;
    var regionBBox = const RegionBBox();
    var scene = 'idle';
    var lastCustomSolid = '';
    var wallCompEnabled = false;
    var wallColor = '';
    var letterboxDetect = true;

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
        case 'saturation':
          final v = double.tryParse(val);
          if (v != null) saturation = v.clamp(0.5, 2.0);
        case 'saturation_algo':
          // UI 已撤；固定减去中性色（与 helper 钳制一致）。
          saturationAlgo = SaturationAlgo.neutral;
        case 'sample_algo':
          // UI 已撤；固定算术平均（与 helper 钳制一致）。
          sampleAlgo = SampleAlgo.mean;
        case 'near_black_luma':
          // UI 已撤；固定 Rec.601（与 helper 钳制一致）。
          nearBlackLuma = NearBlackLuma.rec601;
        case 'mode':
          mode = switch (val) {
            'b' || 'B' => ColorMode.b,
            _ => ColorMode.a,
          };
        case 'com':
          if (val.isNotEmpty) com = val;
        case 'capture_output':
          if (val.isNotEmpty) capture = val;
        case 'last_com':
          lastCom = val;
        case 'serial_configured':
          if (val == '0' || val == '1') serialConfigured = val == '1';
        case 'sleep_sync':
          if (val == '0' || val == '1') sleepSync = val == '1';
        case 'screen_off_sync':
          if (val == '0' || val == '1') screenOffSync = val == '1';
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
        case 'region_algo':
          regionAlgo = switch (val) {
            'max' => RegionAlgo.max,
            _ => RegionAlgo.mean,
          };
        case 'region_blur':
          final v = int.tryParse(val);
          if (v != null) regionBlur = v.clamp(0, 20);
        case 'region_smooth':
          final v = double.tryParse(val);
          if (v != null) regionSmooth = v.clamp(0.0, 0.99);
        case 'region_dark':
          final v = int.tryParse(val);
          if (v != null) regionDark = v.clamp(0, 50);
        case 'region_bbox':
          final box = RegionBBox.tryParse(val);
          if (box != null) regionBBox = box;
        case 'scene':
          if (val.isNotEmpty) scene = val;
        case 'last_custom_solid':
          final h = val.trim().toLowerCase();
          if (RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) {
            lastCustomSolid = h;
          } else if (h.isEmpty) {
            lastCustomSolid = '';
          }
        case 'wall_comp':
          if (val == '0' || val == '1') wallCompEnabled = val == '1';
        case 'letterbox_detect':
          if (val == '0' || val == '1') letterboxDetect = val == '1';
        case 'wall_color':
          final h = val.trim().toLowerCase();
          if (RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) {
            wallColor = h;
          } else if (h.isEmpty) {
            wallColor = '';
          }
        default:
          break;
      }
    }

    return AppConfig(
      emaAlpha: alpha,
      nearBlack: nearBlack,
      blurStep: blurStep,
      saturation: saturation,
      saturationAlgo: saturationAlgo,
      sampleAlgo: sampleAlgo,
      nearBlackLuma: nearBlackLuma,
      mode: mode,
      comPort: com,
      captureOutput: capture,
      lastConnectedCom: lastCom,
      serialConfigured: serialConfigured,
      autoSleepSync: sleepSync,
      screenOffSync: screenOffSync,
      turnOffOnShutdown: shutdownOff,
      startOnBoot: autostart,
      segmentMap: map,
      regionAlgo: regionAlgo,
      regionBlur: regionBlur,
      regionSmooth: regionSmooth,
      regionDark: regionDark,
      regionBBox: regionBBox,
      lastScene: scene,
      lastCustomSolid: lastCustomSolid,
      wallCompEnabled: wallCompEnabled,
      wallColor: wallColor,
      letterboxDetect: letterboxDetect,
    );
  }
}
