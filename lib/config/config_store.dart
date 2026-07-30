import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'app_config.dart';

/// exe 同目录读写 `zeeray_config.json`；读失败回退默认，写失败不抛给 UI。
///
/// [file] 仅供单测注入；生产路径始终走 [resolvedConfigFile]。
class ConfigStore {
  ConfigStore({File? file}) : _fileOverride = file;

  static const fileName = 'zeeray_config.json';

  final File? _fileOverride;

  /// 默认落盘位置：Flutter/helper 同目录（打包态与 debug exe 旁）。
  static File resolvedConfigFile() => File(
    '${File(Platform.resolvedExecutable).parent.path}'
    '${Platform.pathSeparator}$fileName',
  );

  File get _file => _fileOverride ?? resolvedConfigFile();

  AppConfig load() {
    try {
      final f = _file;
      if (!f.existsSync()) return const AppConfig();
      final decoded = jsonDecode(f.readAsStringSync());
      // jsonDecode 有时给出 Map<dynamic,dynamic>；统一转成 String 键再解析
      if (decoded is! Map) return const AppConfig();
      return AppConfig.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return const AppConfig();
    }
  }

  void save(AppConfig cfg) {
    try {
      _file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(cfg.toJson()),
      );
    } catch (e, st) {
      // 磁盘满 / 无写权限时静默；配置仍留在内存
      developer.log(
        'config save failed: $e',
        name: 'ConfigStore',
        stackTrace: st,
      );
    }
  }
}
