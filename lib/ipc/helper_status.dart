/// helper → Flutter 的 `status <word>` 行。
enum HelperStatusWord {
  ready,
  reconnecting,
  reconnectOk,
  reconnectFail,
  unknown,
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

/// 解析一行 helper 输出；非 `status` 前缀返回 null。
HelperStatusWord? tryParseStatusLine(String line) {
  if (!line.startsWith('status ')) return null;
  return parseHelperStatusWord(line.substring(7).trim());
}
