import 'package:flutter_test/flutter_test.dart';
import 'package:screen_strip_sync/config/app_config.dart';
import 'package:screen_strip_sync/config/segment_map_codec.dart';

void main() {
  group('AppConfig.fromCfgLines', () {
    test('parses full snapshot including autostart', () {
      final cfg = AppConfig.fromCfgLines(const [
        'cfg alpha 0.55',
        'cfg near_black 20',
        'cfg blur 4',
        'cfg saturation 1.60',
        'cfg mode b',
        'cfg com COM7',
        'cfg last_com COM7',
        'cfg serial_configured 1',
        'cfg sleep_sync 0',
        'cfg shutdown_off 0',
        'cfg autostart 1',
        'cfg map default',
        'cfg scene solid FF00FF',
      ]);
      expect(cfg.emaAlpha, 0.55);
      expect(cfg.nearBlack, 20);
      expect(cfg.blurStep, 4);
      expect(cfg.saturation, 1.60);
      expect(cfg.mode, ColorMode.b);
      expect(cfg.comPort, 'COM7');
      expect(cfg.captureOutput, 'auto');
      expect(cfg.lastConnectedCom, 'COM7');
      expect(cfg.serialConfigured, isTrue);
      expect(cfg.autoSleepSync, isFalse);
      expect(cfg.turnOffOnShutdown, isFalse);
      expect(cfg.startOnBoot, isTrue);
      expect(cfg.segmentMap, isNull);
      expect(cfg.lastScene, 'solid FF00FF');
    });

    test('empty lines fall back to defaults', () {
      final cfg = AppConfig.fromCfgLines(const []);
      expect(cfg.emaAlpha, 1.0);
      expect(cfg.nearBlack, 4);
      expect(cfg.blurStep, 0);
      expect(cfg.saturation, 1.2);
      expect(cfg.sampleAlgo, SampleAlgo.rms);
      expect(cfg.mode, ColorMode.a);
      expect(cfg.comPort, 'COM10');
      expect(cfg.captureOutput, 'auto');
      expect(cfg.lastConnectedCom, '');
      expect(cfg.serialConfigured, isFalse);
      expect(cfg.autoSleepSync, isTrue);
      expect(cfg.turnOffOnShutdown, isTrue);
      expect(cfg.startOnBoot, isFalse);
      expect(cfg.regionBlur, 3);
      expect(cfg.regionSmooth, 0.8);
      expect(cfg.regionDark, 15);
      expect(cfg.lastScene, 'idle');
      expect(cfg.wallCompEnabled, isFalse);
      expect(cfg.wallColor, '');
      expect(cfg.hasWallColor, isFalse);
    });

    test('parses serial_configured 0 and 1', () {
      expect(
        AppConfig.fromCfgLines(const [
          'cfg serial_configured 0',
        ]).serialConfigured,
        isFalse,
      );
      expect(
        AppConfig.fromCfgLines(const [
          'cfg serial_configured 1',
        ]).serialConfigured,
        isTrue,
      );
    });

    test('parses capture_output auto and device name', () {
      expect(
        AppConfig.fromCfgLines(const ['cfg capture_output auto']).captureOutput,
        'auto',
      );
      expect(
        AppConfig.fromCfgLines(const [
          r'cfg capture_output \\.\DISPLAY2',
        ]).captureOutput,
        r'\\.\DISPLAY2',
      );
    });

    test('parses wall compensation fields', () {
      final cfg = AppConfig.fromCfgLines(const [
        'cfg wall_comp 1',
        'cfg wall_color FFE6B4',
      ]);
      expect(cfg.wallCompEnabled, isTrue);
      expect(cfg.wallColor, 'ffe6b4');
      expect(cfg.hasWallColor, isTrue);
    });

    test('clamps out-of-range numeric fields', () {
      expect(
        AppConfig.fromCfgLines(const ['cfg alpha 0.01']).emaAlpha,
        0.05,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg alpha 2.0']).emaAlpha,
        1.0,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg near_black -1']).nearBlack,
        0,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg near_black 100']).nearBlack,
        64,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg blur -3']).blurStep,
        0,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg blur 99']).blurStep,
        8,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg saturation 0.1']).saturation,
        0.5,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg saturation 3.0']).saturation,
        2.0,
      );
    });

    test('accepts lines without cfg prefix', () {
      final cfg = AppConfig.fromCfgLines(const [
        'autostart 1',
        'sleep_sync 0',
      ]);
      expect(cfg.startOnBoot, isTrue);
      expect(cfg.autoSleepSync, isFalse);
    });

    test('parses map payload; default clears map', () {
      final parts = List.generate(
        kSegmentCount,
        (i) => '$i,0,${i + 1},5',
      );
      final body = parts.join(';');
      final withMap = AppConfig.fromCfgLines(['cfg map $body']);
      expect(withMap.hasSegmentMap, isTrue);
      expect(withMap.segmentMap![3].x0, closeTo(0.03, 1e-9));

      final cleared = AppConfig.fromCfgLines([
        'cfg map $body',
        'cfg map default',
      ]);
      expect(cleared.segmentMap, isNull);
    });

    test('parses sample_algo rms and mean; illegal falls back to rms', () {
      expect(
        AppConfig.fromCfgLines(const ['cfg sample_algo mean']).sampleAlgo,
        SampleAlgo.mean,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg sample_algo rms']).sampleAlgo,
        SampleAlgo.rms,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg sample_algo xyz']).sampleAlgo,
        SampleAlgo.rms,
      );
    });

    test('parses region fields and scene region', () {
      final cfg = AppConfig.fromCfgLines(const [
        'cfg region_algo max',
        'cfg region_blur 8',
        'cfg region_smooth 0.80',
        'cfg region_dark 3',
        'cfg region_bbox 12,20,70,55',
        'cfg scene region',
      ]);
      expect(cfg.regionAlgo, RegionAlgo.max);
      expect(cfg.regionBlur, 8);
      expect(cfg.regionSmooth, 0.80);
      expect(cfg.regionDark, 3);
      expect(cfg.regionBBox, const RegionBBox(l: 12, t: 20, w: 70, h: 55));
      expect(cfg.lastScene, 'region');
    });

    test('clamps region numeric fields', () {
      expect(
        AppConfig.fromCfgLines(const ['cfg region_blur 99']).regionBlur,
        20,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg region_smooth 1.5']).regionSmooth,
        0.99,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg region_dark -2']).regionDark,
        0,
      );
    });

    test('illegal mode falls back to A', () {
      expect(
        AppConfig.fromCfgLines(const ['cfg mode x']).mode,
        ColorMode.a,
      );
      expect(
        AppConfig.fromCfgLines(const ['cfg mode B']).mode,
        ColorMode.b,
      );
    });
  });
}
