import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'helper_status.dart';

const _ipcPort = 9527;
const _stillRunning = -1;

/// 解析 helper.exe：exe 同目录优先，开发时回退 `cpp_core/build/Release/`。
File resolveHelperExecutable() {
  final exeDir = File(Platform.resolvedExecutable).parent;
  final beside = File('${exeDir.path}${Platform.pathSeparator}helper.exe');
  if (beside.existsSync()) return beside;

  final dev = File(
    'cpp_core${Platform.pathSeparator}build'
    '${Platform.pathSeparator}Release${Platform.pathSeparator}helper.exe',
  );
  if (dev.existsSync()) return dev;

  throw StateError(
    '找不到 helper.exe（已查 exe 同目录与 cpp_core/build/Release/）',
  );
}

/// 拉起 helper、维护 Socket、按行收发 IPC 文本。
class HelperClient {
  Process? _proc;
  Socket? _sock;
  final StringBuffer _rxBuf = StringBuffer();
  StreamSubscription<List<int>>? _socketSub;

  final _statusController = StreamController<HelperStatusWord>.broadcast();
  final _disconnectController = StreamController<void>.broadcast();

  /// helper 推来的 `status` 词（ready / reconnecting / …）。
  Stream<HelperStatusWord> get statusStream => _statusController.stream;

  /// Socket 断开（helper 退出或网络错误）。
  Stream<void> get disconnectStream => _disconnectController.stream;

  bool get isConnected => _sock != null;

  Future<void> connect() async {
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
    _proc = await Process.start(
      helperFile.path,
      [],
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
    final word = tryParseStatusLine(line);
    if (word != null) {
      _statusController.add(word);
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
