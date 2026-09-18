/// helper → Flutter 的 `status …` 行（单词或 key value）。
enum HelperStatusWord {
  ready,
  reconnecting,
  reconnectOk,
  reconnectFail,
  unknown,
}

/// 解析后的 helper 状态事件。
sealed class HelperStatusEvent {
  const HelperStatusEvent();
}

/// 连接相位词：`ready` / `reconnecting` / …
final class HelperStatusPhase extends HelperStatusEvent {
  const HelperStatusPhase(this.word);

  final HelperStatusWord word;
}

/// 当前已打开的串口：`status com COM10`
final class HelperStatusCom extends HelperStatusEvent {
  const HelperStatusCom(this.port);

  final String port;
}

/// 追色引擎线程：`status engine 0|1`
final class HelperStatusEngine extends HelperStatusEvent {
  const HelperStatusEngine(this.running);

  final bool running;
}

/// 显示意图：`status display engine|region|solid|soft_off|idle`
enum HelperDisplayKind { idle, engine, region, solid, softOff }

final class HelperStatusDisplay extends HelperStatusEvent {
  const HelperStatusDisplay(this.kind);

  final HelperDisplayKind kind;
}

/// 当前真正 duplicate 的那块屏：`status capture_output NAME WxH L,T [friendly…]`
final class HelperStatusCaptureOutput extends HelperStatusEvent {
  const HelperStatusCaptureOutput({
    required this.name,
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    this.friendlyName = '',
  });

  final String name;
  final int width;
  final int height;
  final int left;
  final int top;

  /// CCD/EDID 友好名；旧 helper 不带则为空。
  final String friendlyName;
}

/// `status outputs <n>`：随后紧跟 n 条 [HelperStatusOutput]。
final class HelperStatusOutputsCount extends HelperStatusEvent {
  const HelperStatusOutputsCount(this.count);

  final int count;
}

/// 一条可 duplicate 的屏：`status output i NAME WxH L,T primary current [friendly…]`
final class HelperStatusOutput extends HelperStatusEvent {
  const HelperStatusOutput({
    required this.index,
    required this.name,
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    required this.isPrimary,
    required this.isCurrent,
    this.friendlyName = '',
  });

  final int index;
  final String name;
  final int width;
  final int height;
  final int left;
  final int top;
  final bool isPrimary;
  final bool isCurrent;
  final String friendlyName;
}

HelperStatusWord parseHelperStatusWord(String word) {
  return switch (word) {
    'ready' => HelperStatusWord.ready,
    'reconnecting' => HelperStatusWord.reconnecting,
    'reconnect_ok' => HelperStatusWord.reconnectOk,
    'reconnect_fail' => HelperStatusWord.reconnectFail,
    _ => HelperStatusWord.unknown,
  };
}

HelperDisplayKind? parseHelperDisplayKind(String value) {
  return switch (value) {
    'idle' => HelperDisplayKind.idle,
    'engine' => HelperDisplayKind.engine,
    'region' => HelperDisplayKind.region,
    'solid' => HelperDisplayKind.solid,
    'soft_off' => HelperDisplayKind.softOff,
    _ => null,
  };
}

/// 解析一行 helper 输出；非 `status` 前缀或未知 kv 返回 null。
HelperStatusEvent? tryParseStatusLine(String line) {
  if (!line.startsWith('status ')) return null;
  final rest = line.substring(7).trim();
  if (rest.isEmpty) return null;

  final space = rest.indexOf(' ');
  if (space < 0) {
    // 缺参的 kv 不算相位词
    if (rest == 'com' ||
        rest == 'engine' ||
        rest == 'display' ||
        rest == 'capture_output' ||
        rest == 'outputs' ||
        rest == 'output') {
      return null;
    }
    return HelperStatusPhase(parseHelperStatusWord(rest));
  }

  final key = rest.substring(0, space);
  final value = rest.substring(space + 1).trim();

  if (key == 'com' && value.isNotEmpty) {
    return HelperStatusCom(value);
  }
  if (key == 'engine' && (value == '0' || value == '1')) {
    return HelperStatusEngine(value == '1');
  }
  if (key == 'display') {
    final kind = parseHelperDisplayKind(value);
    if (kind != null) return HelperStatusDisplay(kind);
  }
  if (key == 'capture_output') {
    return _parseCaptureOutput(value);
  }
  if (key == 'outputs') {
    final n = int.tryParse(value);
    if (n != null && n >= 0) return HelperStatusOutputsCount(n);
  }
  if (key == 'output') {
    return _parseOutput(value);
  }
  return null;
}

final _captureOutputRest = RegExp(
  r'^(\S+)\s+(\d+)x(\d+)\s+(-?\d+),(-?\d+)(?:\s+(.+))?$',
);
final _outputRest = RegExp(
  r'^(\d+)\s+(\S+)\s+(\d+)x(\d+)\s+(-?\d+),(-?\d+)\s+([01])\s+([01])(?:\s+(.+))?$',
);

HelperStatusCaptureOutput? _parseCaptureOutput(String value) {
  final m = _captureOutputRest.firstMatch(value);
  if (m == null) return null;
  return HelperStatusCaptureOutput(
    name: m.group(1)!,
    width: int.parse(m.group(2)!),
    height: int.parse(m.group(3)!),
    left: int.parse(m.group(4)!),
    top: int.parse(m.group(5)!),
    friendlyName: m.group(6)?.trim() ?? '',
  );
}

HelperStatusOutput? _parseOutput(String value) {
  final m = _outputRest.firstMatch(value);
  if (m == null) return null;
  return HelperStatusOutput(
    index: int.parse(m.group(1)!),
    name: m.group(2)!,
    width: int.parse(m.group(3)!),
    height: int.parse(m.group(4)!),
    left: int.parse(m.group(5)!),
    top: int.parse(m.group(6)!),
    isPrimary: m.group(7) == '1',
    isCurrent: m.group(8) == '1',
    friendlyName: m.group(9)?.trim() ?? '',
  );
}
