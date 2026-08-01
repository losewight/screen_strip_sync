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

/// 显示意图：`status display engine|solid|soft_off|idle`
enum HelperDisplayKind { idle, engine, solid, softOff }

final class HelperStatusDisplay extends HelperStatusEvent {
  const HelperStatusDisplay(this.kind);

  final HelperDisplayKind kind;
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
    // 缺参的 com/engine/display 不算相位词
    if (rest == 'com' || rest == 'engine' || rest == 'display') return null;
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
  return null;
}
