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

HelperStatusWord parseHelperStatusWord(String word) {
  return switch (word) {
    'ready' => HelperStatusWord.ready,
    'reconnecting' => HelperStatusWord.reconnecting,
    'reconnect_ok' => HelperStatusWord.reconnectOk,
    'reconnect_fail' => HelperStatusWord.reconnectFail,
    _ => HelperStatusWord.unknown,
  };
}

/// 解析一行 helper 输出；非 `status` 前缀或未知 kv 返回 null。
HelperStatusEvent? tryParseStatusLine(String line) {
  if (!line.startsWith('status ')) return null;
  final rest = line.substring(7).trim();
  if (rest.isEmpty) return null;

  final space = rest.indexOf(' ');
  if (space < 0) {
    // 缺参的 com/engine 不算相位词
    if (rest == 'com' || rest == 'engine') return null;
    return HelperStatusPhase(parseHelperStatusWord(rest));
  }

  final key = rest.substring(0, space);
  final value = rest.substring(space + 1).trim();

  return switch (key) {
    'com' when value.isNotEmpty => HelperStatusCom(value),
    'engine' when value == '0' || value == '1' => HelperStatusEngine(
      value == '1',
    ),
    _ => null,
  };
}
