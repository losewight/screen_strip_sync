import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/segment_map_codec.dart';
import '../ipc/helper_client.dart';

export '../config/app_config.dart';

/// 配置 Notifier：由 helper `cfg …`/`cfg end` 快照驱动；setter 只乐观改内存。
///
/// 落盘与注册表属主是 helper；下发 IPC 由 [HelperStateNotifier] 负责。
class ConfigNotifier extends Notifier<AppConfig> {
  StreamSubscription<AppConfig>? _cfgSub;
  StreamSubscription<void>? _disconnectSub;
  bool _hasSnapshot = false;

  bool get hasSnapshot => _hasSnapshot;

  @override
  AppConfig build() {
    final client = ref.watch(helperClientProvider);
    _cfgSub?.cancel();
    _disconnectSub?.cancel();
    _cfgSub = client.configSnapshots.listen((snap) {
      _hasSnapshot = true;
      state = snap;
    });
    // 为什么：断线后旧快照只读展示，但标记未就绪，等下次 cfg end 再可编辑
    _disconnectSub = client.disconnectStream.listen((_) {
      if (!_hasSnapshot) return;
      _hasSnapshot = false;
      state = state.copyWith(emaAlpha: state.emaAlpha);
    });
    ref.onDispose(() {
      _cfgSub?.cancel();
      _cfgSub = null;
      _disconnectSub?.cancel();
      _disconnectSub = null;
    });
    return const AppConfig();
  }

  void setEmaAlpha(double value) {
    state = state.copyWith(emaAlpha: value.clamp(0.05, 1.0));
  }

  void setNearBlack(int value) {
    state = state.copyWith(nearBlack: value.clamp(0, 64));
  }

  void setBlurStep(int value) {
    state = state.copyWith(blurStep: value.clamp(0, 8));
  }

  void setSaturation(double value) {
    state = state.copyWith(saturation: value.clamp(0.5, 2.0));
  }

  void setMode(ColorMode mode) {
    state = state.copyWith(mode: mode);
  }

  void setRegionAlgo(RegionAlgo algo) {
    state = state.copyWith(regionAlgo: algo);
  }

  void setRegionBlur(int value) {
    state = state.copyWith(regionBlur: value.clamp(0, 20));
  }

  void setRegionSmooth(double value) {
    state = state.copyWith(regionSmooth: value.clamp(0.0, 0.99));
  }

  void setRegionDark(int value) {
    state = state.copyWith(regionDark: value.clamp(0, 50));
  }

  void setRegionBBox(RegionBBox box) {
    if (!box.isValid) return;
    state = state.copyWith(regionBBox: box);
  }

  void setLastCustomSolid(String hex) {
    final h = hex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) return;
    state = state.copyWith(lastCustomSolid: h);
  }

  void setWallCompEnabled(bool value) {
    state = state.copyWith(wallCompEnabled: value);
  }

  void setWallColor(String hex) {
    final h = hex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) return;
    state = state.copyWith(wallColor: h);
  }

  void setComPort(String value) {
    state = state.copyWith(comPort: value.trim());
  }

  void setCaptureOutput(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    state = state.copyWith(captureOutput: name);
  }

  /// helper `status com` / 快照后的内存更新；不写盘。
  void setLastConnectedCom(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    if (name == state.lastConnectedCom && name == state.comPort) return;
    state = state.copyWith(lastConnectedCom: name, comPort: name);
  }

  void setAutoSleepSync(bool value) {
    state = state.copyWith(autoSleepSync: value);
  }

  void setTurnOffOnShutdown(bool value) {
    state = state.copyWith(turnOffOnShutdown: value);
  }

  void setStartOnBoot(bool value) {
    state = state.copyWith(startOnBoot: value);
  }

  /// 写入恰好 [kSegmentCount] 段；长度不对则忽略。
  void setSegmentMap(List<SegmentSample> map) {
    if (map.length != kSegmentCount) return;
    state = state.copyWith(
      segmentMap: List<SegmentSample>.unmodifiable(map),
    );
  }

  /// 清除校准，helper 侧应随后 `set map default`。
  void clearSegmentMap() {
    state = state.copyWith(clearSegmentMap: true);
  }
}

final configProvider = NotifierProvider<ConfigNotifier, AppConfig>(
  ConfigNotifier.new,
);

/// 是否已收到过至少一次 helper `cfg end` 快照。
final configReadyProvider = Provider<bool>((ref) {
  ref.watch(configProvider);
  return ref.read(configProvider.notifier).hasSnapshot;
});
