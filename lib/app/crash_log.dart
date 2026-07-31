import 'dart:io';

import 'package:flutter/foundation.dart';

/// 偶发无声退出诊断：append 到 exe 同目录 [fileName]。
class CrashLog {
  CrashLog._();

  static const fileName = 'zeeray_crash.log';

  /// 超过此行数时，启动时裁到 [keepLines] 行（只裁一次 / 进程）。
  static const maxLines = 300;
  static const keepLines = 150;

  static bool _trimChecked = false;

  /// 日志绝对路径（exe 同目录，与 [config_store] / [helper_client] 一致）。
  static String get filePath =>
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}$fileName';

  /// Dart / Flutter 未捕获异常。
  static void error(String source, Object error, StackTrace? stack) {
    _append('ERROR', source, '$error\n${stack ?? StackTrace.current}');
  }

  /// 生命周期等标记（区分关窗退出 vs 真崩溃）。
  static void event(String source, String message) {
    _append('EVENT', source, message);
  }

  static void _append(String level, String source, String body) {
    final line =
        '[${DateTime.now().toIso8601String()}][$level][$source] '
        '$body\n';
    debugPrint('CrashLog: $line');
    try {
      final f = File(filePath);
      _trimIfNeeded(f);
      f.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // 写盘失败不能再抛
    }
  }

  static void _trimIfNeeded(File f) {
    if (_trimChecked) return;
    _trimChecked = true;
    if (!f.existsSync()) return;

    try {
      final lines = f.readAsLinesSync();
      if (lines.length <= maxLines) return;

      final kept = lines.sublist(lines.length - keepLines);
      final header =
          '[${DateTime.now().toIso8601String()}][EVENT][crash_log] '
          'trimmed ${lines.length} -> ${kept.length} lines\n';
      f.writeAsStringSync('$header${kept.join('\n')}\n', flush: true);
    } catch (_) {
      // 裁切失败则继续 append，不挡启动
    }
  }
}
