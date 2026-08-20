/// 自动更新检查服务：读取仓库根目录的 release.json 版本清单
///
/// 方案 B：发布时更新 release.json（版本号、各平台下载 URL、SHA256、更新日志）
/// 并 push 到仓库，客户端通过 raw 直链读取，无需自建服务器，也无 API 限流。
///
///   GET https://raw.githubusercontent.com/{owner}/{repo}/main/release.json
///
/// 对比当前版本（pubspec version），存在新版本时返回更新信息。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// 单个平台的下载产物
class PlatformArtifact {
  final String url;
  final String? sha256;
  final int? size;
  final Map<String, PlatformArtifact>? abi;

  const PlatformArtifact({required this.url, this.sha256, this.size, this.abi});

  factory PlatformArtifact.fromJson(Map<String, dynamic> j) {
    Map<String, PlatformArtifact>? abiMap;
    if (j['abi'] is Map) {
      abiMap = {};
      (j['abi'] as Map).forEach((k, v) {
        if (v is Map) {
          abiMap![k.toString()] =
              PlatformArtifact.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }
    return PlatformArtifact(
      url: j['url']?.toString() ?? '',
      sha256: j['sha256']?.toString(),
      size: (j['size'] as num?)?.toInt(),
      abi: abiMap,
    );
  }
}

/// 更新信息
class ReleaseInfo {
  final String version;
  final int? build;
  final String name;
  final String notes;
  final DateTime? publishedAt;
  final Map<String, PlatformArtifact> platforms;

  const ReleaseInfo({
    required this.version,
    this.build,
    this.name = '',
    this.notes = '',
    this.publishedAt,
    this.platforms = const {},
  });

  /// 当前平台对应的下载产物（android / linux / windows / web）
  PlatformArtifact? artifactFor(String platformKey) => platforms[platformKey];

  /// Android 平台按设备 ABI 匹配的下载产物
  ///
  /// [deviceAbi] 为 `Build.SUPPORTED_ABIS[0]` 的值（如 `arm64-v8a`）。
  /// 优先匹配 ABI 子项，无匹配时回退到 universal 或顶层 artifact。
  PlatformArtifact? androidArtifact(String deviceAbi) {
    final android = platforms['android'];
    if (android == null || android.abi == null || android.abi!.isEmpty) {
      return android;
    }
    final key = _mapAbiToKey(deviceAbi);
    return android.abi![key] ?? android.abi!['universal'] ?? android;
  }

  /// 将设备 ABI 字符串映射到 release.json 中的键名
  static String _mapAbiToKey(String abi) {
    if (abi.startsWith('arm64')) return 'arm64';
    if (abi.startsWith('armeabi')) return 'armv7';
    // x86 / x86_64 / mips -> universal 兜底
    return 'universal';
  }

  /// 兜底：第一个可用平台产物
  PlatformArtifact? get firstArtifact =>
      platforms.isEmpty ? null : platforms.values.first;
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

/// 更新检查服务（方案 B：release.json 清单）
class UpdateCheckerService {
  static const String owner = 'caogenfunan123';
  static const String repo = 'hexo';
  static const String manifestUrl =
      'https://raw.githubusercontent.com/$owner/$repo/main/release.json';

  final String currentVersion;
  final http.Client _client;

  UpdateCheckerService({required this.currentVersion, http.Client? client})
      : _client = client ?? http.Client();

  /// 检查是否有新版本
  Future<UpdateCheckResult> check(
      {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final res = await _client
          .get(Uri.parse(manifestUrl), headers: const {
            'User-Agent': 'tuomo-app',
          })
          .timeout(timeout);
      if (res.statusCode != 200) {
        return UpdateCheckResult(
            hasUpdate: false, currentVersion: currentVersion);
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final version = j['version']?.toString() ?? '';
      if (version.isEmpty) {
        return UpdateCheckResult(
            hasUpdate: false, currentVersion: currentVersion);
      }
      final platforms = <String, PlatformArtifact>{};
      final p = j['platforms'];
      if (p is Map) {
        p.forEach((key, value) {
          if (value is Map) {
            platforms[key.toString()] =
                PlatformArtifact.fromJson(Map<String, dynamic>.from(value));
          }
        });
      }
      final release = ReleaseInfo(
        version: version,
        build: (j['build'] as num?)?.toInt(),
        name: j['name']?.toString() ?? '',
        notes: j['notes']?.toString() ?? '',
        publishedAt: DateTime.tryParse(j['publishedAt']?.toString() ?? ''),
        platforms: platforms,
      );
      final hasUpdate = _compareVersions(currentVersion, release.version) < 0;
      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        release: hasUpdate ? release : null,
      );
    } catch (_) {
      return UpdateCheckResult(
          hasUpdate: false, currentVersion: currentVersion);
    }
  }

  /// 比较两个版本号：a < b 返回负，a == b 返回 0，a > b 返回正
  ///
  /// 支持 `X.Y.Z` 与 `X.Y.Z+N`（构建号）格式，构建号参与比较，
  /// 避免 `1.0.9+10` 与 `1.0.9+11` 被误判为同一版本。
  static int _compareVersions(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    for (int i = 0; i < pa.length; i++) {
      if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
    }
    return 0;
  }

  static List<int> _parse(String v) {
    final mainPart = v.split('+').first;
    final parts = mainPart.split('.');
    final nums = <int>[];
    for (int i = 0; i < 3; i++) {
      nums.add(i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
    }
    // 构建号：1.0.9+10 → 10；无构建号默认 0
    final build = int.tryParse(v.split('+').last) ?? 0;
    nums.add(build);
    return nums;
  }

  void dispose() {
    _client.close();
  }
}
