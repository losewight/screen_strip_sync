import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeeray_ambilight/config/app_config.dart';
import 'package:zeeray_ambilight/config/config_store.dart';
import 'package:zeeray_ambilight/config/segment_map_codec.dart';

void main() {
  group('AppConfig.fromJson / toJson', () {
    test('round-trip preserves fields', () {
      const original = AppConfig(
        emaAlpha: 0.55,
        nearBlack: 20,
        blurStep: 4,
        mode: ColorMode.b,
        comPort: 'COM7',
        lastConnectedCom: 'COM7',
        autoSleepSync: false,
        turnOffOnShutdown: false,
        startOnBoot: true,
      );
      final restored = AppConfig.fromJson(original.toJson());
      expect(restored.emaAlpha, 0.55);
      expect(restored.nearBlack, 20);
      expect(restored.blurStep, 4);
      expect(restored.mode, ColorMode.b);
      expect(restored.comPort, 'COM7');
      expect(restored.lastConnectedCom, 'COM7');
      expect(restored.autoSleepSync, isFalse);
      expect(restored.turnOffOnShutdown, isFalse);
      expect(restored.startOnBoot, isTrue);
    });

    test('missing keys fall back to defaults', () {
      final cfg = AppConfig.fromJson(<String, dynamic>{});
      expect(cfg.emaAlpha, 0.3);
      expect(cfg.nearBlack, 12);
      expect(cfg.blurStep, 2);
      expect(cfg.mode, ColorMode.a);
      expect(cfg.comPort, 'COM10');
      expect(cfg.lastConnectedCom, '');
      expect(cfg.autoSleepSync, isTrue);
      expect(cfg.turnOffOnShutdown, isTrue);
      expect(cfg.startOnBoot, isFalse);
    });

    test('clamps out-of-range emaAlpha', () {
      expect(AppConfig.fromJson({'emaAlpha': 0.01}).emaAlpha, 0.05);
      expect(AppConfig.fromJson({'emaAlpha': 2.0}).emaAlpha, 1.0);
    });

    test('clamps out-of-range nearBlack and blurStep', () {
      expect(AppConfig.fromJson({'nearBlack': -1}).nearBlack, 0);
      expect(AppConfig.fromJson({'nearBlack': 100}).nearBlack, 64);
      expect(AppConfig.fromJson({'blurStep': -3}).blurStep, 0);
      expect(AppConfig.fromJson({'blurStep': 99}).blurStep, 8);
    });

    test('illegal mode falls back to A; B is case-insensitive', () {
      expect(AppConfig.fromJson({'mode': 'x'}).mode, ColorMode.a);
      expect(AppConfig.fromJson({'mode': 'b'}).mode, ColorMode.b);
      expect(AppConfig.fromJson({'mode': 'B'}).mode, ColorMode.b);
    });

    test('blank comPort falls back to COM10', () {
      expect(AppConfig.fromJson({'comPort': '  '}).comPort, 'COM10');
      expect(AppConfig.fromJson({'comPort': 'COM3'}).comPort, 'COM3');
    });

    test('lastConnectedCom trims; missing defaults empty', () {
      expect(AppConfig.fromJson({}).lastConnectedCom, '');
      expect(
        AppConfig.fromJson({'lastConnectedCom': ' COM12 '}).lastConnectedCom,
        'COM12',
      );
    });

    test('toJson uses stable string keys', () {
      expect(
        const AppConfig(mode: ColorMode.b).toJson(),
        {
          'emaAlpha': 0.3,
          'nearBlack': 12,
          'blurStep': 2,
          'mode': 'b',
          'comPort': 'COM10',
          'lastConnectedCom': '',
          'autoSleepSync': true,
          'turnOffOnShutdown': true,
          'startOnBoot': false,
        },
      );
    });

    test('missing segmentMap is null (uncalibrated)', () {
      expect(AppConfig.fromJson({}).segmentMap, isNull);
      expect(const AppConfig().hasSegmentMap, isFalse);
    });

    test('valid segmentMap round-trips; bad length discarded', () {
      final map = List.generate(
        kSegmentCount,
        (i) => SegmentSample(
          x0: i / 10.0,
          y0: 0,
          x1: (i + 1) / 10.0,
          y1: 0.05,
        ),
      );
      final cfg = AppConfig(segmentMap: map);
      final restored = AppConfig.fromJson(cfg.toJson());
      expect(restored.hasSegmentMap, isTrue);
      expect(restored.segmentMap![3].x0, closeTo(0.3, 1e-9));

      expect(
        AppConfig.fromJson({
          'segmentMap': [
            {'x0': 0, 'y0': 0, 'x1': 1, 'y1': 1},
          ],
        }).segmentMap,
        isNull,
      );
    });
  });

  group('ConfigStore', () {
    late Directory tempDir;
    late File configFile;
    late ConfigStore store;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zeeray_config_');
      configFile = File(
        '${tempDir.path}${Platform.pathSeparator}zeeray_config.json',
      );
      store = ConfigStore(file: configFile);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('missing file returns defaults', () {
      final cfg = store.load();
      expect(cfg.emaAlpha, 0.3);
      expect(cfg.mode, ColorMode.a);
      expect(cfg.comPort, 'COM10');
      expect(cfg.lastConnectedCom, '');
      expect(cfg.autoSleepSync, isTrue);
      expect(cfg.turnOffOnShutdown, isTrue);
      expect(cfg.startOnBoot, isFalse);
      expect(cfg.segmentMap, isNull);
    });

    test('save then load round-trips', () {
      const cfg = AppConfig(
        emaAlpha: 0.8,
        mode: ColorMode.b,
        comPort: 'COM5',
        lastConnectedCom: 'COM5',
        autoSleepSync: false,
        turnOffOnShutdown: false,
        startOnBoot: true,
      );
      store.save(cfg);
      final loaded = store.load();
      expect(loaded.emaAlpha, 0.8);
      expect(loaded.mode, ColorMode.b);
      expect(loaded.comPort, 'COM5');
      expect(loaded.lastConnectedCom, 'COM5');
      expect(loaded.autoSleepSync, isFalse);
      expect(loaded.turnOffOnShutdown, isFalse);
      expect(loaded.startOnBoot, isTrue);
    });

    test('corrupt JSON returns defaults without throwing', () {
      configFile.writeAsStringSync('{not-json');
      final cfg = store.load();
      expect(cfg.emaAlpha, 0.3);
      expect(cfg.mode, ColorMode.a);
    });

    test('non-object JSON returns defaults', () {
      configFile.writeAsStringSync(jsonEncode([1, 2, 3]));
      final cfg = store.load();
      expect(cfg.comPort, 'COM10');
    });
  });
}
