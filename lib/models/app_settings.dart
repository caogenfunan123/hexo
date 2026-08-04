import 'ai_profile.dart';
import 'ai_settings.dart';
import 'blog_site_config.dart';
import 'github_settings.dart';
import 'github_token_profile.dart';
import 'proxy_settings.dart';
import 'sync_settings.dart';
import 'ui_settings.dart';

/// 应用全局设置（重构版 V2）
///
/// 拆分为 5 个子配置，每个负责独立领域：
/// - GitHubSettings：GitHub 令牌、图床、图片压缩
/// - AiSettings：AI 模型、API、Profile
/// - ProxySettings：网络代理
/// - SyncSettings：自动保存、备份、WebDAV、离线模式
/// - UiSettings：主题、护眼、站点信息、状态预设
///
/// 保留原 AppSettings 完整兼容层，所有旧字段通过 getter 代理到子配置
class AppSettings {
  // ── 子配置 ──
  final GitHubSettings github;
  final AiSettings ai;
  final ProxySettings proxy;
  final SyncSettings sync;
  final UiSettings ui;

  // ── 动态 CMS 站点配置（不拆分，独立领域） ──
  final List<BlogSiteConfig> blogSiteConfigs;
  final String activeSiteId;
  final String activeRepoId;

  const AppSettings({
    this.github = const GitHubSettings(),
    this.ai = const AiSettings(),
    this.proxy = const ProxySettings(),
    this.sync = const SyncSettings(),
    this.ui = const UiSettings(),
    this.blogSiteConfigs = const [],
    this.activeSiteId = '',
    this.activeRepoId = '',
  });

  // ============================================================
  // 兼容层 — 旧字段通过 getter 代理到子配置
  // ============================================================

  // ── GitHubSettings 代理 ──
  String get defaultToken => github.defaultToken;
  List<GithubTokenProfile> get githubTokens => github.githubTokens;
  String get activeGithubTokenId => github.activeGithubTokenId;
  String get imageBedType => github.imageBedType;
  String get imageBedToken => github.imageBedToken;
  String get imageBedOwner => github.imageBedOwner;
  String get imageBedRepo => github.imageBedRepo;
  String get imageBedBranch => github.imageBedBranch;
  String get imageBedPath => github.imageBedPath;
  String get imageBedCdn => github.imageBedCdn;
  bool get autoCompressImage => github.autoCompressImage;
  int get compressQuality => github.compressQuality;
  int get compressMaxWidth => github.compressMaxWidth;

  GithubTokenProfile? get activeGithubToken => github.activeGithubToken;
  String get effectiveGithubToken => github.effectiveGithubToken;

  // ── AiSettings 代理 ──
  String get aiProvider => ai.aiProvider;
  String get aiApiKey => ai.aiApiKey;
  String get aiBaseUrl => ai.aiBaseUrl;
  String get aiModel => ai.aiModel;
  List<AiProfile> get aiProfiles => ai.aiProfiles;
  String get activeAiProfileId => ai.activeAiProfileId;
  String get defaultModelId => ai.defaultModelId;
  String get defaultModelBase => ai.defaultModelBase;

  AiProfile? get activeAiProfile => ai.activeAiProfile;
  String get effectiveAiBaseUrl => ai.effectiveAiBaseUrl;
  String get effectiveAiApiKey => ai.effectiveAiApiKey;
  String get effectiveAiModel => ai.effectiveAiModel;

  // ── ProxySettings 代理 ──
  bool get proxyEnabled => proxy.proxyEnabled;
  String get proxyHost => proxy.proxyHost;
  int get proxyPort => proxy.proxyPort;
  String get proxyUsername => proxy.proxyUsername;
  String get proxyPassword => proxy.proxyPassword;
  bool get proxyApplyToAi => proxy.proxyApplyToAi;

  // ── SyncSettings 代理 ──
  bool get autoSaveEnabled => sync.autoSaveEnabled;
  int get autoSaveIntervalSeconds => sync.autoSaveIntervalSeconds;
  String get autoSaveDir => sync.autoSaveDir;
  String get backupDir => sync.backupDir;
  String get webdavUrl => sync.webdavUrl;
  String get webdavUsername => sync.webdavUsername;
  String get webdavPassword => sync.webdavPassword;
  String get webdavFolder => sync.webdavFolder;
  bool get webdavAutoSyncEnabled => sync.webdavAutoSyncEnabled;
  int get webdavAutoSyncIntervalSeconds => sync.webdavAutoSyncIntervalSeconds;
  bool get webdavSyncWifiOnly => sync.webdavSyncWifiOnly;
  bool get restoreSession => sync.restoreSession;
  bool get offlineMode => sync.offlineMode;

  // ── UiSettings 代理 ──
  String get siteAvatar => ui.siteAvatar;
  String get siteName => ui.siteName;
  String get siteBio => ui.siteBio;
  String get siteHome => ui.siteHome;
  String get siteAbout => ui.siteAbout;
  String get siteGuestbook => ui.siteGuestbook;
  String get siteNow => ui.siteNow;
  String get siteWorks => ui.siteWorks;
  int get themeColor => ui.themeColor;
  bool get nightEyeProtection => ui.nightEyeProtection;
  double get nightEyeIntensity => ui.nightEyeIntensity;
  int get httpTimeoutSeconds => ui.httpTimeoutSeconds;
  bool get allowInsecureHttps => ui.allowInsecureHttps;
  List<String> get statusPresets => ui.statusPresets;
  String get cloudflareDeployHook => ui.cloudflareDeployHook;

  // ============================================================
  // 活跃站点
  // ============================================================

  String get effectiveActiveSiteId {
    if (activeSiteId.isNotEmpty) return activeSiteId;
    if (activeRepoId.isNotEmpty) return activeRepoId;
    if (blogSiteConfigs.isNotEmpty) return blogSiteConfigs.first.id;
    return '';
  }

  BlogSiteConfig? get activeBlogSiteConfig {
    final siteId = effectiveActiveSiteId;
    if (siteId.isEmpty) return null;
    for (final config in blogSiteConfigs) {
      if (config.id == siteId) return config;
    }
    return null;
  }

  // ============================================================
  // copyWith — 同时支持子对象和扁平参数（向后兼容）
  // ============================================================

  AppSettings copyWith({
    // ── 子对象（推荐） ──
    GitHubSettings? github,
    AiSettings? ai,
    ProxySettings? proxy,
    SyncSettings? sync,
    UiSettings? ui,
    List<BlogSiteConfig>? blogSiteConfigs,
    String? activeSiteId,
    String? activeRepoId,
    // ── 扁平参数（向后兼容旧代码） ──
    // GitHubSettings
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
    // AiSettings
    String? aiProvider,
    String? aiApiKey,
    String? aiBaseUrl,
    String? aiModel,
    List<AiProfile>? aiProfiles,
    String? activeAiProfileId,
    String? defaultModelId,
    String? defaultModelBase,
    // ProxySettings
    bool? proxyEnabled,
    String? proxyHost,
    int? proxyPort,
    String? proxyUsername,
    String? proxyPassword,
    bool? proxyApplyToAi,
    // SyncSettings
    bool? autoSaveEnabled,
    int? autoSaveIntervalSeconds,
    String? autoSaveDir,
    String? backupDir,
    String? webdavUrl,
    String? webdavUsername,
    String? webdavPassword,
    String? webdavFolder,
    bool? webdavAutoSyncEnabled,
    int? webdavAutoSyncIntervalSeconds,
    bool? webdavSyncWifiOnly,
    bool? restoreSession,
    bool? offlineMode,
    // UiSettings
    String? siteAvatar,
    String? siteName,
    String? siteBio,
    String? siteHome,
    String? siteAbout,
    String? siteGuestbook,
    String? siteNow,
    String? siteWorks,
    int? themeColor,
    bool? nightEyeProtection,
    double? nightEyeIntensity,
    int? httpTimeoutSeconds,
    bool? allowInsecureHttps,
    List<String>? statusPresets,
    String? cloudflareDeployHook,
  }) {
    // 如果有扁平参数传入，构建对应的子对象
    final bool hasGitHubFlat = githubTokens != null || activeGithubTokenId != null ||
        defaultToken != null || imageBedOwner != null || imageBedRepo != null ||
        imageBedToken != null || imageBedBranch != null || imageBedPath != null ||
        imageBedCdn != null || imageBedType != null || autoCompressImage != null ||
        compressQuality != null || compressMaxWidth != null;
    final bool hasAiFlat = aiProfiles != null || activeAiProfileId != null ||
        defaultModelId != null || defaultModelBase != null ||
        aiProvider != null || aiApiKey != null || aiBaseUrl != null || aiModel != null;
    final bool hasProxyFlat = proxyEnabled != null || proxyHost != null ||
        proxyPort != null || proxyUsername != null || proxyPassword != null ||
        proxyApplyToAi != null;
    final bool hasSyncFlat = autoSaveEnabled != null ||
        autoSaveIntervalSeconds != null || autoSaveDir != null ||
        backupDir != null || webdavUrl != null || webdavUsername != null ||
        webdavPassword != null || webdavFolder != null ||
        webdavAutoSyncEnabled != null || webdavAutoSyncIntervalSeconds != null ||
        webdavSyncWifiOnly != null || restoreSession != null || offlineMode != null;
    final bool hasUiFlat = siteName != null || siteBio != null ||
        siteAvatar != null || siteHome != null || siteAbout != null ||
        siteGuestbook != null || siteNow != null || siteWorks != null ||
        themeColor != null || nightEyeProtection != null ||
        nightEyeIntensity != null || httpTimeoutSeconds != null ||
        allowInsecureHttps != null || statusPresets != null ||
        cloudflareDeployHook != null;

    final GitHubSettings effectiveGitHub = github ??
        (hasGitHubFlat
            ? this.github.copyWith(
                defaultToken: defaultToken,
                githubTokens: githubTokens,
                activeGithubTokenId: activeGithubTokenId,
                imageBedType: imageBedType,
                imageBedToken: imageBedToken,
                imageBedOwner: imageBedOwner,
                imageBedRepo: imageBedRepo,
                imageBedBranch: imageBedBranch,
                imageBedPath: imageBedPath,
                imageBedCdn: imageBedCdn,
                autoCompressImage: autoCompressImage,
                compressQuality: compressQuality,
                compressMaxWidth: compressMaxWidth,
              )
            : this.github);
    final AiSettings effectiveAi = ai ??
        (hasAiFlat
            ? this.ai.copyWith(
                aiProvider: aiProvider,
                aiApiKey: aiApiKey,
                aiBaseUrl: aiBaseUrl,
                aiModel: aiModel,
                aiProfiles: aiProfiles,
                activeAiProfileId: activeAiProfileId,
                defaultModelId: defaultModelId,
                defaultModelBase: defaultModelBase,
              )
            : this.ai);
    final ProxySettings effectiveProxy = proxy ??
        (hasProxyFlat
            ? this.proxy.copyWith(
                proxyEnabled: proxyEnabled,
                proxyHost: proxyHost,
                proxyPort: proxyPort,
                proxyUsername: proxyUsername,
                proxyPassword: proxyPassword,
                proxyApplyToAi: proxyApplyToAi,
              )
            : this.proxy);
    final SyncSettings effectiveSync = sync ??
        (hasSyncFlat
            ? this.sync.copyWith(
                autoSaveEnabled: autoSaveEnabled,
                autoSaveIntervalSeconds: autoSaveIntervalSeconds,
                autoSaveDir: autoSaveDir,
                backupDir: backupDir,
                webdavUrl: webdavUrl,
                webdavUsername: webdavUsername,
                webdavPassword: webdavPassword,
                webdavFolder: webdavFolder,
                webdavAutoSyncEnabled: webdavAutoSyncEnabled,
                webdavAutoSyncIntervalSeconds: webdavAutoSyncIntervalSeconds,
                webdavSyncWifiOnly: webdavSyncWifiOnly,
                restoreSession: restoreSession,
                offlineMode: offlineMode,
              )
            : this.sync);
    final UiSettings effectiveUi = ui ??
        (hasUiFlat
            ? this.ui.copyWith(
                siteAvatar: siteAvatar,
                siteName: siteName,
                siteBio: siteBio,
                siteHome: siteHome,
                siteAbout: siteAbout,
                siteGuestbook: siteGuestbook,
                siteNow: siteNow,
                siteWorks: siteWorks,
                themeColor: themeColor,
                nightEyeProtection: nightEyeProtection,
                nightEyeIntensity: nightEyeIntensity,
                httpTimeoutSeconds: httpTimeoutSeconds,
                allowInsecureHttps: allowInsecureHttps,
                statusPresets: statusPresets,
                cloudflareDeployHook: cloudflareDeployHook,
              )
            : this.ui);

    return AppSettings(
      github: effectiveGitHub,
      ai: effectiveAi,
      proxy: effectiveProxy,
      sync: effectiveSync,
      ui: effectiveUi,
      blogSiteConfigs: blogSiteConfigs ?? this.blogSiteConfigs,
      activeSiteId: activeSiteId ?? this.activeSiteId,
      activeRepoId: activeRepoId ?? this.activeRepoId,
    );
  }

  // ============================================================
  // 序列化
  // ============================================================

  Map<String, dynamic> toJson() => {
        ...github.toJson(),
        ...ai.toJson(),
        ...proxy.toJson(),
        ...sync.toJson(),
        ...ui.toJson(),
        'blogSiteConfigs': blogSiteConfigs.map((e) => e.toJson()).toList(),
        'activeSiteId': activeSiteId,
        'activeRepoId': activeRepoId,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    return AppSettings(
      github: GitHubSettings.fromJson(j),
      ai: AiSettings.fromJson(j),
      proxy: ProxySettings.fromJson(j),
      sync: SyncSettings.fromJson(j),
      ui: UiSettings.fromJson(j),
      blogSiteConfigs: _parseBlogSiteConfigs(j['blogSiteConfigs']),
      activeSiteId: j['activeSiteId']?.toString() ?? '',
      activeRepoId: j['activeRepoId']?.toString() ?? '',
    );
  }

  static List<BlogSiteConfig> _parseBlogSiteConfigs(dynamic raw) {
    if (raw is! List) return [];
    final configs = <BlogSiteConfig>[];
    for (final e in raw) {
      if (e is Map) {
        try {
          configs.add(BlogSiteConfig.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
    }
    return configs;
  }
}