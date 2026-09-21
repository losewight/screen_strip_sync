/// 三段整数 semver 比较（只认 major.minor.patch；忽略 `+build` / 前缀 `v`）。
abstract final class Semver {
  /// 规范化：去 `v`/`V`、截掉 `+…` / `-…` 预发布后缀，再解析三段。
  static (int, int, int)? parse(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    final dash = s.indexOf('-');
    if (dash >= 0) s = s.substring(0, dash);
    final parts = s.split('.');
    if (parts.length < 2 || parts.length > 3) return null;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = parts.length == 3 ? int.tryParse(parts[2]) : 0;
    if (major == null || minor == null || patch == null) return null;
    if (major < 0 || minor < 0 || patch < 0) return null;
    return (major, minor, patch);
  }

  /// `a > b` → 正；相等 → 0；`a < b` → 负。解析失败返回 null。
  static int? compare(String a, String b) {
    final pa = parse(a);
    final pb = parse(b);
    if (pa == null || pb == null) return null;
    if (pa.$1 != pb.$1) return pa.$1 - pb.$1;
    if (pa.$2 != pb.$2) return pa.$2 - pb.$2;
    return pa.$3 - pb.$3;
  }

  static bool isGreater(String a, String b) {
    final c = compare(a, b);
    return c != null && c > 0;
  }
}
