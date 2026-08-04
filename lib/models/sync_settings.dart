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
      );
}