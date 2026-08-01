import 'package:flutter_test/flutter_test.dart';
import 'package:zeeray_ambilight/ipc/helper_status.dart';

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

    test('ignores unknown key-value pairs', () {
      expect(tryParseStatusLine('status foo bar'), isNull);
    });
  });
}
