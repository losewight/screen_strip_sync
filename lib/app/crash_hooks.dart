import 'dart:async';

import 'package:flutter/foundation.dart';

import 'crash_log.dart';

/// 在 [WidgetsFlutterBinding.ensureInitialized] 之后、业务逻辑之前调用。
void installCrashHooks() {
  FlutterError.onError = (details) {
    CrashLog.error('FlutterError', details.exception, details.stack);
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    CrashLog.error('PlatformDispatcher', error, stack);
    return true;
  };
}

/// 包一层 zone，兜 async gap 里漏网的未捕获错误。
Future<void> runGuarded(Future<void> Function() body) async {
  await runZonedGuarded(body, (error, stack) {
    CrashLog.error('runZonedGuarded', error, stack);
  });
}
