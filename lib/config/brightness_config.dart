/// 亮度模式（与 helper `brightness full|linear` 对齐）。
enum BrightnessMode {
  /// 全亮度：帧 Brightness 固定 0x63。
  full,

  /// 线性：BRT = lo + (hi-lo) * 画面亮度均值。
  linear,
}

extension BrightnessModeIpc on BrightnessMode {
  String get ipcWord => switch (this) {
    BrightnessMode.full => 'full',
    BrightnessMode.linear => 'linear',
  };

  String get label => switch (this) {
    BrightnessMode.full => '全亮度',
    BrightnessMode.linear => '线性',
  };

  static BrightnessMode fromIpcWord(String value) {
    return switch (value.trim().toLowerCase()) {
      'linear' || 'l' => BrightnessMode.linear,
      _ => BrightnessMode.full,
    };
  }
}

/// 亮度模式 + 线性区间 0..100（即 BRT 原值 0x00..0x64）。
class BrightnessSetting {
  const BrightnessSetting({
    this.mode = BrightnessMode.full,
    this.lo = 25,
    this.hi = 75,
  });

  static const defaults = BrightnessSetting();

  final BrightnessMode mode;
  final int lo;
  final int hi;

  /// IPC：`full|linear lo,hi`
  String toIpcPayload() => '${mode.ipcWord} $lo,$hi';

  /// 解析 `full|linear lo,hi`；非法返回 null。
  static BrightnessSetting? tryParse(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final sp = t.indexOf(' ');
    if (sp < 0) return null;
    final modeWord = t.substring(0, sp).trim();
    final range = t.substring(sp + 1).trim();
    final parts = range.split(',');
    if (parts.length != 2) return null;
    final a = int.tryParse(parts[0].trim());
    final b = int.tryParse(parts[1].trim());
    if (a == null || b == null) return null;
    var lo = a.clamp(0, 100);
    var hi = b.clamp(0, 100);
    if (lo > hi) {
      final tmp = lo;
      lo = hi;
      hi = tmp;
    }
    return BrightnessSetting(
      mode: BrightnessModeIpc.fromIpcWord(modeWord),
      lo: lo,
      hi: hi,
    );
  }

  BrightnessSetting copyWith({BrightnessMode? mode, int? lo, int? hi}) {
    var nextLo = (lo ?? this.lo).clamp(0, 100);
    var nextHi = (hi ?? this.hi).clamp(0, 100);
    if (nextLo > nextHi) {
      final tmp = nextLo;
      nextLo = nextHi;
      nextHi = tmp;
    }
    return BrightnessSetting(
      mode: mode ?? this.mode,
      lo: nextLo,
      hi: nextHi,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrightnessSetting &&
          mode == other.mode &&
          lo == other.lo &&
          hi == other.hi;

  @override
  int get hashCode => Object.hash(mode, lo, hi);
}
