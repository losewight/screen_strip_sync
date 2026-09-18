/// 屏幕氛围取色框：被抓那块屏的百分比整数 0..100（与 helper `region_bbox` 对齐）。
class RegionBBox {
  const RegionBBox({
    this.l = 10,
    this.t = 20,
    this.w = 80,
    this.h = 60,
  });

  final int l;
  final int t;
  final int w;
  final int h;

  bool get isValid =>
      l >= 0 && t >= 0 && w > 0 && h > 0 && l + w <= 100 && t + h <= 100;

  /// IPC / 展示用：`L,T,W,H`
  String toIpcPayload() => '$l,$t,$w,$h';

  /// 解析 `L,T,W,H`；非法返回 null。
  static RegionBBox? tryParse(String raw) {
    final parts = raw.split(',');
    if (parts.length != 4) return null;
    final l = int.tryParse(parts[0].trim());
    final t = int.tryParse(parts[1].trim());
    final w = int.tryParse(parts[2].trim());
    final h = int.tryParse(parts[3].trim());
    if (l == null || t == null || w == null || h == null) return null;
    final box = RegionBBox(
      l: l.clamp(0, 100),
      t: t.clamp(0, 100),
      w: w.clamp(0, 100),
      h: h.clamp(0, 100),
    );
    return box.isValid ? box : null;
  }

  /// 物理像素 → 被抓那块屏的百分比（四舍五入后夹紧并保证可解析）。
  static RegionBBox fromPixels({
    required int left,
    required int top,
    required int width,
    required int height,
    required int screenW,
    required int screenH,
  }) {
    if (screenW <= 0 || screenH <= 0) {
      return const RegionBBox();
    }
    var l = ((left * 100) / screenW).round().clamp(0, 100);
    var t = ((top * 100) / screenH).round().clamp(0, 100);
    var w = ((width * 100) / screenW).round().clamp(1, 100);
    var h = ((height * 100) / screenH).round().clamp(1, 100);
    if (l + w > 100) w = 100 - l;
    if (t + h > 100) h = 100 - t;
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    return RegionBBox(l: l, t: t, w: w, h: h);
  }

  RegionBBox copyWith({int? l, int? t, int? w, int? h}) {
    return RegionBBox(
      l: l ?? this.l,
      t: t ?? this.t,
      w: w ?? this.w,
      h: h ?? this.h,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegionBBox &&
          l == other.l &&
          t == other.t &&
          w == other.w &&
          h == other.h;

  @override
  int get hashCode => Object.hash(l, t, w, h);
}

/// 柔和融合 / 高亮追踪（与 helper `region_algo mean|max` 对齐）。
enum RegionAlgo {
  mean,
  max,
}
