/// 一段灯带对应的屏幕采样矩形（相对被抓的那块屏，归一化 `[0,1]`）。
///
/// 约束经 [SegmentSample.normalize] / codec 保证：`0≤x0<x1≤1`，`0≤y0<y1≤1`。
class SegmentSample {
  const SegmentSample({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
  });

  final double x0;
  final double y0;
  final double x1;
  final double y1;

  /// 拖框原始对角点 → 规范化矩形；边长不足 [minSpan] 时向外抬。
  factory SegmentSample.normalize({
    required double ax,
    required double ay,
    required double bx,
    required double by,
    double minSpan = 0.01,
  }) {
    var x0 = ax < bx ? ax : bx;
    var x1 = ax < bx ? bx : ax;
    var y0 = ay < by ? ay : by;
    var y1 = ay < by ? by : ay;

    x0 = x0.clamp(0.0, 1.0);
    x1 = x1.clamp(0.0, 1.0);
    y0 = y0.clamp(0.0, 1.0);
    y1 = y1.clamp(0.0, 1.0);

    if (x1 - x0 < minSpan) {
      final mid = ((x0 + x1) / 2).clamp(minSpan / 2, 1.0 - minSpan / 2);
      x0 = mid - minSpan / 2;
      x1 = mid + minSpan / 2;
    }
    if (y1 - y0 < minSpan) {
      final mid = ((y0 + y1) / 2).clamp(minSpan / 2, 1.0 - minSpan / 2);
      y0 = mid - minSpan / 2;
      y1 = mid + minSpan / 2;
    }

    return SegmentSample(x0: x0, y0: y0, x1: x1, y1: y1);
  }

  /// 非法 / 缺字段返回 null（整表丢弃由调用方决定）。
  static SegmentSample? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    double? read(String k) {
      final v = map[k];
      return switch (v) {
        num n => n.toDouble(),
        _ => null,
      };
    }

    final x0 = read('x0');
    final y0 = read('y0');
    final x1 = read('x1');
    final y1 = read('y1');
    if (x0 == null || y0 == null || x1 == null || y1 == null) return null;
    if (!(x0 >= 0 && y0 >= 0 && x1 <= 1 && y1 <= 1)) return null;
    if (!(x0 < x1 && y0 < y1)) return null;
    return SegmentSample(x0: x0, y0: y0, x1: x1, y1: y1);
  }

  Map<String, dynamic> toJson() => {
    'x0': x0,
    'y0': y0,
    'x1': x1,
    'y1': y1,
  };
}
