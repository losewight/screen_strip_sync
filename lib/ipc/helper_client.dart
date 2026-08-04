import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'helper_status.dart';

const _ipcPort = 9527;
const _stillRunning = -1;

/// 解析 helper.exe：exe 同目录优先；开发时从 exe 向上找仓库内
/// `cpp_core/build/Release/helper.exe`（不依赖进程 CWD）。
File resolveHelperExecutable() {
  final exeDir = File(Platform.resolvedExecutable).parent;
  final beside = File('${exeDir.path}${Platform.pathSeparator}helper.exe');
  if (beside.existsSync()) return beside;

  var dir = exeDir;
  for (var i = 0; i < 10; i++) {
    final dev = File(
      '${dir.path}${Platform.pathSeparator}cpp_core'
      '${Platform.pathSeparator}build'
      '${Platform.pathSeparator}Release'
      '${Platform.pathSeparator}helper.exe',
    );
    if (dev.existsSync()) return dev;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  throw StateError(
    '找不到 helper.exe（已查 exe 同目录与向上遍历的 cpp_core/build/Release/）',
  );
}

/// 拉起 helper、维护 Socket、按行收发 IPC 文本。
class HelperClient {
  Process? _proc;
  Socket? _sock;
  final StringBuffer _rxBuf = StringBuffer();
  StreamSubscription<List<int>>? _socketSub;

  final _statusController = StreamController<HelperStatusEvent>.broadcast();
  final _disconnectController = StreamController<void>.broadcast();
  final _uiShowController = StreamController<void>.broadcast();
  final _configController = StreamController<AppConfig>.broadcast();
  final _cfgBuf = <String>[];

  /// helper 推来的 `status` 事件（相位 / com / engine）。
  Stream<HelperStatusEvent> get statusStream => _statusController.stream;

  /// Socket 断开（helper 退出或网络错误）。
  Stream<void> get disconnectStream => _disconnectController.stream;

  /// 托盘双击且已有客户端：helper 推 `ui show`，前端置顶窗口。
  Stream<void> get uiShowStream => _uiShowController.stream;

  /// 每次 `cfg …` + `cfg end` 组成的完整快照（可多次推送）。
  Stream<AppConfig> get configSnapshots => _configController.stream;

  bool get isConnected => _sock != null;

  /// 先试连已有 helper；失败才 `Process.start(..., ['--no-ui'])` 再重试。
  /// [comPort] 保留参数兼容；开口只走 JSON / IPC（H2 后 argv 不再传 COM）。
  Future<void> connect({String? comPort}) async {
    if (isConnected) return;

    await _teardownSocket();

    const failMsg = '连接失败：helper 未就绪或已退出，请确认灯带已插上后重试';

    // 为什么：helper 已常驻时直接连，避免再起次实例又立刻退出导致误判失败（H5）
    try {
      final existing = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _ipcPort,
        timeout: const Duration(milliseconds: 300),
      );
      _sock = existing;
      _listenSocket(existing);
      debugPrint('helper: connected to existing instance');
      return;
    } catch (_) {
      // 未在听 → 自拉或等已有子进程就绪
    }

    // 为什么：前端绝不杀 helper。若上次自拉的进程还在，只重试连，不再 spawn。
    var needSpawn = true;
    if (_proc != null) {
      final exitCode = await _proc!.exitCode.timeout(
        Duration.zero,
        onTimeout: () => _stillRunning,
      );
      if (exitCode == _stillRunning) {
        needSpawn = false;
        debugPrint('helper: child still running, retry connect only');
      } else {
        _proc = null;
      }
    }

    if (needSpawn) {
      final helperFile = resolveHelperExecutable();
      debugPrint('helper: ${helperFile.path} --no-ui');
      // 为什么：必须 --no-ui，否则 helper 再 CreateProcess 一个 Flutter，互相拉起
      _proc = await Process.start(
        helperFile.path,
        const ['--no-ui'],
        workingDirectory: helperFile.parent.path,
      );
    }

    const maxTries = 10;
    Socket? sock;
    Object? lastErr;

    for (var i = 1; i <= maxTries; i++) {
      final proc = _proc;
      if (proc != null) {
        final exitCode = await proc.exitCode.timeout(
          Duration.zero,
          onTimeout: () => _stillRunning,
        );
        if (exitCode != _stillRunning) {
          debugPrint('helper exited early: code=$exitCode');
          _proc = null;
          throw StateError(failMsg);
        }
      }

      try {
        sock = await Socket.connect(
          InternetAddress.loopbackIPv4,
          _ipcPort,
          timeout: const Duration(milliseconds: 300),
        );
        break;
      } catch (e) {
        lastErr = e;
        if (i < maxTries) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    }

    if (sock == null) {
      debugPrint('Socket.connect failed: $lastErr');
      // 松手句柄，不 kill：常驻实例由托盘 / quit IPC 管生命周期
      _proc = null;
      throw StateError(failMsg);
    }

    _sock = sock;
    _listenSocket(sock);
  }

  void _listenSocket(Socket sock) {
    _socketSub?.cancel();
    _socketSub = sock.listen(
      (data) {
        _rxBuf.write(utf8.decode(data));
        var chunk = _rxBuf.toString();
        var nl = chunk.indexOf('\n');
        while (nl >= 0) {
          final line = chunk.substring(0, nl).trimRight();
          chunk = chunk.substring(nl + 1);
          _onLine(line);
          nl = chunk.indexOf('\n');
        }
        _rxBuf
          ..clear()
          ..write(chunk);
      },
      onError: (Object e) {
        debugPrint('IPC socket error: $e');
        _handleDisconnect();
      },
      onDone: _handleDisconnect,
      cancelOnError: true,
    );
  }

  void _onLine(String line) {
    if (line.isEmpty) return;
    if (line == 'ui show') {
      if (!_uiShowController.isClosed) {
        _uiShowController.add(null);
      }
      return;
    }
    if (line.startsWith('cfg ')) {
      if (line == 'cfg end') {
        final snap = AppConfig.fromCfgLines(_cfgBuf);
        _cfgBuf.clear();
        if (!_configController.isClosed) {
          _configController.add(snap);
        }
        return;
      }
      _cfgBuf.add(line);
      return;
    }
    final event = tryParseStatusLine(line);
    if (event != null) {
      _statusController.add(event);
    }
  }

  void _handleDisconnect() {
    if (_sock != null) {
      _disconnectController.add(null);
    }
    unawaited(_teardownSocket());
  }

  void send(String cmd) {
    final sock = _sock;
    if (sock == null) {
      throw StateError('未连接 helper');
    }
    sock.write('$cmd\n');
  }

  /// 前端退出 / 断连：发 `bye`，只关 Socket；helper 灯效与进程保持。
  Future<void> quit() async {
    final sock = _sock;
    if (sock != null) {
      try {
        sock.write('bye\n');
      } catch (_) {}
      await _teardownSocket();
    }
  }

  Future<void> dispose() async {
    await quit();
    if (!_statusController.isClosed) {
      await _statusController.close();
    }
    if (!_disconnectController.isClosed) {
      await _disconnectController.close();
    }
    if (!_uiShowController.isClosed) {
      await _uiShowController.close();
    }
    if (!_configController.isClosed) {
      await _configController.close();
    }
  }

  Future<void> _teardownSocket() async {
    await _socketSub?.cancel();
    _socketSub = null;
    _rxBuf.clear();
    _cfgBuf.clear();
    final sock = _sock;
    _sock = null;
    if (sock != null) {
      try {
        sock.destroy();
      } catch (_) {}
    }
  }
}

final helperClientProvider = Provider<HelperClient>((ref) {
  final client = HelperClient();
  ref.onDispose(() => client.dispose());
  return client;
});
