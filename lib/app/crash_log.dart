import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';

/// 偶发无声退出诊断：append 到数据目录 [fileName]。
class CrashLog {
  CrashLog._();

  static const fileName = 'screen_strip_sync_crash.log';

  static const maxLines = 300;
  static const keepLines = 150;

  static bool _trimChecked = false;

  static String get filePath {
    final inData = AppPaths.crashLogFile?.path;
    if (inData != null) return inData;
    return '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}$fileName';
  }

  static void error(String source, Object error, StackTrace? stack) {
    _append('ERROR', source, '$error\n${stack ?? StackTrace.current}');
  }

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
    } catch (_) {}
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
    } catch (_) {}
  }
}
