import 'package:flutter_test/flutter_test.dart';
import 'package:screen_strip_sync/ipc/helper_status.dart';

void main() {
  group('tryParseStatusLine', () {
    test('returns null for non-status lines', () {
      expect(tryParseStatusLine('cmd=start'), isNull);
      expect(tryParseStatusLine('status'), isNull);
      expect(tryParseStatusLine('status '), isNull);
    });

    test('parses legacy single-word phase lines', () {
      expect(
        tryParseStatusLine('status ready'),
        isA<HelperStatusPhase>().having(
          (e) => e.word,
          'word',
          HelperStatusWord.ready,
        ),
      );
      expect(
        tryParseStatusLine('status reconnecting'),
        isA<HelperStatusPhase>().having(
          (e) => e.word,
          'word',
          HelperStatusWord.reconnecting,
        ),
      );
      expect(
        tryParseStatusLine('status reconnect_ok'),
        isA<HelperStatusPhase>().having(
          (e) => e.word,
          'word',
          HelperStatusWord.reconnectOk,
        ),
      );
      expect(
        tryParseStatusLine('status reconnect_fail'),
        isA<HelperStatusPhase>().having(
          (e) => e.word,
          'word',
          HelperStatusWord.reconnectFail,
        ),
      );
      expect(
        tryParseStatusLine('status not_a_word'),
        isA<HelperStatusPhase>().having(
          (e) => e.word,
          'word',
          HelperStatusWord.unknown,
        ),
      );
    });

    test('parses status com COMn', () {
      expect(
        tryParseStatusLine('status com COM10'),
        isA<HelperStatusCom>().having((e) => e.port, 'port', 'COM10'),
      );
      expect(tryParseStatusLine('status com '), isNull);
    });

    test('parses status engine 0|1', () {
      expect(
        tryParseStatusLine('status engine 1'),
        isA<HelperStatusEngine>().having((e) => e.running, 'running', isTrue),
      );
      expect(
        tryParseStatusLine('status engine 0'),
        isA<HelperStatusEngine>().having(
          (e) => e.running,
          'running',
          isFalse,
        ),
      );
      expect(tryParseStatusLine('status engine 2'), isNull);
      expect(tryParseStatusLine('status engine'), isNull);
    });

    test('parses status display kinds', () {
      expect(
        tryParseStatusLine('status display engine'),
        isA<HelperStatusDisplay>().having(
          (e) => e.kind,
          'kind',
          HelperDisplayKind.engine,
        ),
      );
      expect(
        tryParseStatusLine('status display solid'),
        isA<HelperStatusDisplay>().having(
          (e) => e.kind,
          'kind',
          HelperDisplayKind.solid,
        ),
      );
      expect(
        tryParseStatusLine('status display soft_off'),
        isA<HelperStatusDisplay>().having(
          (e) => e.kind,
          'kind',
          HelperDisplayKind.softOff,
        ),
      );
      expect(
        tryParseStatusLine('status display idle'),
        isA<HelperStatusDisplay>().having(
          (e) => e.kind,
          'kind',
          HelperDisplayKind.idle,
        ),
      );
      expect(tryParseStatusLine('status display'), isNull);
      expect(tryParseStatusLine('status display other'), isNull);
    });

    test('parses status capture_output and output list', () {
      expect(
        tryParseStatusLine(r'status capture_output \\.\DISPLAY1 2560x1440 0,0'),
        isA<HelperStatusCaptureOutput>()
            .having((e) => e.name, 'name', r'\\.\DISPLAY1')
            .having((e) => e.width, 'width', 2560)
            .having((e) => e.height, 'height', 1440)
            .having((e) => e.left, 'left', 0)
            .having((e) => e.top, 'top', 0),
      );
      expect(
        tryParseStatusLine(r'status capture_output \\.\DISPLAY2 1920x1080 2560,-200'),
        isA<HelperStatusCaptureOutput>()
            .having((e) => e.left, 'left', 2560)
            .having((e) => e.top, 'top', -200),
      );
      expect(
        tryParseStatusLine('status outputs 2'),
        isA<HelperStatusOutputsCount>().having((e) => e.count, 'count', 2),
      );
      expect(
        tryParseStatusLine(
          r'status output 1 \\.\DISPLAY2 1920x1080 2560,0 0 1',
        ),
        isA<HelperStatusOutput>()
            .having((e) => e.index, 'index', 1)
            .having((e) => e.name, 'name', r'\\.\DISPLAY2')
            .having((e) => e.isPrimary, 'isPrimary', isFalse)
            .having((e) => e.isCurrent, 'isCurrent', isTrue),
      );
      expect(tryParseStatusLine('status capture_output'), isNull);
      expect(tryParseStatusLine('status outputs'), isNull);
      expect(tryParseStatusLine('status output'), isNull);
    });

    test('ignores unknown key-value pairs', () {
      expect(tryParseStatusLine('status foo bar'), isNull);
    });
  });
}
