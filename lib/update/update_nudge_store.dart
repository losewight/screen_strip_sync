import 'dart:convert';

import '../app/app_paths.dart';
import 'semver.dart';

/// 每个远端版本只提醒一次：读/写 `update_nudge.json`。
abstract final class UpdateNudgeStore {
  static const _key = 'lastNotifiedRemoteVersion';

  /// 已提醒过的远端版本；无文件 / 损坏 → null。
  static String? readLastNotified() {
    final file = AppPaths.updateNudgeFile;
    if (file == null || !file.existsSync()) return null;
    try {
      final raw = file.readAsStringSync();
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final v = json[_key];
      if (v is! String || v.isEmpty) return null;
      return Semver.parse(v) == null ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// 用户确认提醒后写入；失败静默。
  static void writeLastNotified(String remoteVersion) {
    final normalized = Semver.parse(remoteVersion);
    if (normalized == null) return;
    final file = AppPaths.updateNudgeFile;
    if (file == null) return;
    try {
      final text = jsonEncode({
        _key: '${normalized.$1}.${normalized.$2}.${normalized.$3}',
      });
      file.writeAsStringSync(text, flush: true);
    } catch (_) {}
  }

  /// 是否还应为该远端版本亮标签：远端必须严格高于上次已提醒版本。
  static bool shouldNudge(String remoteVersion) {
    final last = readLastNotified();
    if (last == null) return true;
    return Semver.isGreater(remoteVersion, last);
  }
}
