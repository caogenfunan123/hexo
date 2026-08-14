/// 自动更新检查服务：查询 GitHub Releases 最新版本
///
/// 使用公开 Releases API（无需 token）：
///   GET https://api.github.com/repos/{owner}/{repo}/releases/latest
/// 对比当前版本（pubspec version），存在新版本时返回更新信息。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// 更新信息
class ReleaseInfo {
  final String tagName;
  final String name;
  final String htmlUrl;
  final String body;
  final DateTime? publishedAt;

  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.htmlUrl,
    required this.body,
    this.publishedAt,
  });

  /// 从 tag 解析版本号（如 "v1.0.5" → "1.0.5"）
  String get versionString =>
      tagName.replaceFirst(RegExp(r'^v'), '').trim();
}

/// 更新检查结果
class UpdateCheckResult {
  final bool hasUpdate;
  final String currentVersion;
  final ReleaseInfo? release;

  const UpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    this.release,
  });
}

/// 更新检查服务
class UpdateCheckerService {
  static const String owner = 'caogenfunan123';
  static const String repo = 'hexo';

  final String currentVersion;
  final http.Client _client;

  UpdateCheckerService({required this.currentVersion, http.Client? client})
      : _client = client ?? http.Client();

  /// 检查是否有新版本
  Future<UpdateCheckResult> check({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final res = await _client
          .get(
            Uri.parse(
              'https://api.github.com/repos/$owner/$repo/releases/latest',
            ),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'tuomo-app',
            },
          )
          .timeout(timeout);
      if (res.statusCode != 200) {
        return UpdateCheckResult(hasUpdate: false, currentVersion: currentVersion);
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final release = ReleaseInfo(
        tagName: j['tag_name']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        htmlUrl: j['html_url']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        publishedAt: DateTime.tryParse(j['published_at']?.toString() ?? ''),
      );
      if (release.tagName.isEmpty) {
        return UpdateCheckResult(hasUpdate: false, currentVersion: currentVersion);
      }
      final hasUpdate = _compareVersions(currentVersion, release.versionString) < 0;
      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        release: hasUpdate ? release : null,
      );
    } catch (_) {
      return UpdateCheckResult(hasUpdate: false, currentVersion: currentVersion);
    }
  }

  /// 比较两个版本号：a < b 返回负，a == b 返回 0，a > b 返回正
  static int _compareVersions(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    for (int i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
    }
    return 0;
  }

  static List<int> _parse(String v) {
    final parts = v.split('.');
    final nums = <int>[];
    for (int i = 0; i < 3; i++) {
      nums.add(i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
    }
    return nums;
  }

  void dispose() {
    _client.close();
  }
}
