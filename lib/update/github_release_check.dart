import 'dart:convert';
import 'dart:io';

import '../app/diag_export.dart';
import 'semver.dart';

/// GitHub Releases「是否有新版本」探测结果。
///
/// 这是前端职责表里「网络请求」的唯一例外：opt-in、失败静默、不经 helper、
/// 不下载安装包，只拿 `tag_name` 做比较。
class ReleaseCheckResult {
  const ReleaseCheckResult({
    required this.updateAvailable,
    this.remoteVersion,
    this.releaseUrl,
  });

  /// 远端严格高于本地。
  final bool updateAvailable;
  final String? remoteVersion;
  final String? releaseUrl;

  static const none = ReleaseCheckResult(updateAvailable: false);
}

/// 查询 `losewight/screen_strip_sync` 最新 Release。
abstract final class GithubReleaseCheck {
  static const owner = 'losewight';
  static const repo = 'screen_strip_sync';
  static const _apiUrl =
      'https://api.github.com/repos/$owner/$repo/releases/latest';
  static const _timeout = Duration(seconds: 5);

  /// 与 [kAppVersion] 比较；任何失败返回 [ReleaseCheckResult.none]。
  static Future<ReleaseCheckResult> checkLatest({
    String localVersion = kAppVersion,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _timeout;
      final req = await client
          .getUrl(Uri.parse(_apiUrl))
          .timeout(_timeout);
      req.headers.set(HttpHeaders.userAgentHeader, 'ScreenStripSync');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        return ReleaseCheckResult.none;
      }
      final body = await res.transform(utf8.decoder).join().timeout(_timeout);
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return ReleaseCheckResult.none;
      final tag = json['tag_name'];
      if (tag is! String || tag.isEmpty) return ReleaseCheckResult.none;
      final remote = tag.trim();
      final htmlUrl = json['html_url'];
      final url = htmlUrl is String && htmlUrl.isNotEmpty
          ? htmlUrl
          : 'https://github.com/$owner/$repo/releases/tag/$remote';
      if (!Semver.isGreater(remote, localVersion)) {
        return ReleaseCheckResult(
          updateAvailable: false,
          remoteVersion: Semver.parse(remote) == null ? null : _stripTag(remote),
          releaseUrl: url,
        );
      }
      return ReleaseCheckResult(
        updateAvailable: true,
        remoteVersion: _stripTag(remote),
        releaseUrl: url,
      );
    } catch (_) {
      return ReleaseCheckResult.none;
    } finally {
      client?.close(force: true);
    }
  }

  static String _stripTag(String tag) {
    final p = Semver.parse(tag);
    if (p == null) return tag;
    return '${p.$1}.${p.$2}.${p.$3}';
  }
}
