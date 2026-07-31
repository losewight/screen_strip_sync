import 'dart:convert';
import 'dart:io';

/// 米家追光灯带 Pro 常用 CH340：USB\VID_1A86&PID_7523
const kZeerayUsbVidPid = 'VID_1A86&PID_7523';

/// 本机枚举到的一个串口（不经 IPC）。
class ComPortInfo {
  const ComPortInfo({
    required this.port,
    required this.displayName,
    required this.preferred,
  });

  /// 规范名，如 `COM10`（给 config / 将来 set com）。
  final String port;

  /// 设备管理器友好名，如 `USB-SERIAL CH340 (COM10)`。
  final String displayName;

  /// PNPDeviceID 含 [kZeerayUsbVidPid]。
  final bool preferred;
}

/// 本机枚举 COM 口；优先 PnP 友好名 + VID/PID，失败再回退注册表口名。
Future<List<ComPortInfo>> scanWindowsComPorts() async {
  if (!Platform.isWindows) return const [];

  final fromPnp = await _portsFromPnp();
  if (fromPnp.isNotEmpty) return fromPnp;
  return _portsFromRegistryFallback();
}

Future<List<ComPortInfo>> _portsFromPnp() async {
  try {
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        r"Get-CimInstance Win32_PnPEntity | "
            r"Where-Object { $_.Name -match '\(COM\d+\)' } | "
            r"Select-Object Name, PNPDeviceID | "
            r"ConvertTo-Json -Compress",
      ],
      runInShell: true,
    );
    if (result.exitCode != 0) return const [];

    final raw = '${result.stdout}'.trim();
    if (raw.isEmpty) return const [];

    final decoded = jsonDecode(raw);
    // 为什么：只有 1 个口时 ConvertTo-Json 给的是 Map，不是 List
    final List<dynamic> rows;
    if (decoded is List) {
      rows = decoded;
    } else if (decoded is Map) {
      rows = [decoded];
    } else {
      return const [];
    }

    final portRe = RegExp(r'\((COM\d+)\)', caseSensitive: false);
    final byPort = <String, ComPortInfo>{};

    for (final row in rows) {
      if (row is! Map) continue;
      final name = '${row['Name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final m = portRe.firstMatch(name);
      if (m == null) continue;
      final port = m.group(1)!.toUpperCase();
      final pnpId = '${row['PNPDeviceID'] ?? ''}'.toUpperCase();
      final preferred = pnpId.contains(kZeerayUsbVidPid);
      final prev = byPort[port];
      // 同口多条时：保留 preferred，或保留已有
      if (prev == null || (!prev.preferred && preferred)) {
        byPort[port] = ComPortInfo(
          port: port,
          displayName: name,
          preferred: preferred,
        );
      }
    }

    final ports = byPort.values.toList()..sort(_comPortCompare);
    return ports;
  } catch (_) {
    return const [];
  }
}

Future<List<ComPortInfo>> _portsFromRegistryFallback() async {
  try {
    final result = await Process.run(
      'reg',
      ['query', r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM'],
      runInShell: true,
    );
    if (result.exitCode != 0) return const [];

    final ports = <ComPortInfo>[];
    final regex = RegExp(r'COM\d+', caseSensitive: false);
    for (final line in '${result.stdout}'.split('\n')) {
      for (final m in regex.allMatches(line)) {
        final p = m.group(0)!.toUpperCase();
        if (ports.any((e) => e.port == p)) continue;
        ports.add(ComPortInfo(port: p, displayName: p, preferred: false));
      }
    }
    ports.sort(_comPortCompare);
    return ports;
  } catch (_) {
    return const [];
  }
}

/// preferred 在前；同组按 COM 编号数值排（COM2 < COM10）。
int _comPortCompare(ComPortInfo a, ComPortInfo b) {
  if (a.preferred != b.preferred) {
    return a.preferred ? -1 : 1;
  }
  return _comNumber(a.port).compareTo(_comNumber(b.port));
}

int _comNumber(String port) =>
    int.tryParse(port.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
