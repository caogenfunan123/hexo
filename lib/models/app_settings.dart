import 'ai_profile.dart';
import 'blog_site_config.dart';
import 'github_token_profile.dart';

class AppSettings {
  final String defaultToken;
  final List<GithubTokenProfile> githubTokens;
  final String activeGithubTokenId;
  final String imageBedType;
  final String imageBedToken;
  final String imageBedOwner;
  final String imageBedRepo;
  final String imageBedBranch;
  final String imageBedPath;
  final String imageBedCdn;
  final String aiProvider;
  final String aiApiKey;
  final String aiBaseUrl;
  final String aiModel;
  final List<AiProfile> aiProfiles;
  final String activeAiProfileId;
  final bool autoCompressImage;
  final int compressQuality;
  final int compressMaxWidth;
  final String activeRepoId;

  // ── 动态 CMS 站点配置 ──
  final List<BlogSiteConfig> blogSiteConfigs;
  /// 当前活跃站点 ID（统一标识，可以是 RepoConfig.id 或 BlogSiteConfig.id）
  /// 为空时回退到 activeRepoId 或第一个可用站点
  final String activeSiteId;

  final String webdavUrl;
  final String webdavUsername;
  final String webdavPassword;
  final String webdavFolder;
  final String siteAvatar;
  final String siteName;
  final String siteBio;
  final String siteHome;
  final String siteAbout;
  final String siteGuestbook;
  final String siteNow;
  final String siteWorks;
  final String cloudflareDeployHook;
  final int themeColor;

  // ── 草稿自动保存 ──
  final bool autoSaveEnabled;
  final int autoSaveIntervalSeconds;
  final String autoSaveDir;

  // ── 备份目录 ──
  final String backupDir;

  // ── 网盘自动同步 ──
  final bool webdavAutoSyncEnabled;
  final int webdavAutoSyncIntervalSeconds;
  final bool webdavSyncWifiOnly;

  // ── 全局默认 AI 模型 ──
  final String defaultModelId;   // modelId
  final String defaultModelBase; // apiBase

  // ── 会话恢复 ──
  final bool restoreSession;

  // ── 网络超时 ──
  final int httpTimeoutSeconds;
  final bool allowInsecureHttps;

  // ── 发布状态预设 ──
  final List<String> statusPresets;

  const AppSettings({
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
    this.aiProvider = 'openai',
    this.aiApiKey = '',
    this.aiBaseUrl = 'https://api.openai.com/v1',
    this.aiModel = 'gpt-4o-mini',
    this.aiProfiles = const [],
    this.activeAiProfileId = '',
    this.autoCompressImage = true,
    this.compressQuality = 80,
    this.compressMaxWidth = 1600,
    this.activeRepoId = '',
    this.blogSiteConfigs = const [],
    this.activeSiteId = '',
    this.webdavUrl = '',
    this.webdavUsername = '',
    this.webdavPassword = '',
    this.webdavFolder = 'hexo-backup',
    this.siteAvatar = '',
    this.siteName = '小子的博客',
    this.siteBio = '分享技术、生活和思考',
    this.siteHome = '',
    this.siteAbout = '',
    this.siteGuestbook = '',
    this.siteNow = '',
    this.siteWorks = '',
    this.cloudflareDeployHook = '',
    this.themeColor = 0xFF0EA5E9,
    this.autoSaveEnabled = true,
    this.autoSaveIntervalSeconds = 30,
    this.autoSaveDir = '',
    this.backupDir = '',
    this.webdavAutoSyncEnabled = false,
    this.webdavAutoSyncIntervalSeconds = 300,
    this.webdavSyncWifiOnly = true,
    this.defaultModelId = '',
    this.defaultModelBase = '',
    this.restoreSession = true,
    this.httpTimeoutSeconds = 30,
    this.allowInsecureHttps = false,
    this.statusPresets = const ['publish', 'draft', 'pending', 'private'],
  });

  GithubTokenProfile? get activeGithubToken {
    if (githubTokens.isEmpty) return null;
    for (final t in githubTokens) {
      if (t.id == activeGithubTokenId) return t;
    }
    return githubTokens.first;
  }

  /// 优先当前已保存令牌，其次旧版 defaultToken 字段。
  String get effectiveGithubToken {
    final active = activeGithubToken;
    if (active != null && active.token.isNotEmpty) return active.token;
    if (defaultToken.isNotEmpty) return defaultToken;
    for (final t in githubTokens) {
      if (t.token.isNotEmpty) return t.token;
    }
    return '';
  }

  AiProfile? get activeAiProfile {
    if (aiProfiles.isEmpty) return null;
    for (final p in aiProfiles) {
      if (p.id == activeAiProfileId) return p;
    }
    return aiProfiles.first;
  }

  /// 兼容旧字段：优先使用多配置里的当前模型
  String get effectiveAiBaseUrl =>
      activeAiProfile?.baseUrl.isNotEmpty == true
          ? activeAiProfile!.baseUrl
          : aiBaseUrl;

  String get effectiveAiApiKey =>
      activeAiProfile?.apiKey.isNotEmpty == true
          ? activeAiProfile!.apiKey
          : aiApiKey;

  String get effectiveAiModel =>
      activeAiProfile?.model.isNotEmpty == true
          ? activeAiProfile!.model
          : aiModel;

  /// 获取当前活跃站点 ID（统一标识）
  /// 优先使用 activeSiteId，为空时回退到 activeRepoId
  String get effectiveActiveSiteId {
    if (activeSiteId.isNotEmpty) return activeSiteId;
    if (activeRepoId.isNotEmpty) return activeRepoId;
    // 都没有时，取第一个动态站点
    if (blogSiteConfigs.isNotEmpty) return blogSiteConfigs.first.id;
    return '';
  }

  /// 获取当前活跃的动态 CMS 站点配置
  BlogSiteConfig? get activeBlogSiteConfig {
    final siteId = effectiveActiveSiteId;
    if (siteId.isEmpty) return null;
    for (final config in blogSiteConfigs) {
      if (config.id == siteId) return config;
    }
    return null;
  }

  AppSettings copyWith({
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
    String? aiProvider,
    String? aiApiKey,
    String? aiBaseUrl,
    String? aiModel,
    List<AiProfile>? aiProfiles,
    String? activeAiProfileId,
    bool? autoCompressImage,
    int? compressQuality,
    int? compressMaxWidth,
    String? activeRepoId,
    List<BlogSiteConfig>? blogSiteConfigs,
    String? activeSiteId,
    String? webdavUrl,
    String? webdavUsername,
    String? webdavPassword,
    String? webdavFolder,
    String? siteAvatar,
    String? siteName,
    String? siteBio,
    String? siteHome,
    String? siteAbout,
    String? siteGuestbook,
    String? siteNow,
    String? siteWorks,
    String? cloudflareDeployHook,
    int? themeColor,
    bool? autoSaveEnabled,
    int? autoSaveIntervalSeconds,
    String? autoSaveDir,
    String? backupDir,
    bool? webdavAutoSyncEnabled,
    int? webdavAutoSyncIntervalSeconds,
    bool? webdavSyncWifiOnly,
    String? defaultModelId,
    String? defaultModelBase,
    bool? restoreSession,
    int? httpTimeoutSeconds,
    bool? allowInsecureHttps,
    List<String>? statusPresets,
  }) {
    return AppSettings(
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
      aiProvider: aiProvider ?? this.aiProvider,
      aiApiKey: aiApiKey ?? this.aiApiKey,
      aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
      aiModel: aiModel ?? this.aiModel,
      aiProfiles: aiProfiles ?? this.aiProfiles,
      activeAiProfileId: activeAiProfileId ?? this.activeAiProfileId,
      autoCompressImage: autoCompressImage ?? this.autoCompressImage,
      compressQuality: compressQuality ?? this.compressQuality,
      compressMaxWidth: compressMaxWidth ?? this.compressMaxWidth,
      activeRepoId: activeRepoId ?? this.activeRepoId,
      blogSiteConfigs: blogSiteConfigs ?? this.blogSiteConfigs,
      activeSiteId: activeSiteId ?? this.activeSiteId,
      webdavUrl: webdavUrl ?? this.webdavUrl,
      webdavUsername: webdavUsername ?? this.webdavUsername,
      webdavPassword: webdavPassword ?? this.webdavPassword,
      webdavFolder: webdavFolder ?? this.webdavFolder,
      siteAvatar: siteAvatar ?? this.siteAvatar,
      siteName: siteName ?? this.siteName,
      siteBio: siteBio ?? this.siteBio,
      siteHome: siteHome ?? this.siteHome,
      siteAbout: siteAbout ?? this.siteAbout,
      siteGuestbook: siteGuestbook ?? this.siteGuestbook,
      siteNow: siteNow ?? this.siteNow,
      siteWorks: siteWorks ?? this.siteWorks,
      cloudflareDeployHook: cloudflareDeployHook ?? this.cloudflareDeployHook,
      themeColor: themeColor ?? this.themeColor,
      autoSaveEnabled: autoSaveEnabled ?? this.autoSaveEnabled,
      autoSaveIntervalSeconds: autoSaveIntervalSeconds ?? this.autoSaveIntervalSeconds,
      autoSaveDir: autoSaveDir ?? this.autoSaveDir,
      backupDir: backupDir ?? this.backupDir,
      webdavAutoSyncEnabled: webdavAutoSyncEnabled ?? this.webdavAutoSyncEnabled,
      webdavAutoSyncIntervalSeconds: webdavAutoSyncIntervalSeconds ?? this.webdavAutoSyncIntervalSeconds,
      webdavSyncWifiOnly: webdavSyncWifiOnly ?? this.webdavSyncWifiOnly,
      defaultModelId: defaultModelId ?? this.defaultModelId,
      defaultModelBase: defaultModelBase ?? this.defaultModelBase,
      restoreSession: restoreSession ?? this.restoreSession,
      httpTimeoutSeconds: httpTimeoutSeconds ?? this.httpTimeoutSeconds,
      allowInsecureHttps: allowInsecureHttps ?? this.allowInsecureHttps,
      statusPresets: statusPresets ?? this.statusPresets,
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
        'aiProvider': aiProvider,
        'aiApiKey': aiApiKey,
        'aiBaseUrl': aiBaseUrl,
        'aiModel': aiModel,
        'aiProfiles': aiProfiles.map((e) => e.toJson()).toList(),
        'activeAiProfileId': activeAiProfileId,
        'autoCompressImage': autoCompressImage,
        'compressQuality': compressQuality,
        'compressMaxWidth': compressMaxWidth,
        'activeRepoId': activeRepoId,
        'blogSiteConfigs': blogSiteConfigs.map((e) => e.toJson()).toList(),
        'activeSiteId': activeSiteId,
        'webdavUrl': webdavUrl,
        'webdavUsername': webdavUsername,
        'webdavPassword': webdavPassword,
        'webdavFolder': webdavFolder,
        'siteAvatar': siteAvatar,
        'siteName': siteName,
        'siteBio': siteBio,
        'siteHome': siteHome,
        'siteAbout': siteAbout,
        'siteGuestbook': siteGuestbook,
        'siteNow': siteNow,
        'siteWorks': siteWorks,
        'cloudflareDeployHook': cloudflareDeployHook,
        'themeColor': themeColor,
        'autoSaveEnabled': autoSaveEnabled,
        'autoSaveIntervalSeconds': autoSaveIntervalSeconds,
        'autoSaveDir': autoSaveDir,
        'backupDir': backupDir,
        'webdavAutoSyncEnabled': webdavAutoSyncEnabled,
        'webdavAutoSyncIntervalSeconds': webdavAutoSyncIntervalSeconds,
        'webdavSyncWifiOnly': webdavSyncWifiOnly,
        'defaultModelId': defaultModelId,
        'defaultModelBase': defaultModelBase,
        'restoreSession': restoreSession,
        'httpTimeoutSeconds': httpTimeoutSeconds,
        'allowInsecureHttps': allowInsecureHttps,
        'statusPresets': statusPresets,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    final profilesRaw = j['aiProfiles'];
    final profiles = <AiProfile>[];
    if (profilesRaw is List) {
      for (final e in profilesRaw) {
        if (e is Map) {
          profiles.add(AiProfile.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    // 兼容旧版单配置：自动迁移成一个 profile
    final legacyKey = j['aiApiKey']?.toString() ?? '';
    final legacyUrl = j['aiBaseUrl']?.toString() ?? 'https://api.openai.com/v1';
    final legacyModel = j['aiModel']?.toString() ?? 'gpt-4o-mini';
    if (profiles.isEmpty && (legacyKey.isNotEmpty || legacyUrl.isNotEmpty)) {
      profiles.add(
        AiProfile(
          id: 'legacy',
          name: j['aiProvider']?.toString().isNotEmpty == true
              ? j['aiProvider'].toString()
              : '默认中转站',
          baseUrl: legacyUrl,
          apiKey: legacyKey,
          model: legacyModel,
        ),
      );
    }

    final activeId = j['activeAiProfileId']?.toString() ??
        (profiles.isNotEmpty ? profiles.first.id : '');

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
      tokens.add(
        GithubTokenProfile(
          id: 'legacy_token',
          name: '默认 Token',
          token: legacyToken,
        ),
      );
    }

    // 去重：同 token 只保留一份
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
        if (t.id == activeTokenId) {
          active = t;
          break;
        }
      }
      resolvedDefault = (active ?? dedup.first).token;
    }

    return AppSettings(
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
      aiProvider: j['aiProvider']?.toString() ?? 'openai',
      aiApiKey: legacyKey,
      aiBaseUrl: legacyUrl,
      aiModel: legacyModel,
      aiProfiles: profiles,
      activeAiProfileId: activeId,
      autoCompressImage: j['autoCompressImage'] != false,
      compressQuality: (j['compressQuality'] as num?)?.toInt() ?? 80,
      compressMaxWidth: (j['compressMaxWidth'] as num?)?.toInt() ?? 1600,
      activeRepoId: j['activeRepoId']?.toString() ?? '',
      blogSiteConfigs: _parseBlogSiteConfigs(j['blogSiteConfigs']),
      activeSiteId: j['activeSiteId']?.toString() ?? '',
      webdavUrl: j['webdavUrl']?.toString() ?? '',
      webdavUsername: j['webdavUsername']?.toString() ?? '',
      webdavPassword: j['webdavPassword']?.toString() ?? '',
      webdavFolder: j['webdavFolder']?.toString() ?? 'hexo-backup',
      siteAvatar: j['siteAvatar']?.toString() ?? '',
      siteName: j['siteName']?.toString() ?? '小子的博客',
      siteBio: j['siteBio']?.toString() ?? '分享技术、生活和思考',
      siteHome: j['siteHome']?.toString() ?? '',
      siteAbout: j['siteAbout']?.toString() ?? '',
      siteGuestbook: j['siteGuestbook']?.toString() ?? '',
      siteNow: j['siteNow']?.toString() ?? '',
      siteWorks: j['siteWorks']?.toString() ?? '',
      cloudflareDeployHook: j['cloudflareDeployHook']?.toString() ?? '',
      themeColor: (j['themeColor'] as num?)?.toInt() ?? 0xFF0EA5E9,
      autoSaveEnabled: j['autoSaveEnabled'] != false,
      autoSaveIntervalSeconds: (j['autoSaveIntervalSeconds'] as num?)?.toInt() ?? 30,
      autoSaveDir: j['autoSaveDir']?.toString() ?? '',
      backupDir: j['backupDir']?.toString() ?? '',
      webdavAutoSyncEnabled: j['webdavAutoSyncEnabled'] == true,
      webdavAutoSyncIntervalSeconds: (j['webdavAutoSyncIntervalSeconds'] as num?)?.toInt() ?? 300,
      webdavSyncWifiOnly: j['webdavSyncWifiOnly'] != false,
      defaultModelId: j['defaultModelId']?.toString() ?? '',
      defaultModelBase: j['defaultModelBase']?.toString() ?? '',
      restoreSession: j['restoreSession'] != false,
      httpTimeoutSeconds: (j['httpTimeoutSeconds'] as num?)?.toInt() ?? 30,
      allowInsecureHttps: j['allowInsecureHttps'] == true,
      statusPresets: _parseStringList(j['statusPresets'], const ['publish', 'draft', 'pending', 'private']),
    );
  }

  /// 解析动态 CMS 站点配置列表
  static List<BlogSiteConfig> _parseBlogSiteConfigs(dynamic raw) {
    if (raw is! List) return [];
    final configs = <BlogSiteConfig>[];
    for (final e in raw) {
      if (e is Map) {
        try {
          configs.add(BlogSiteConfig.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {
          // 忽略无法解析的配置
        }
      }
    }
    return configs;
  }

  /// 解析字符串列表
  static List<String> _parseStringList(dynamic raw, List<String> fallback) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return fallback;
  }
}
