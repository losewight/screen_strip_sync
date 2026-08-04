import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/crash_hooks.dart';
import 'app/crash_log.dart';
import 'app/ui_singleton.dart';

Future<void> main() async {
  CrashLog.event('main', 'startup log=${CrashLog.filePath}');
  // 为什么：binding 与 runApp 必须在同一 zone；await 插件后再 runZonedGuarded 会错位
  WidgetsFlutterBinding.ensureInitialized();

  // 为什么：第二实例不得开窗；托盘唤回走 helper H5，此处只 exit
  if (!tryAcquireUiSingleton()) {
    CrashLog.event('main', 'ui singleton held, exit');
    exit(0);
  }

  installCrashHooks();

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

  // 为什么：Windows Debug 下 AXTree 更新失败会 assert 杀进程（Lost connection）；
  // 本 App 不依赖读屏，ExcludeSemantics 关掉语义桥即可避开。
  runApp(
    const ProviderScope(
      child: ExcludeSemantics(child: ZeerayApp()),
    ),
  );
  CrashLog.event('main', 'runApp done');
}
