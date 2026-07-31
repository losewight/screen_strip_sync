import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/crash_hooks.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  installCrashHooks();

  await runGuarded(() async {
    await windowManager.ensureInitialized();

    // 为什么：系统标题栏换成自绘商店风顶栏，必须先藏原生 chrome

    const windowOptions = WindowOptions(
      size: Size(1100, 720),

      minimumSize: Size(800, 520),

      center: true,

      backgroundColor: Colors.transparent,

      skipTaskbar: false,

      titleBarStyle: TitleBarStyle.hidden,

      title: 'Zeeray Ambilight',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();

      await windowManager.focus();
    });

    runApp(const ProviderScope(child: ZeerayApp()));
  });
}
