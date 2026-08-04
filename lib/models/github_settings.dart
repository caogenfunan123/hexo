/// GitHub 设置子配置
/// 从 AppSettings 拆分，独立管理 GitHub 令牌、图床等配置
library;

import 'github_token_profile.dart';

class GitHubSettings {
  final String defaultToken;
  final List<GithubTokenProfile> githubTokens;
  final String activeGithubTokenId;

  // 图床
  final String imageBedType;
  final String imageBedToken;
  final String imageBedOwner;
  final String imageBedRepo;
  final String imageBedBranch;
  final String imageBedPath;
  final String imageBedCdn;
  final bool autoCompressImage;
  final int compressQuality;
  final int compressMaxWidth;

  const GitHubSettings({
    this.defaultToken = '',
    this.githubTokens = const [],
    this.activeGithubTokenId = '',
    this.imageBedType = 'github',
    this.imageBedToken = '',
    this.imageBedOwner = '',
    this.imageBedRepo = '',
    this.imageBedBranch = 'main',
    this.imageBedPath = 'images',
    this.imageBedCdn = '',
    this.autoCompressImage = true,
    this.compressQuality = 80,
    this.compressMaxWidth = 1600,
  });

  GithubTokenProfile? get activeGithubToken {
    if (githubTokens.isEmpty) return null;
    for (final t in githubTokens) {
      if (t.id == activeGithubTokenId) return t;
    }
    return githubTokens.first;
  }

  String get effectiveGithubToken {
    final active = activeGithubToken;
    if (active != null && active.token.isNotEmpty) return active.token;
    if (defaultToken.isNotEmpty) return defaultToken;
    for (final t in githubTokens) {
      if (t.token.isNotEmpty) return t.token;
    }
    return '';
  }

  GitHubSettings copyWith({
    String? defaultToken,
    List<GithubTokenProfile>? githubTokens,
    String? activeGithubTokenId,
    String? imageBedType,
    String? imageBedToken,
    String? imageBedOwner,
    String? imageBedRepo,
    String? imageBedBranch,
    String? imageBedPath,
    String? imageBedCdn,
    bool? autoCompressImage,
    int? compressQuality,
    int? compressMaxWidth,
  }) {
    return GitHubSettings(
      defaultToken: defaultToken ?? this.defaultToken,
      githubTokens: githubTokens ?? this.githubTokens,
      activeGithubTokenId: activeGithubTokenId ?? this.activeGithubTokenId,
      imageBedType: imageBedType ?? this.imageBedType,
      imageBedToken: imageBedToken ?? this.imageBedToken,
      imageBedOwner: imageBedOwner ?? this.imageBedOwner,
      imageBedRepo: imageBedRepo ?? this.imageBedRepo,
      imageBedBranch: imageBedBranch ?? this.imageBedBranch,
      imageBedPath: imageBedPath ?? this.imageBedPath,
      imageBedCdn: imageBedCdn ?? this.imageBedCdn,
      autoCompressImage: autoCompressImage ?? this.autoCompressImage,
      compressQuality: compressQuality ?? this.compressQuality,
      compressMaxWidth: compressMaxWidth ?? this.compressMaxWidth,
    );
  }

  Map<String, dynamic> toJson() => {
        'defaultToken': defaultToken,
        'githubTokens': githubTokens.map((e) => e.toJson()).toList(),
        'activeGithubTokenId': activeGithubTokenId,
        'imageBedType': imageBedType,
        'imageBedToken': imageBedToken,
        'imageBedOwner': imageBedOwner,
        'imageBedRepo': imageBedRepo,
        'imageBedBranch': imageBedBranch,
        'imageBedPath': imageBedPath,
        'imageBedCdn': imageBedCdn,
        'autoCompressImage': autoCompressImage,
        'compressQuality': compressQuality,
        'compressMaxWidth': compressMaxWidth,
      };

  factory GitHubSettings.fromJson(Map<String, dynamic> j) {
    final tokensRaw = j['githubTokens'];
    final tokens = <GithubTokenProfile>[];
    if (tokensRaw is List) {
      for (final e in tokensRaw) {
        if (e is Map) {
          tokens.add(GithubTokenProfile.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final legacyToken = j['defaultToken']?.toString() ?? '';
    if (tokens.isEmpty && legacyToken.isNotEmpty) {
      tokens.add(GithubTokenProfile(
        id: 'legacy_token',
        name: '默认 Token',
        token: legacyToken,
      ));
    }
    final dedup = <GithubTokenProfile>[];
    final seen = <String>{};
    for (final t in tokens) {
      final key = t.token.trim();
      if (key.isEmpty) continue;
      if (seen.contains(key)) continue;
      seen.add(key);
      dedup.add(t);
    }
    final activeTokenId = j['activeGithubTokenId']?.toString() ??
        (dedup.isNotEmpty ? dedup.first.id : '');
    String resolvedDefault = legacyToken;
    if (dedup.isNotEmpty) {
      GithubTokenProfile? active;
      for (final t in dedup) {
        if (t.id == activeTokenId) { active = t; break; }
      }
      resolvedDefault = (active ?? dedup.first).token;
    }
    return GitHubSettings(
      defaultToken: resolvedDefault.isNotEmpty ? resolvedDefault : legacyToken,
      githubTokens: dedup,
      activeGithubTokenId: activeTokenId,
      imageBedType: j['imageBedType']?.toString() ?? 'github',
      imageBedToken: j['imageBedToken']?.toString() ?? '',
      imageBedOwner: j['imageBedOwner']?.toString() ?? '',
      imageBedRepo: j['imageBedRepo']?.toString() ?? '',
      imageBedBranch: j['imageBedBranch']?.toString() ?? 'main',
      imageBedPath: j['imageBedPath']?.toString() ?? 'images',
      imageBedCdn: j['imageBedCdn']?.toString() ?? '',
      autoCompressImage: j['autoCompressImage'] != false,
      compressQuality: (j['compressQuality'] as num?)?.toInt() ?? 80,
      compressMaxWidth: (j['compressMaxWidth'] as num?)?.toInt() ?? 1600,
    );
  }
}