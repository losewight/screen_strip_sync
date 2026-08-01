/// 双调色方案（阶段 C 才真正进引擎；此处只存用户意图）。
enum ColorMode {
  /// 方案 A：高亮度 + RGB 跟屏色
  a,

  /// 方案 B：luma → Brightness + 亮度 EMA
  b,
}

/// 用户可改参数快照（A5 落盘；B 才下发 helper）。
///
/// 帧长 / 50ms 节流永不进此类。
class AppConfig {
  const AppConfig({
    this.emaAlpha = 0.3,
    this.mode = ColorMode.a,
    this.comPort = 'COM10',
    this.lastConnectedCom = '',
    this.autoSleepSync = true,
    this.turnOffOnShutdown = true,
    this.startOnBoot = false,
  });

  /// EMA 平滑系数，与 helper 当前写死的 `0.3f` 对齐；取值域约 0.05..1.0。
  final double emaAlpha;

  final ColorMode mode;

  /// 串口名，如 `COM10`；下拉/手输的当前选中。
  final String comPort;

  /// helper 曾成功打开的口；空表示从未连上过，不走快速连接。
  final String lastConnectedCom;

  /// 显示器息屏时是否自动熄灯；暂不下发 helper。
  final bool autoSleepSync;

  /// Windows 关机时是否自动关闭灯带；暂不下发 helper。
  final bool turnOffOnShutdown;

  /// 软件随系统启动后是否自动启动灯带；暂不下发 helper。
  final bool startOnBoot;

  AppConfig copyWith({
    double? emaAlpha,
    ColorMode? mode,
    String? comPort,
    String? lastConnectedCom,
    bool? autoSleepSync,
    bool? turnOffOnShutdown,
    bool? startOnBoot,
  }) {
    return AppConfig(
      emaAlpha: emaAlpha ?? this.emaAlpha,
      mode: mode ?? this.mode,
      comPort: comPort ?? this.comPort,
      lastConnectedCom: lastConnectedCom ?? this.lastConnectedCom,
      autoSleepSync: autoSleepSync ?? this.autoSleepSync,
      turnOffOnShutdown: turnOffOnShutdown ?? this.turnOffOnShutdown,
      startOnBoot: startOnBoot ?? this.startOnBoot,
    );
  }

  /// 非法 / 缺字段回退默认，不抛。
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final rawAlpha = json['emaAlpha'];
    final alpha = switch (rawAlpha) {
      num n => n.toDouble().clamp(0.05, 1.0),
      _ => 0.3,
    };

    final mode = switch (json['mode']) {
      'b' || 'B' => ColorMode.b,
      _ => ColorMode.a,
    };

    final rawCom = json['comPort'];
    final com = switch (rawCom) {
      String s when s.trim().isNotEmpty => s.trim(),
      _ => 'COM10',
    };

    final rawLastCom = json['lastConnectedCom'];
    final lastCom = switch (rawLastCom) {
      String s => s.trim(),
      _ => '',
    };

    final autoSleepSync = switch (json['autoSleepSync']) {
      bool b => b,
      _ => true,
    };

    final turnOffOnShutdown = switch (json['turnOffOnShutdown']) {
      bool b => b,
      _ => true,
    };

    final startOnBoot = switch (json['startOnBoot']) {
      bool b => b,
      _ => false,
    };

    return AppConfig(
      emaAlpha: alpha,
      mode: mode,
      comPort: com,
      lastConnectedCom: lastCom,
      autoSleepSync: autoSleepSync,
      turnOffOnShutdown: turnOffOnShutdown,
      startOnBoot: startOnBoot,
    );
  }

  Map<String, dynamic> toJson() => {
    'emaAlpha': emaAlpha,
    'mode': switch (mode) {
      ColorMode.a => 'a',
      ColorMode.b => 'b',
    },
    'comPort': comPort,
    'lastConnectedCom': lastConnectedCom,
    'autoSleepSync': autoSleepSync,
    'turnOffOnShutdown': turnOffOnShutdown,
    'startOnBoot': startOnBoot,
  };
}
