import 'dart:io';

import 'package:flutter/foundation.dart';

/// 偶发无声退出诊断：append 到 exe 同目录 [fileName]。
class CrashLog {
  CrashLog._();

  static const fileName = 'zeeray_crash.log';

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
      final f = File(
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}$fileName',
      );
      f.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // 写盘失败不能再抛
    }
  }
}
