/// 音乐动态配色（与 helper `music_palette vu|rainbow|fixed|level|screen` 对齐）。
enum MusicPalette {
  /// 经典绿 → 黄 → 红（按段位置）。
  vu,

  /// 彩虹流动。
  rainbow,

  /// 自选单色。
  fixed,

  /// 整条随音量变色。
  level,

  /// 动态取屏幕色彩。
  screen,
}

extension MusicPaletteIpc on MusicPalette {
  String get ipcWord => switch (this) {
    MusicPalette.vu => 'vu',
    MusicPalette.rainbow => 'rainbow',
    MusicPalette.fixed => 'fixed',
    MusicPalette.level => 'level',
    MusicPalette.screen => 'screen',
  };

  String get label => switch (this) {
    MusicPalette.vu => '经典绿黄红',
    MusicPalette.rainbow => '彩虹流动',
    MusicPalette.fixed => '自选单色',
    MusicPalette.level => '整条随音量变色',
    MusicPalette.screen => '动态取屏幕色彩',
  };

  static MusicPalette fromIpcWord(String value) {
    return switch (value.trim().toLowerCase()) {
      'rainbow' || 'r' => MusicPalette.rainbow,
      'fixed' || 'f' => MusicPalette.fixed,
      'level' || 'l' => MusicPalette.level,
      'screen' || 's' => MusicPalette.screen,
      _ => MusicPalette.vu,
    };
  }
}

/// 配色预览用 RGB（0..255）；与 helper `music_palette_color` 同公式。
typedef MusicRgb = ({int r, int g, int b});

/// 满电平时 10 格静态预览色；[Screen] 无 [Vu] 占位。
List<MusicRgb> musicPalettePreviewColors(
  MusicPalette palette, {
  String fixedHex = '00aaff',
  int nowMs = 0,
}) {
  final fixed = musicNormalizeFixedHex(fixedHex) ?? (r: 0, g: 0xaa, b: 0xff);
  return [
    for (var i = 0; i < 10; i++)
      musicPaletteColor(
        palette,
        t: i / 9.0,
        level: 1.0,
        nowMs: nowMs,
        fixed: fixed,
      ),
  ];
}

/// 单段配色；[t]/[level] 均钳到 0..1。
MusicRgb musicPaletteColor(
  MusicPalette palette, {
  required double t,
  required double level,
  int nowMs = 0,
  MusicRgb fixed = (r: 0, g: 0xaa, b: 0xff),
  MusicRgb? screenRgb,
}) {
  final tt = t.clamp(0.0, 1.0);
  final lv = level.clamp(0.0, 1.0);
  switch (palette) {
    case MusicPalette.vu:
      return _hsv(120.0 * (1.0 - tt), 1, 1);
    case MusicPalette.rainbow:
      final base = (nowMs / 1000.0) * 36.0;
      return _hsv((base + tt * 300.0) % 360.0, 1, 1);
    case MusicPalette.fixed:
      return musicNormalizeFixedRgb(fixed) ?? fixed;
    case MusicPalette.level:
      return _hsv(240.0 * (1.0 - lv), 1, 1);
    case MusicPalette.screen:
      return screenRgb ?? _hsv(120.0 * (1.0 - tt), 1, 1);
  }
}

/// 最大通道归一化到 255；全 0 返回 null。
MusicRgb? musicNormalizeFixedRgb(MusicRgb rgb) {
  final max = rgb.r > rgb.g
      ? (rgb.r > rgb.b ? rgb.r : rgb.b)
      : (rgb.g > rgb.b ? rgb.g : rgb.b);
  if (max <= 0) return null;
  if (max == 255) return rgb;
  return (
    r: ((rgb.r * 255) / max).round().clamp(0, 255),
    g: ((rgb.g * 255) / max).round().clamp(0, 255),
    b: ((rgb.b * 255) / max).round().clamp(0, 255),
  );
}

/// 解析并归一化 6 位 hex；非法或全黑返回 null。
MusicRgb? musicNormalizeFixedHex(String hex) {
  final h = hex.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) return null;
  final v = int.parse(h, radix: 16);
  return musicNormalizeFixedRgb((
    r: (v >> 16) & 0xff,
    g: (v >> 8) & 0xff,
    b: v & 0xff,
  ));
}

MusicRgb _hsv(double h, double s, double v) {
  final hue = ((h % 360) + 360) % 360;
  final c = v * s;
  final x = c * (1 - (((hue / 60) % 2) - 1).abs());
  final m = v - c;
  late final double rp, gp, bp;
  if (hue < 60) {
    rp = c;
    gp = x;
    bp = 0;
  } else if (hue < 120) {
    rp = x;
    gp = c;
    bp = 0;
  } else if (hue < 180) {
    rp = 0;
    gp = c;
    bp = x;
  } else if (hue < 240) {
    rp = 0;
    gp = x;
    bp = c;
  } else if (hue < 300) {
    rp = x;
    gp = 0;
    bp = c;
  } else {
    rp = c;
    gp = 0;
    bp = x;
  }
  return (
    r: ((rp + m) * 255).round().clamp(0, 255),
    g: ((gp + m) * 255).round().clamp(0, 255),
    b: ((bp + m) * 255).round().clamp(0, 255),
  );
}

/// 音乐动态音频来源（与 helper `music_source system|mic|both` 对齐）。
enum MusicPickupSource {
  speaker,
  microphone,
  both,
}

extension MusicPickupSourceIpc on MusicPickupSource {
  String get ipcWord => switch (this) {
    MusicPickupSource.speaker => 'system',
    MusicPickupSource.microphone => 'mic',
    MusicPickupSource.both => 'both',
  };

  String get label => switch (this) {
    MusicPickupSource.speaker => '系统声音',
    MusicPickupSource.microphone => '麦克风',
    MusicPickupSource.both => '系统声音 + 麦克风',
  };

  static MusicPickupSource fromIpcWord(String value) {
    return switch (value) {
      'mic' => MusicPickupSource.microphone,
      'both' => MusicPickupSource.both,
      _ => MusicPickupSource.speaker,
    };
  }
}

/// 音乐动态灯光模式（与 helper `music_layout linear|mirror` 对齐）。
enum MusicLightMode {
  /// 从一端向另一端按电平逐段点亮。
  startToEnd,

  /// 左右两半镜像点亮。
  dualMirror,
}

extension MusicLightModeIpc on MusicLightMode {
  String get ipcWord => switch (this) {
    MusicLightMode.startToEnd => 'linear',
    MusicLightMode.dualMirror => 'mirror',
  };

  String get label => switch (this) {
    MusicLightMode.startToEnd => '从头到尾',
    MusicLightMode.dualMirror => '双条镜像',
  };

  static MusicLightMode fromIpcWord(String value) {
    return switch (value) {
      'mirror' => MusicLightMode.dualMirror,
      _ => MusicLightMode.startToEnd,
    };
  }
}

/// 静音表现（与 helper `music_silence off|min` 对齐）。
enum MusicSilence {
  off,
  keepMin,
}

extension MusicSilenceIpc on MusicSilence {
  String get ipcWord => switch (this) {
    MusicSilence.off => 'off',
    MusicSilence.keepMin => 'min',
  };

  String get label => switch (this) {
    MusicSilence.off => '全灭',
    MusicSilence.keepMin => '保留最低一格',
  };

  static MusicSilence fromIpcWord(String value) {
    return switch (value) {
      'min' => MusicSilence.keepMin,
      _ => MusicSilence.off,
    };
  }
}

/// 双条镜像其余段处理（与 helper `music_rest off|peak|base` 对齐）。
enum MusicRest {
  off,
  peak,
  base,
}

extension MusicRestIpc on MusicRest {
  String get ipcWord => switch (this) {
    MusicRest.off => 'off',
    MusicRest.peak => 'peak',
    MusicRest.base => 'base',
  };

  String get label => switch (this) {
    MusicRest.off => '始终灭',
    MusicRest.peak => '满格闪亮',
    MusicRest.base => '跟随底色',
  };

  static MusicRest fromIpcWord(String value) {
    return switch (value) {
      'peak' => MusicRest.peak,
      'base' => MusicRest.base,
      _ => MusicRest.off,
    };
  }
}

/// 双条镜像四端点（与 helper `music_mirror l0,l1,r0,r1` 对齐；-1=未设）。
class MusicMirror {
  const MusicMirror({
    this.l0 = -1,
    this.l1 = -1,
    this.r0 = -1,
    this.r1 = -1,
  });

  static const none = MusicMirror();

  final int l0;
  final int l1;
  final int r0;
  final int r1;

  bool get isUnset => l0 < 0 && l1 < 0 && r0 < 0 && r1 < 0;

  /// 四端点均在 0..9 且左右段集合不相交。
  bool get isValid {
    if (!_inRange(l0) || !_inRange(l1) || !_inRange(r0) || !_inRange(r1)) {
      return false;
    }
    final left = leftSegments.toSet();
    final right = rightSegments.toSet();
    return left.isNotEmpty &&
        right.isNotEmpty &&
        left.intersection(right).isEmpty;
  }

  List<int> get leftSegments => _walk(l0, l1);
  List<int> get rightSegments => _walk(r0, r1);

  List<int> get restSegments {
    if (!isValid) return const [];
    final used = {...leftSegments, ...rightSegments};
    return [for (var i = 0; i < 10; i++) if (!used.contains(i)) i];
  }

  /// IPC：`l0,l1,r0,r1`（调用方对 [none] 发 `clear`）。
  String toIpcPayload() => '$l0,$l1,$r0,$r1';

  /// 解析 `l0,l1,r0,r1` 或 `none`；非法返回 null。
  static MusicMirror? tryParse(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t == 'none') return MusicMirror.none;
    final parts = t.split(',');
    if (parts.length != 4) return null;
    final vals = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p.trim());
      if (v == null) return null;
      vals.add(v);
    }
    final m = MusicMirror(l0: vals[0], l1: vals[1], r0: vals[2], r1: vals[3]);
    if (m.isUnset) return MusicMirror.none;
    return m.isValid ? m : null;
  }

  MusicMirror copyWith({int? l0, int? l1, int? r0, int? r1}) {
    return MusicMirror(
      l0: l0 ?? this.l0,
      l1: l1 ?? this.l1,
      r0: r0 ?? this.r0,
      r1: r1 ?? this.r1,
    );
  }

  static bool _inRange(int v) => v >= 0 && v <= 9;

  static List<int> _walk(int a, int b) {
    if (!_inRange(a) || !_inRange(b)) return const [];
    if (a <= b) {
      return [for (var i = a; i <= b; i++) i];
    }
    return [for (var i = a; i >= b; i--) i];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicMirror &&
          l0 == other.l0 &&
          l1 == other.l1 &&
          r0 == other.r0 &&
          r1 == other.r1;

  @override
  int get hashCode => Object.hash(l0, l1, r0, r1);
}
