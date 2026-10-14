import 'package:flutter_test/flutter_test.dart';
import 'package:screen_strip_sync/config/music_config.dart';

void main() {
  group('MusicMirror', () {
    test('none is unset and invalid', () {
      expect(MusicMirror.none.isUnset, isTrue);
      expect(MusicMirror.none.isValid, isFalse);
      expect(MusicMirror.tryParse('none'), MusicMirror.none);
      expect(MusicMirror.tryParse(''), MusicMirror.none);
    });

    test('parses U-shape and computes segments', () {
      final m = MusicMirror.tryParse('0,3,9,6');
      expect(m, isNotNull);
      expect(m!.isValid, isTrue);
      expect(m.leftSegments, [0, 1, 2, 3]);
      expect(m.rightSegments, [9, 8, 7, 6]);
      expect(m.restSegments, [4, 5]);
      expect(m.toIpcPayload(), '0,3,9,6');
    });

    test('reverse direction on a bar', () {
      final m = MusicMirror(l0: 2, l1: 0, r0: 5, r1: 9);
      expect(m.isValid, isTrue);
      expect(m.leftSegments, [2, 1, 0]);
      expect(m.rightSegments, [5, 6, 7, 8, 9]);
      expect(m.restSegments, [3, 4]);
    });

    test('overlap is invalid; tryParse returns null', () {
      final bad = MusicMirror(l0: 0, l1: 5, r0: 4, r1: 9);
      expect(bad.isValid, isFalse);
      expect(MusicMirror.tryParse('0,5,4,9'), isNull);
    });

    test('unequal lengths ok', () {
      final m = MusicMirror(l0: 0, l1: 1, r0: 9, r1: 5);
      expect(m.isValid, isTrue);
      expect(m.leftSegments.length, 2);
      expect(m.rightSegments.length, 5);
      expect(m.restSegments, [2, 3, 4]);
    });
  });

  group('MusicRest', () {
    test('ipc words', () {
      expect(MusicRest.off.ipcWord, 'off');
      expect(MusicRest.peak.ipcWord, 'peak');
      expect(MusicRest.base.ipcWord, 'base');
      expect(MusicRestIpc.fromIpcWord('peak'), MusicRest.peak);
      expect(MusicRestIpc.fromIpcWord('base'), MusicRest.base);
      expect(MusicRestIpc.fromIpcWord('x'), MusicRest.off);
    });
  });

  group('MusicPalette', () {
    test('ipc words and labels', () {
      expect(MusicPalette.vu.ipcWord, 'vu');
      expect(MusicPalette.rainbow.ipcWord, 'rainbow');
      expect(MusicPalette.fixed.ipcWord, 'fixed');
      expect(MusicPalette.level.ipcWord, 'level');
      expect(MusicPalette.screen.ipcWord, 'screen');
      expect(MusicPaletteIpc.fromIpcWord('rainbow'), MusicPalette.rainbow);
      expect(MusicPaletteIpc.fromIpcWord('fixed'), MusicPalette.fixed);
      expect(MusicPaletteIpc.fromIpcWord('level'), MusicPalette.level);
      expect(MusicPaletteIpc.fromIpcWord('screen'), MusicPalette.screen);
      expect(MusicPaletteIpc.fromIpcWord('vu'), MusicPalette.vu);
      expect(MusicPaletteIpc.fromIpcWord('x'), MusicPalette.vu);
    });

    test('normalize fixed rejects black and boosts dark', () {
      expect(musicNormalizeFixedHex('000000'), isNull);
      final dark = musicNormalizeFixedHex('001122');
      expect(dark, isNotNull);
      expect(dark!.b, 255);
      expect(dark.r, lessThan(dark.b));
    });

    test('vu endpoints and level full are vivid', () {
      final low = musicPaletteColor(MusicPalette.vu, t: 0, level: 1);
      final high = musicPaletteColor(MusicPalette.vu, t: 1, level: 1);
      expect(low.g, greaterThan(low.r));
      expect(high.r, greaterThan(high.g));
      final full = musicPaletteColor(MusicPalette.level, t: 0, level: 1);
      expect(full.r, 255);
    });
  });
}
