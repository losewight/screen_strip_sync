import 'dart:io';

import '../config/app_config.dart';
import '../ipc/helper_client.dart';
import '../state/helper_ui_state.dart';
import 'app_paths.dart';
import 'crash_log.dart';

/// 与 [pubspec.yaml] `version:` 对齐；无 package_info 时硬编码。
const kAppVersion = '1.1.0';

/// helper.rc ProductVersion；与 C++ 启动横幅一致。
const kHelperVersion = '1.1.0';

const _helperLogName = 'helper.log';
const _configName = 'screen_strip_sync_config.json';
const _maxLogTailBytes = 200 * 1024;

/// 开源排障：本机拼诊断 txt（不上传、不经 IPC 推全文）。
abstract final class DiagExporter {
  /// 导出成功后的绝对路径。
  static Future<DiagExportResult> export({
    required HelperUiState ui,
    required AppConfig config,
    required bool helperConnected,
    void Function(String cmd)? sendIpc,
  }) async {
    if (helperConnected && sendIpc != null) {
      sendIpc('diag_mark');
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    final helperPath = _tryResolveHelper();
    final dataDir = resolveDataDirectory();
    final installDir = helperPath?.parent;
    final flutterDir = File(Platform.resolvedExecutable).parent;

    final buf = StringBuffer();
    buf.writeln('# Screen Strip Sync diagnostics');
    buf.writeln();
    buf.writeln('## meta');
    buf.writeln('exportedAt: ${DateTime.now().toIso8601String()}');
    buf.writeln('appVersion: $kAppVersion');
    buf.writeln('helperVersion: $kHelperVersion');
    buf.writeln(
      'os: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    buf.writeln('flutterExe: ${Platform.resolvedExecutable}');
    buf.writeln(
      'helperExe: ${helperPath?.path ?? "(not found)"}',
    );
    buf.writeln('dataDir: ${dataDir?.path ?? "(unknown)"}');
    buf.writeln('helperConnected: $helperConnected');
    buf.writeln();

    buf.writeln('## status');
    buf.writeln('phase: ${ui.phase.name}');
    buf.writeln('message: ${ui.message}');
    buf.writeln('currentCom: ${ui.currentCom}');
    buf.writeln('lastGoodCom: ${ui.lastGoodCom}');
    buf.writeln('hasDevice: ${ui.hasDevice}');
    buf.writeln('engineRunning: ${ui.engineRunning}');
    buf.writeln('canControl: ${ui.canControl}');
    buf.writeln('canConfigure: ${ui.canConfigure}');
    buf.writeln('lastScene: ${config.lastScene}');
    buf.writeln('comPort(config): ${config.comPort}');
    buf.writeln('autoSleepSync: ${config.autoSleepSync}');
    buf.writeln('turnOffOnShutdown: ${config.turnOffOnShutdown}');
    buf.writeln('startOnBoot: ${config.startOnBoot}');
    buf.writeln('emaAlpha: ${config.emaAlpha}');
    buf.writeln('nearBlack: ${config.nearBlack}');
    buf.writeln('blurStep: ${config.blurStep}');
    buf.writeln('saturation: ${config.saturation}');
    buf.writeln('saturationAlgo: ${config.saturationAlgo.name}');
    buf.writeln('sampleAlgo: ${config.sampleAlgo.name}');
    buf.writeln('nearBlackLuma: ${config.nearBlackLuma.name}');
    buf.writeln('regionAlgo: ${config.regionAlgo.name}');
    buf.writeln('regionBlur: ${config.regionBlur}');
    buf.writeln('regionSmooth: ${config.regionSmooth}');
    buf.writeln('regionDark: ${config.regionDark}');
    buf.writeln('regionBBox: ${config.regionBBox.toIpcPayload()}');
    buf.writeln('hasSegmentMap: ${config.hasSegmentMap}');
    buf.writeln();

    buf.writeln('## config');
    final configFile = _firstExisting([
      if (dataDir != null)
        File('${dataDir.path}${Platform.pathSeparator}$_configName'),
      if (installDir != null)
        File('${installDir.path}${Platform.pathSeparator}$_configName'),
      File('${flutterDir.path}${Platform.pathSeparator}$_configName'),
    ]);
    if (configFile != null) {
      buf.writeln('path: ${configFile.path}');
      buf.writeln('```json');
      buf.writeln(configFile.readAsStringSync());
      buf.writeln('```');
    } else {
      buf.writeln('(config file not found)');
    }
    buf.writeln();

    buf.writeln('## helper.log (tail)');
    final helperLog = _firstExisting([
      if (dataDir != null)
        File('${dataDir.path}${Platform.pathSeparator}$_helperLogName'),
      if (installDir != null)
        File('${installDir.path}${Platform.pathSeparator}$_helperLogName'),
      File('${flutterDir.path}${Platform.pathSeparator}$_helperLogName'),
    ]);
    if (helperLog != null) {
      buf.writeln('path: ${helperLog.path}');
      buf.writeln('```');
      _writeTail(buf, helperLog, _maxLogTailBytes);
      buf.writeln('```');
    } else {
      buf.writeln('(helper.log not found)');
    }
    buf.writeln();

    buf.writeln('## crash.log');
    final crashLog = _firstExisting([
      File(CrashLog.filePath),
      if (dataDir != null)
        File(
          '${dataDir.path}${Platform.pathSeparator}${CrashLog.fileName}',
        ),
      if (installDir != null)
        File(
          '${installDir.path}${Platform.pathSeparator}${CrashLog.fileName}',
        ),
    ]);
    if (crashLog != null) {
      buf.writeln('path: ${crashLog.path}');
      buf.writeln('```');
      _writeTail(buf, crashLog, _maxLogTailBytes);
      buf.writeln('```');
    } else {
      buf.writeln('(crash log not found)');
    }

    final outPath = _outputPath();
    final out = File(outPath);
    await out.writeAsString(buf.toString(), flush: true);

    return DiagExportResult(
      path: out.path,
      dataDir: dataDir?.path,
    );
  }

  /// 日志 / 配置所在数据目录（%LocalAppData%\\Screen Strip Sync）。
  static Directory? resolveDataDirectory() => AppPaths.dataDirectory;

  /// 在资源管理器中选中 [path]。
  static Future<void> revealInExplorer(String path) async {
    await Process.start('explorer.exe', ['/select,', path]);
  }

  /// 打开目录（日志所在文件夹）。
  static Future<void> openDirectory(String dirPath) async {
    await Process.start('explorer.exe', [dirPath]);
  }

  static File? _tryResolveHelper() {
    try {
      return resolveHelperExecutable();
    } catch (_) {
      return null;
    }
  }

  static File? _firstExisting(List<File> files) {
    for (final f in files) {
      if (f.existsSync()) return f;
    }
    return null;
  }

  static String _outputPath() {
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final name = 'screen_strip_sync_diag_$stamp.txt';
    final user = Platform.environment['USERPROFILE'];
    if (user != null && user.isNotEmpty) {
      final desktop = Directory('$user${Platform.pathSeparator}Desktop');
      if (desktop.existsSync()) {
        return '${desktop.path}${Platform.pathSeparator}$name';
      }
    }
    return '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}$name';
  }

  static void _writeTail(StringBuffer buf, File file, int maxBytes) {
    final text = _readTail(file, maxBytes);
    buf.write(text);
    if (text.isNotEmpty && !text.endsWith('\n')) {
      buf.writeln();
    }
  }

  static String _readTail(File file, int maxBytes) {
    final raf = file.openSync(mode: FileMode.read);
    try {
      final len = raf.lengthSync();
      final start = len > maxBytes ? len - maxBytes : 0;
      raf.setPositionSync(start);
      final bytes = raf.readSync(len - start);
      var text = String.fromCharCodes(bytes);
      if (start > 0) {
        final nl = text.indexOf('\n');
        if (nl >= 0 && nl + 1 < text.length) {
          text = text.substring(nl + 1);
        }
      }
      return text;
    } finally {
      raf.closeSync();
    }
  }
}

class DiagExportResult {
  const DiagExportResult({required this.path, this.dataDir});

  final String path;
  final String? dataDir;
}
