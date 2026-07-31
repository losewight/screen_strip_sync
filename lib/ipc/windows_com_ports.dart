import 'dart:io';

/// 本机枚举 COM 口（不经 IPC）；CH340 用 PnP 友好名粗筛。
Future<({List<String> all, List<String> ch340})> scanWindowsComPorts() async {
  if (!Platform.isWindows) {
    return (all: <String>[], ch340: <String>[]);
  }

  final all = await _portsFromRegistry();
  final ch340 = await _ch340Ports();
  return (all: all, ch340: ch340);
}

Future<List<String>> _portsFromRegistry() async {
  try {
    final result = await Process.run(
      'reg',
      ['query', r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM'],
      runInShell: true,
    );
    if (result.exitCode != 0) return [];

    final ports = <String>[];
    final regex = RegExp(r'COM\d+', caseSensitive: false);
    for (final line in '${result.stdout}'.split('\n')) {
      for (final m in regex.allMatches(line)) {
        final p = m.group(0)!.toUpperCase();
        if (!ports.contains(p)) ports.add(p);
      }
    }
    ports.sort(_comSort);
    return ports;
  } catch (_) {
    return [];
  }
}

Future<List<String>> _ch340Ports() async {
  try {
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        "Get-CimInstance Win32_PnPEntity | "
            "Where-Object { \$_.Name -match 'CH340' -and \$_.Name -match 'COM\\d+' } | "
            "ForEach-Object { if (\$_.Name -match '(COM\\d+)') { \$matches[1] } }",
      ],
      runInShell: true,
    );
    if (result.exitCode != 0) return [];

    final ports = <String>[];
    for (final line in '${result.stdout}'.split('\n')) {
      final p = line.trim().toUpperCase();
      if (p.startsWith('COM') && !ports.contains(p)) ports.add(p);
    }
    ports.sort(_comSort);
    return ports;
  } catch (_) {
    return [];
  }
}

int _comSort(String a, String b) {
  final na = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  final nb = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  return na.compareTo(nb);
}
