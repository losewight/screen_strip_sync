import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/config_store.dart';

export '../config/app_config.dart';

/// 设置页读写的配置 Notifier：启动 load，改完 save。
///
/// 下发 helper 由 [HelperStateNotifier] 负责，此处只管本地值。
class ConfigNotifier extends Notifier<AppConfig> {
  final _store = ConfigStore();

  @override
  AppConfig build() => _store.load();

  void setEmaAlpha(double value) {
    state = state.copyWith(emaAlpha: value.clamp(0.05, 1.0));
    _store.save(state);
  }

  void setMode(ColorMode mode) {
    state = state.copyWith(mode: mode);
    _store.save(state);
  }

  void setComPort(String value) {
    state = state.copyWith(comPort: value.trim());
    _store.save(state);
  }

  /// helper 确认连通后写入；供快速连接 / 开机自启读取。
  void setLastConnectedCom(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    if (name == state.lastConnectedCom) return;
    state = state.copyWith(lastConnectedCom: name, comPort: name);
    _store.save(state);
  }

  void setAutoSleepSync(bool value) {
    state = state.copyWith(autoSleepSync: value);
    _store.save(state);
  }

  void setTurnOffOnShutdown(bool value) {
    state = state.copyWith(turnOffOnShutdown: value);
    _store.save(state);
  }

  void setStartOnBoot(bool value) {
    state = state.copyWith(startOnBoot: value);
    _store.save(state);
  }
}

final configProvider = NotifierProvider<ConfigNotifier, AppConfig>(
  ConfigNotifier.new,
);
