/// 同步设置子配置
/// 从 AppSettings 拆分，独立管理自动保存、备份、WebDAV、同步配置
library;

class SyncSettings {
  // 草稿自动保存
  final bool autoSaveEnabled;
  final int autoSaveIntervalSeconds;
  final String autoSaveDir;

  // 备份
  final String backupDir;

  // WebDAV
  final String webdavUrl;
  final String webdavUsername;
  final String webdavPassword;
  final String webdavFolder;
  final bool webdavAutoSyncEnabled;
  final int webdavAutoSyncIntervalSeconds;
  final bool webdavSyncWifiOnly;

  // 会话恢复
  final bool restoreSession;

  // 离线模式
  final bool offlineMode;

  // ── 草稿云同步（独立于网站仓库） ──
  /// 是否启用草稿云同步，默认关闭
  final bool draftSyncEnabled;
  /// 同步仓库：owner
  final String syncRepoOwner;
  /// 同步仓库：repo 名称
  final String syncRepoName;
  /// 同步仓库：分支
  final String syncRepoBranch;
  /// 同步仓库：Token
  final String syncRepoToken;

  const SyncSettings({
    this.autoSaveEnabled = true,
    this.autoSaveIntervalSeconds = 30,
    this.autoSaveDir = '',
    this.backupDir = '',
    this.webdavUrl = '',
    this.webdavUsername = '',
    this.webdavPassword = '',
    this.webdavFolder = 'hexo-backup',
    this.webdavAutoSyncEnabled = false,
    this.webdavAutoSyncIntervalSeconds = 300,
    this.webdavSyncWifiOnly = true,
    this.restoreSession = true,
    this.offlineMode = false,
    this.draftSyncEnabled = false,
    this.syncRepoOwner = '',
    this.syncRepoName = '',
    this.syncRepoBranch = 'main',
    this.syncRepoToken = '',
  });

  SyncSettings copyWith({
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
    bool? draftSyncEnabled,
    String? syncRepoOwner,
    String? syncRepoName,
    String? syncRepoBranch,
    String? syncRepoToken,
  }) {
    return SyncSettings(
      autoSaveEnabled: autoSaveEnabled ?? this.autoSaveEnabled,
      autoSaveIntervalSeconds: autoSaveIntervalSeconds ?? this.autoSaveIntervalSeconds,
      autoSaveDir: autoSaveDir ?? this.autoSaveDir,
      backupDir: backupDir ?? this.backupDir,
      webdavUrl: webdavUrl ?? this.webdavUrl,
      webdavUsername: webdavUsername ?? this.webdavUsername,
      webdavPassword: webdavPassword ?? this.webdavPassword,
      webdavFolder: webdavFolder ?? this.webdavFolder,
      webdavAutoSyncEnabled: webdavAutoSyncEnabled ?? this.webdavAutoSyncEnabled,
      webdavAutoSyncIntervalSeconds: webdavAutoSyncIntervalSeconds ?? this.webdavAutoSyncIntervalSeconds,
      webdavSyncWifiOnly: webdavSyncWifiOnly ?? this.webdavSyncWifiOnly,
      restoreSession: restoreSession ?? this.restoreSession,
      offlineMode: offlineMode ?? this.offlineMode,
      draftSyncEnabled: draftSyncEnabled ?? this.draftSyncEnabled,
      syncRepoOwner: syncRepoOwner ?? this.syncRepoOwner,
      syncRepoName: syncRepoName ?? this.syncRepoName,
      syncRepoBranch: syncRepoBranch ?? this.syncRepoBranch,
      syncRepoToken: syncRepoToken ?? this.syncRepoToken,
    );
  }

  Map<String, dynamic> toJson() => {
        'autoSaveEnabled': autoSaveEnabled,
        'autoSaveIntervalSeconds': autoSaveIntervalSeconds,
        'autoSaveDir': autoSaveDir,
        'backupDir': backupDir,
        'webdavUrl': webdavUrl,
        'webdavUsername': webdavUsername,
        'webdavPassword': webdavPassword,
        'webdavFolder': webdavFolder,
        'webdavAutoSyncEnabled': webdavAutoSyncEnabled,
        'webdavAutoSyncIntervalSeconds': webdavAutoSyncIntervalSeconds,
        'webdavSyncWifiOnly': webdavSyncWifiOnly,
        'restoreSession': restoreSession,
        'offlineMode': offlineMode,
        'draftSyncEnabled': draftSyncEnabled,
        'syncRepoOwner': syncRepoOwner,
        'syncRepoName': syncRepoName,
        'syncRepoBranch': syncRepoBranch,
        'syncRepoToken': syncRepoToken,
      };

  factory SyncSettings.fromJson(Map<String, dynamic> j) => SyncSettings(
        autoSaveEnabled: j['autoSaveEnabled'] != false,
        autoSaveIntervalSeconds: (j['autoSaveIntervalSeconds'] as num?)?.toInt() ?? 30,
        autoSaveDir: j['autoSaveDir']?.toString() ?? '',
        backupDir: j['backupDir']?.toString() ?? '',
        webdavUrl: j['webdavUrl']?.toString() ?? '',
        webdavUsername: j['webdavUsername']?.toString() ?? '',
        webdavPassword: j['webdavPassword']?.toString() ?? '',
        webdavFolder: j['webdavFolder']?.toString() ?? 'hexo-backup',
        webdavAutoSyncEnabled: j['webdavAutoSyncEnabled'] == true,
        webdavAutoSyncIntervalSeconds: (j['webdavAutoSyncIntervalSeconds'] as num?)?.toInt() ?? 300,
        webdavSyncWifiOnly: j['webdavSyncWifiOnly'] != false,
        restoreSession: j['restoreSession'] != false,
        offlineMode: j['offlineMode'] == true,
        draftSyncEnabled: j['draftSyncEnabled'] == true,
        syncRepoOwner: j['syncRepoOwner']?.toString() ?? '',
        syncRepoName: j['syncRepoName']?.toString() ?? '',
        syncRepoBranch: j['syncRepoBranch']?.toString() ?? 'main',
        syncRepoToken: j['syncRepoToken']?.toString() ?? '',
      );
}