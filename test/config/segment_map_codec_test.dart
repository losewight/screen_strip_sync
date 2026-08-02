import 'package:flutter_test/flutter_test.dart';
import 'package:zeeray_ambilight/config/segment_map_codec.dart';
import 'package:zeeray_ambilight/config/segment_sample.dart';

List<SegmentSample> _tenTopEdge() {
  return List.generate(kSegmentCount, (i) {
    final x0 = i / 10.0;
    final x1 = (i + 1) / 10.0;
    return SegmentSample(x0: x0, y0: 0, x1: x1, y1: 0.03);
  });
}

void main() {
  group('SegmentSample.normalize', () {
    test('orders corners and clamps', () {
      final s = SegmentSample.normalize(ax: 0.8, ay: 0.9, bx: 0.2, by: 0.1);
      expect(s.x0, closeTo(0.2, 1e-9));
      expect(s.y0, closeTo(0.1, 1e-9));
      expect(s.x1, closeTo(0.8, 1e-9));
      expect(s.y1, closeTo(0.9, 1e-9));
    });

    test('lifts tiny drag to minSpan', () {
      final s = SegmentSample.normalize(
        ax: 0.5,
        ay: 0.5,
        bx: 0.501,
        by: 0.501,
        minSpan: 0.01,
      );
      expect(s.x1 - s.x0, closeTo(0.01, 1e-6));
      expect(s.y1 - s.y0, closeTo(0.01, 1e-6));
    });
  });

  group('SegmentMapCodec', () {
    test('JSON round-trip of 10 segments', () {
      final map = _tenTopEdge();
      final json = map.map((s) => s.toJson()).toList();
      final parsed = SegmentMapCodec.parseSegmentMapJson(json);
      expect(parsed, isNotNull);
      expect(parsed!.length, kSegmentCount);
      expect(parsed[0].x0, 0.0);
      expect(parsed[9].x1, 1.0);
    });

    test('illegal JSON length yields null', () {
      expect(SegmentMapCodec.parseSegmentMapJson([]), isNull);
      expect(
        SegmentMapCodec.parseSegmentMapJson([
          {'x0': 0, 'y0': 0, 'x1': 1, 'y1': 1},
        ]),
        isNull,
      );
    });

    test('IPC encode/decode top-edge style map', () {
      final map = _tenTopEdge();
      final payload = SegmentMapCodec.encodeIpcPayload(map);
      expect(payload, isNotNull);
      expect(payload!.length, lessThan(kIpcMaxLineChars));

      final cmd = SegmentMapCodec.encodeIpcCommand(map);
      expect(cmd, startsWith('set map '));
      expect(cmd!.length, lessThan(kIpcMaxLineChars));

      final decoded = SegmentMapCodec.decodeIpcPayload(payload);
      expect(decoded, isNotNull);
      expect(decoded!.length, 10);
      // 量化到百分数后仍有序
      expect(decoded[0].x0, 0.0);
      expect(decoded[0].x1, 0.1);
    });

    test('highlight and clear commands', () {
      expect(SegmentMapCodec.highlightCommand(3), 'highlight 3');
      expect(SegmentMapCodec.ipcClearCommand, 'set map default');
    });

    test('rectFromDisplayDrag delegates to normalize', () {
      final s = SegmentMapCodec.rectFromDisplayDrag(
        ax: 1.0,
        ay: 1.0,
        bx: 0.0,
        by: 0.0,
      );
      expect(s.x0, 0.0);
      expect(s.y0, 0.0);
      expect(s.x1, 1.0);
      expect(s.y1, 1.0);
    });
  });
}
