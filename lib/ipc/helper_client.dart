import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// helper 推来的 `status` 事件（相位 / com / engine）。
  Stream<HelperStatusEvent> get statusStream => _statusController.stream;

  /// Socket 断开（helper 退出或网络错误）。
  Stream<void> get disconnectStream => _disconnectController.stream;

  bool get isConnected => _sock != null;

  /// [comPort] 传给 helper 作 argv[1]，启动时就开对口（不再死开 COM10）。
  Future<void> connect({String? comPort}) async {
    if (isConnected) return;

    await _teardownSocket();

    if (_proc != null) {
      final exitCode = await _proc!.exitCode.timeout(
        Duration.zero,
        onTimeout: () => _stillRunning,
      );
      if (exitCode == _stillRunning) {
        await _killHelper();
      } else {
        _proc = null;
      }
    }

    final helperFile = resolveHelperExecutable();
    debugPrint('helper: ${helperFile.path}');
    final args = <String>[];
    final com = comPort?.trim();
    if (com != null && com.isNotEmpty) {
      args.add(com);
    }
    _proc = await Process.start(
      helperFile.path,
      args,
      workingDirectory: helperFile.parent.path,
    );

    const maxTries = 10;
    const failMsg = '连接失败：helper 未就绪或已退出，请确认灯带已插上后重试';
    Socket? sock;
    Object? lastErr;

    for (var i = 1; i <= maxTries; i++) {
      final exitCode = await _proc!.exitCode.timeout(
        Duration.zero,
        onTimeout: () => _stillRunning,
      );
      if (exitCode != _stillRunning) {
        debugPrint('helper exited early: code=$exitCode');
        _proc = null;
        throw StateError(failMsg);
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
      await _killHelper();
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

  /// 礼貌退出：发 quit，关 Socket；helper 自行关灯后进程结束。
  Future<void> quit() async {
    final sock = _sock;
    if (sock != null) {
      try {
        sock.write('quit\n');
      } catch (_) {}
      await _teardownSocket();
    }

    final proc = _proc;
    if (proc != null) {
      await proc.exitCode.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => _stillRunning,
      );
      _proc = null;
    }
  }

  Future<void> dispose() async {
    await quit();
    await _killHelper();
    if (!_statusController.isClosed) {
      await _statusController.close();
    }
    if (!_disconnectController.isClosed) {
      await _disconnectController.close();
    }
  }

  Future<void> _teardownSocket() async {
    await _socketSub?.cancel();
    _socketSub = null;
    _rxBuf.clear();
    final sock = _sock;
    _sock = null;
    if (sock != null) {
      try {
        sock.destroy();
      } catch (_) {}
    }
  }

  Future<void> _killHelper() async {
    await _teardownSocket();
    final proc = _proc;
    _proc = null;
    if (proc != null) {
      try {
        proc.kill();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
}

final helperClientProvider = Provider<HelperClient>((ref) {
  final client = HelperClient();
  ref.onDispose(() => client.dispose());
  return client;
});
