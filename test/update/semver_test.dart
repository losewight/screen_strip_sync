import 'package:flutter_test/flutter_test.dart';

import 'package:screen_strip_sync/update/semver.dart';

void main() {
  group('Semver', () {
    test('parse strips v and build', () {
      expect(Semver.parse('v1.0.3+3'), (1, 0, 3));
      expect(Semver.parse('1.2'), (1, 2, 0));
    });

    test('compare ordering', () {
      expect(Semver.isGreater('1.0.4', '1.0.3'), isTrue);
      expect(Semver.isGreater('1.0.3', '1.0.3'), isFalse);
      expect(Semver.isGreater('1.0.3', '1.0.4'), isFalse);
      expect(Semver.isGreater('2.0.0', '1.9.9'), isTrue);
    });
  });
}
