import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeeray_ambilight/config/app_config.dart';
import 'package:zeeray_ambilight/config/config_store.dart';

void main() {
  group('AppConfig.fromJson / toJson', () {
    test('round-trip preserves fields', () {
      const original = AppConfig(
        emaAlpha: 0.55,
        mode: ColorMode.b,
        comPort: 'COM7',
        autoSleepSync: false,
        turnOffOnShutdown: false,
        startOnBoot: true,
      );
      final restored = AppConfig.fromJson(original.toJson());
      expect(restored.emaAlpha, 0.55);
      expect(restored.mode, ColorMode.b);
      expect(restored.comPort, 'COM7');
      expect(restored.autoSleepSync, isFalse);
      expect(restored.turnOffOnShutdown, isFalse);
      expect(restored.startOnBoot, isTrue);
    });

    test('missing keys fall back to defaults', () {
      final cfg = AppConfig.fromJson(<String, dynamic>{});
      expect(cfg.emaAlpha, 0.3);
      expect(cfg.mode, ColorMode.a);
      expect(cfg.comPort, 'COM10');
      expect(cfg.autoSleepSync, isTrue);
      expect(cfg.turnOffOnShutdown, isTrue);
      expect(cfg.startOnBoot, isFalse);
    });

    test('clamps out-of-range emaAlpha', () {
      expect(AppConfig.fromJson({'emaAlpha': 0.01}).emaAlpha, 0.05);
      expect(AppConfig.fromJson({'emaAlpha': 2.0}).emaAlpha, 1.0);
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

    test('toJson uses stable string keys', () {
      expect(
        const AppConfig(mode: ColorMode.b).toJson(),
        {
          'emaAlpha': 0.3,
          'mode': 'b',
          'comPort': 'COM10',
          'autoSleepSync': true,
          'turnOffOnShutdown': true,
          'startOnBoot': false,
        },
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
      expect(cfg.autoSleepSync, isTrue);
      expect(cfg.turnOffOnShutdown, isTrue);
      expect(cfg.startOnBoot, isFalse);
    });

    test('save then load round-trips', () {
      const cfg = AppConfig(
        emaAlpha: 0.8,
        mode: ColorMode.b,
        comPort: 'COM5',
        autoSleepSync: false,
        turnOffOnShutdown: false,
        startOnBoot: true,
      );
      store.save(cfg);
      final loaded = store.load();
      expect(loaded.emaAlpha, 0.8);
      expect(loaded.mode, ColorMode.b);
      expect(loaded.comPort, 'COM5');
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
