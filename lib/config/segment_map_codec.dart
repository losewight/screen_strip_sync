import 'segment_sample.dart';

/// 段映射表长度（协议 / 灯带逻辑段数）。
const int kSegmentCount = 10;

/// IPC 行最大长度（与 helper `ipc_loop` 一致）；超长整句丢弃。
///
/// 这是本机 TCP 文本行上限，**与串口帧长 120 字节红线无关**，两者不得互相「对齐」。
const int kIpcMaxLineChars = 512;

/// 段映射 ↔ IPC / 显示坐标换算。
///
/// 调用约定：
/// - UI 拖框结束 → [rectFromDisplayDrag] → [SegmentSample]
/// - helper `cfg map` / IPC：`encodeIpcPayload` / `decodeIpcPayload`
/// - 下发 helper：`set map ${encodeIpcPayload(list)}` 或 `set map default`
abstract final class SegmentMapCodec {
  /// JSON 数组 → 恰好 10 段；任一非法则整表 `null`（未校准）。
  static List<SegmentSample>? parseSegmentMapJson(Object? raw) {
    if (raw is! List) return null;
    if (raw.length != kSegmentCount) return null;
    final out = <SegmentSample>[];
    for (final item in raw) {
      final s = SegmentSample.tryFromJson(item);
      if (s == null) return null;
      out.add(s);
    }
    return List<SegmentSample>.unmodifiable(out);
  }

  /// 显示层拖框（相对截图 widget 的 0..1）→ 采样矩形。
  static SegmentSample rectFromDisplayDrag({
    required double ax,
    required double ay,
    required double bx,
    required double by,
  }) => SegmentSample.normalize(ax: ax, ay: ay, bx: bx, by: by);

  /// 10 段 → `x0,y0,x1,y1;...`（0..100 整数百分比，无 `set map ` 前缀）。
  ///
  /// 长度 ≥ [kIpcMaxLineChars] 时返回 null（调用方应视为失败、不下发）。
  static String? encodeIpcPayload(List<SegmentSample> map) {
    if (map.length != kSegmentCount) return null;
    final parts = <String>[];
    for (final s in map) {
      final x0 = _pct(s.x0);
      final y0 = _pct(s.y0);
      final x1 = _pct(s.x1);
      final y1 = _pct(s.y1);
      // 量化后仍须 x0<x1、y0<y1
      if (x0 >= x1 || y0 >= y1) return null;
      parts.add('$x0,$y0,$x1,$y1');
    }
    final body = parts.join(';');
    if (body.length >= kIpcMaxLineChars) return null;
    return body;
  }

  /// 完整命令行（含前缀）；失败返回 null。
  static String? encodeIpcCommand(List<SegmentSample> map) {
    final body = encodeIpcPayload(map);
    if (body == null) return null;
    final line = 'set map $body';
    if (line.length >= kIpcMaxLineChars) return null;
    return line;
  }

  static const String ipcClearCommand = 'set map default';

  static String highlightCommand(int segment) {
    assert(segment >= 0 && segment < kSegmentCount);
    return 'highlight $segment';
  }

  /// 解析 helper 同款 payload（测试 / 对称校验用）。
  static List<SegmentSample>? decodeIpcPayload(String body) {
    final segs = body.split(';');
    if (segs.length != kSegmentCount) return null;
    final out = <SegmentSample>[];
    for (final seg in segs) {
      final nums = seg.split(',');
      if (nums.length != 4) return null;
      final vals = <int>[];
      for (final n in nums) {
        final v = int.tryParse(n.trim());
        if (v == null || v < 0 || v > 100) return null;
        vals.add(v);
      }
      final x0 = vals[0] / 100.0;
      final y0 = vals[1] / 100.0;
      final x1 = vals[2] / 100.0;
      final y1 = vals[3] / 100.0;
      if (!(x0 < x1 && y0 < y1)) return null;
      out.add(SegmentSample(x0: x0, y0: y0, x1: x1, y1: y1));
    }
    return List<SegmentSample>.unmodifiable(out);
  }

  static int _pct(double v) => (v.clamp(0.0, 1.0) * 100).round().clamp(0, 100);
}
