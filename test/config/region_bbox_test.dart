import 'package:flutter_test/flutter_test.dart';
import 'package:screen_strip_sync/config/region_bbox.dart';

void main() {
  group('RegionBBox', () {
    test('default constructor creates valid bbox', () {
      const box = RegionBBox();
      expect(box.isValid, isTrue);
      expect(box.toIpcPayload(), equals('10,20,80,60'));
    });

    test('tryParse parses valid payload', () {
      final box = RegionBBox.tryParse('15,25,50,40');
      expect(box, isNotNull);
      expect(box!.l, equals(15));
      expect(box.t, equals(25));
      expect(box.w, equals(50));
      expect(box.h, equals(40));
      expect(box.isValid, isTrue);
    });

    test('tryParse rejects invalid payload', () {
      expect(RegionBBox.tryParse(''), isNull);
      expect(RegionBBox.tryParse('1,2,3'), isNull);
      expect(RegionBBox.tryParse('a,b,c,d'), isNull);
      expect(RegionBBox.tryParse('90,0,20,10'), isNull); // 90+20 > 100
    });

    test('fromPixels handles right/bottom screen edge clamp without overflow', () {
      // User drags box touching rightmost pixel: left=1920, screenW=1920
      final box = RegionBBox.fromPixels(
        left: 1920,
        top: 1080,
        width: 100,
        height: 100,
        screenW: 1920,
        screenH: 1080,
      );
      expect(box.isValid, isTrue);
      expect(box.l + box.w, lessThanOrEqualTo(100));
      expect(box.t + box.h, lessThanOrEqualTo(100));
      expect(box.w, greaterThan(0));
      expect(box.h, greaterThan(0));
    });

    test('fromPixels handles zero or negative screen dimensions', () {
      final box = RegionBBox.fromPixels(
        left: 0,
        top: 0,
        width: 100,
        height: 100,
        screenW: 0,
        screenH: 0,
      );
      expect(box.isValid, isTrue);
      expect(box, equals(const RegionBBox()));
    });
  });
}
