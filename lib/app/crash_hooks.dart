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
