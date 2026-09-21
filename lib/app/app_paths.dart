import 'dart:io';

/// 可写数据目录：%LocalAppData%\Screen Strip Sync\
/// 与安装位置无关；配置 / 日志 / crash 均在此。
abstract final class AppPaths {
  static const folderName = 'Screen Strip Sync';

  /// 数据目录；不存在时尝试创建。
  static Directory? get dataDirectory {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return null;
    final dir = Directory(
      '$local${Platform.pathSeparator}$folderName',
    );
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    } catch (_) {
      return null;
    }
    return dir;
  }

  static File? get helperLogFile =>
      _fileInDataDir('helper.log');

  static File? get configFile =>
      _fileInDataDir('screen_strip_sync_config.json');

  static File? get crashLogFile =>
      _fileInDataDir('screen_strip_sync_crash.log');

  /// UI 更新提醒落盘（与 helper 配置文件分离，避免双写）。
  static File? get updateNudgeFile =>
      _fileInDataDir('update_nudge.json');

  static File? _fileInDataDir(String name) {
    final dir = dataDirectory;
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$name');
  }
}
