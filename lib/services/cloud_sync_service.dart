import 'dart:convert';

import '../models/app_settings.dart';
import '../models/article.dart';
import '../models/repo_config.dart';
import 'github_service.dart';
import 'log_service.dart';
import 'sync_service.dart';
import 'webdav_service.dart';

// ============================================================
// 同步后端抽象
// ============================================================

/// 同步文件信息
class SyncFileInfo {
  final String path;
  final int size;
  final DateTime modified;
  final String? sha; // GitHub 专用

  const SyncFileInfo({
    required this.path,
    required this.size,
    required this.modified,
    this.sha,
  });
}

/// 同步后端类型
enum SyncBackendType { github, webdav }

/// 同步后端抽象接口
abstract class SyncBackend {
  SyncBackendType get type;
  String get displayName;
  bool get isConfigured;

  /// 读取文件内容
  Future<String?> readFile(String path);

  /// 写入文件
  Future<void> writeFile(String path, String content);

  /// 删除文件
  Future<void> deleteFile(String path);

  /// 列出指定前缀下的文件
  Future<List<SyncFileInfo>> listFiles(String prefix);

  /// 释放资源
  void dispose();
}

// ============================================================
// GitHub 同步后端
// ============================================================

class GitHubSyncBackend implements SyncBackend {
  final GitHubService _github;
  RepoConfig? _repo;
  String _syncPath = '_hexo_sync';

  GitHubSyncBackend(this._github);

  @override
  SyncBackendType get type => SyncBackendType.github;

  @override
  String get displayName => 'GitHub 仓库同步';

  @override
  bool get isConfigured => _repo != null && _repo!.token.isNotEmpty;

  /// 配置同步仓库
  void configureRepo(RepoConfig repo, {String syncPath = '_hexo_sync'}) {
    _repo = repo;
    _syncPath = syncPath;
  }

  @override
  Future<String?> readFile(String path) async {
    if (_repo == null) return null;
    final fullPath = '$_syncPath/$path';
    final result = await _github.getRawFile(_repo!, fullPath);
    return result?['content'];
  }

  @override
  Future<void> writeFile(String path, String content) async {
    if (_repo == null) throw Exception('GitHub 同步仓库未配置');

    final fullPath = '$_syncPath/$path';
    String? sha;
    try {
      final existing = await _github.getRawFile(_repo!, fullPath);
      sha = existing?['sha'];
    } catch (e) { debugPrint('CloudSync: get SHA for writeFile failed: $e'); }

    await _github.putRawFile(
      _repo!,
      fullPath,
      content,
      sha: sha,
      commitMessage: 'sync: update $path',
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    if (_repo == null) throw Exception('GitHub 同步仓库未配置');

    final fullPath = '$_syncPath/$path';
    try {
      final existing = await _github.getRawFile(_repo!, fullPath);
      if (existing != null) {
        await _github.deleteRawFile(
          _repo!,
          fullPath,
          existing['sha'] ?? '',
          commitMessage: 'sync: delete $path',
        );
      }
    } catch (e) { debugPrint('CloudSync: get SHA for deleteFile failed: $e'); }
  }

  @override
  Future<List<SyncFileInfo>> listFiles(String prefix) async {
    if (_repo == null) return [];

    try {
      final items = await _github.listPosts(_repo!, path: _syncPath);
      final result = <SyncFileInfo>[];
      for (final item in items) {
        final relativePath = item.path.startsWith('$_syncPath/')
            ? item.path.substring(_syncPath.length + 1)
            : item.path;
        if (prefix.isEmpty || relativePath.startsWith(prefix)) {
          result.add(SyncFileInfo(
            path: relativePath,
            size: item.size ?? 0,
            modified: item.lastModified ?? DateTime.now(),
            sha: item.sha,
          ));
        }
      }
      return result;
    } catch (e) { debugPrint('CloudSync: listFiles failed: $e');
      return [];
    }
  }

  @override
  void dispose() {
    // GitHub service is externally managed; nothing to clean up here
  }
}

// ============================================================
// WebDAV 同步后端
// ============================================================

class WebDavSyncBackend implements SyncBackend {
  final WebDavService _webdav = WebDavService();
  String _url = '';
  String _username = '';
  String _password = '';
  String _folder = 'hexo-sync';

  @override
  SyncBackendType get type => SyncBackendType.webdav;

  @override
  String get displayName => 'WebDAV 网盘同步';

  @override
  bool get isConfigured => _url.isNotEmpty && _username.isNotEmpty;

  /// 从 AppSettings 配置
  void configureFromSettings(AppSettings settings) {
    _url = settings.webdavUrl;
    _username = settings.webdavUsername;
    _password = settings.webdavPassword;
    if (settings.webdavFolder.isNotEmpty) {
      _folder = settings.webdavFolder;
    }
  }

  /// 手动配置
  void configure({
    required String url,
    required String username,
    required String password,
    String folder = 'hexo-sync',
  }) {
    _url = url;
    _username = username;
    _password = password;
    _folder = folder;
  }

  @override
  Future<String?> readFile(String path) async {
    if (!isConfigured) return null;
    try {
      final bytes = await _webdav.downloadFile(
        _url, _username, _password, _folder, path,
      );
      return utf8.decode(bytes);
    } catch (e) { debugPrint('CloudSync: WebDAV readFile failed: $e');
      return null;
    }
  }

  @override
  Future<void> writeFile(String path, String content) async {
    if (!isConfigured) throw Exception('WebDAV 未配置');

    await _webdav.uploadFile(
      _url, _username, _password, _folder, path,
      utf8.encode(content),
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    if (!isConfigured) throw Exception('WebDAV 未配置');

    try {
      await _webdav.deleteFile(_url, _username, _password, _folder, path);
    } catch (e) { debugPrint('CloudSync: WebDAV deleteFile failed: $e'); }
  }

  @override
  Future<List<SyncFileInfo>> listFiles(String prefix) async {
    if (!isConfigured) return [];

    try {
      final items = await _webdav.list(_url, _username, _password, _folder);
      final result = <SyncFileInfo>[];
      for (final item in items) {
        if (!item.isDir && (prefix.isEmpty || item.name.startsWith(prefix))) {
          result.add(SyncFileInfo(
            path: item.name,
            size: item.size ?? 0,
            modified: item.modified,
          ));
        }
      }
      return result;
    } catch (e) { debugPrint('CloudSync: WebDAV listFiles failed: $e');
      return [];
    }
  }

  @override
  void dispose() {
    // WebDavService creates and closes its own HttpClient per request
  }
}

// ============================================================
// 云端同步服务
// ============================================================

/// 同步冲突策略
enum ConflictStrategy {
  /// 本地优先
  localWins,

  /// 远程优先
  remoteWins,

  /// 保留双方（创建冲突副本）
  keepBoth,

  /// 最新时间优先
  newestWins,
}

/// 同步结果
class SyncResult {
  int pulled;
  int pushed;
  int conflicts;
  List<String> errors;

  SyncResult({
    this.pulled = 0,
    this.pushed = 0,
    this.conflicts = 0,
    List<String>? errors,
  }) : errors = errors ?? [];

  bool get isSuccess => errors.isEmpty;
}

/// 云端同步服务
///
/// 统一管理多种同步后端，负责：
/// - 草稿 JSON 同步
/// - 设置同步
/// - 同步映射同步
/// - 模板/片段同步
/// - 冲突处理（时间戳比对 + 冲突副本）
/// - 敏感数据加密（Token、API Key）
class CloudSyncService {
  final LogService _logService;
  final Map<SyncBackendType, SyncBackend> _backends = {};

  /// 设备密钥（持久化，不同设备不同密钥）
  String _deviceKey = '';

  CloudSyncService(this._logService);

  /// 初始化设备密钥（必须在首次使用前调用）
  Future<void> initDeviceKey(String key) async {
    _deviceKey = key;
  }

  /// 释放所有后端资源（HttpClient 等）
  void dispose() {
    for (final backend in _backends.values) {
      backend.dispose();
    }
    _backends.clear();
  }

  /// 注册同步后端
  void registerBackend(SyncBackend backend) {
    _backends[backend.type] = backend;
  }

  /// 获取后端
  SyncBackend? getBackend(SyncBackendType type) => _backends[type];

  /// 获取所有已配置的后端
  List<SyncBackend> get configuredBackends =>
      _backends.values.where((b) => b.isConfigured).toList();

  /// 是否有已配置的后端
  bool get hasConfiguredBackend => configuredBackends.isNotEmpty;

  // ============================================================
  // 草稿同步
  // ============================================================

  /// 推送草稿到云端
  Future<SyncResult> pushDrafts(
    SyncBackend backend,
    List<Article> drafts,
  ) async {
    final result = SyncResult();
    for (final draft in drafts) {
      try {
        final path = 'drafts/${draft.id}.json';
        final json = jsonEncode(draft.toJson());
        await backend.writeFile(path, json);
        result.pushed++;
      } catch (e) {
        result.errors.add('推送草稿失败 [${draft.title}]: $e');
      }
    }
    if (result.pushed > 0) {
      _logService.add('云同步', '已推送 $result.pushed 篇草稿到 ${backend.displayName}');
    }
    return result;
  }

  /// 拉取草稿从云端
  /// 返回合并后的完整草稿列表（本地独有 + 远程独有 + 冲突解决结果）
  Future<List<Article>> pullDrafts(
    SyncBackend backend, {
    ConflictStrategy strategy = ConflictStrategy.newestWins,
    List<Article>? existingDrafts, // 用于冲突检测
  }) async {
    final merged = <Article>[];
    final localMap = <String, Article>{};
    final remoteIds = <String>{};
    if (existingDrafts != null) {
      for (final d in existingDrafts) {
        localMap[d.id] = d;
      }
    }

    try {
      final files = await backend.listFiles('drafts/');
      for (final file in files) {
        try {
          final content = await backend.readFile(file.path);
          if (content == null) continue;

          final json = jsonDecode(content) as Map<String, dynamic>;
          final remote = Article.fromJson(json);
          remoteIds.add(remote.id);

          // 冲突检测
          final local = localMap[remote.id];
          if (local != null) {
            if (remote.updatedAt.isAfter(local.updatedAt)) {
              // 远程更新 → 使用远程版本
              merged.add(remote);
            } else {
              // 本地更新或相同 → 保留本地
              merged.add(local);
            }
          } else {
            // 本地没有 → 直接采用远程
            merged.add(remote);
          }
        } catch (e) {
          _logService.add('拉取草稿失败', '${file.path}: $e', success: false);
        }
      }
    } catch (e) {
      _logService.add('云同步失败', '拉取草稿列表失败: $e', success: false);
    }

    // 保留本地独有的草稿（不在远程但存在于本地）
    if (existingDrafts != null) {
      for (final d in existingDrafts) {
        if (!remoteIds.contains(d.id)) {
          merged.add(d);
        }
      }
    }

    _logService.add('云同步', '已从 ${backend.displayName} 拉取 ${merged.length} 篇草稿');
    return merged;
  }

  // ============================================================
  // 设置同步
  // ============================================================

  /// 推送设置到云端（敏感数据加密）
  Future<void> pushSettings(SyncBackend backend, AppSettings settings) async {
    final json = jsonEncode(settings.toJson());
    final encrypted = _encrypt(json, _deviceKey);
    await backend.writeFile('config/settings.enc', encrypted);
    _logService.add('云同步', '已推送设置到 ${backend.displayName}');
  }

  /// 拉取设置从云端（解密）
  Future<AppSettings?> pullSettings(SyncBackend backend) async {
    try {
      final encrypted = await backend.readFile('config/settings.enc');
      if (encrypted == null) return null;

      final json = _decrypt(encrypted, _deviceKey);
      return AppSettings.fromJson(jsonDecode(json));
    } catch (e) {
      _logService.add('拉取设置失败', '$e', success: false);
      return null;
    }
  }

  // ============================================================
  // 同步映射同步
  // ============================================================

  /// 推送同步映射
  Future<void> pushSyncMappings(SyncBackend backend, SyncService syncService) async {
    final json = syncService.toJsonString();
    await backend.writeFile('config/sync_mappings.json', json);
    _logService.add('云同步', '已推送同步映射到 ${backend.displayName}');
  }

  /// 拉取同步映射
  Future<void> pullSyncMappings(SyncBackend backend, SyncService syncService) async {
    try {
      final json = await backend.readFile('config/sync_mappings.json');
      if (json != null) {
        syncService.fromJsonString(json);
        _logService.add('云同步', '已从 ${backend.displayName} 拉取同步映射');
      }
    } catch (e) {
      _logService.add('拉取同步映射失败', '$e', success: false);
    }
  }

  // ============================================================
  // 模板/片段同步
  // ============================================================

  /// 推送模板
  Future<void> pushTemplates(SyncBackend backend, List<dynamic> templates) async {
    final json = jsonEncode(templates.map((t) => t.toJson()).toList());
    await backend.writeFile('config/templates.json', json);
    _logService.add('云同步', '已推送 ${templates.length} 个模板');
  }

  /// 拉取模板列表
  Future<List<Map<String, dynamic>>?> pullTemplatesRaw(SyncBackend backend) async {
    try {
      final json = await backend.readFile('config/templates.json');
      if (json == null) return null;
      final list = jsonDecode(json) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (e) { debugPrint('CloudSync: pullTemplatesRaw failed: $e');
      return null;
    }
  }

  /// 推送片段
  Future<void> pushSnippets(SyncBackend backend, List<dynamic> snippets) async {
    final json = jsonEncode(snippets.map((s) => s.toJson()).toList());
    await backend.writeFile('config/snippets.json', json);
    _logService.add('云同步', '已推送 ${snippets.length} 个片段');
  }

  /// 拉取片段列表
  Future<List<Map<String, dynamic>>?> pullSnippetsRaw(SyncBackend backend) async {
    try {
      final json = await backend.readFile('config/snippets.json');
      if (json == null) return null;
      final list = jsonDecode(json) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (e) { debugPrint('CloudSync: pullSnippetsRaw failed: $e');
      return null;
    }
  }

  // ============================================================
  // 一键全量同步
  // ============================================================

  /// 全量推送到云端
  Future<SyncResult> pushAll(
    SyncBackend backend, {
    required List<Article> drafts,
    required AppSettings settings,
    required SyncService syncService,
    List<dynamic>? templates,
    List<dynamic>? snippets,
  }) async {
    final result = SyncResult();

    // 推送草稿
    final draftResult = await pushDrafts(backend, drafts);
    result.pushed += draftResult.pushed;
    result.errors.addAll(draftResult.errors);

    // 推送设置
    try {
      await pushSettings(backend, settings);
      result.pushed++;
    } catch (e) {
      result.errors.add('推送设置失败: $e');
    }

    // 推送同步映射
    try {
      await pushSyncMappings(backend, syncService);
      result.pushed++;
    } catch (e) {
      result.errors.add('推送同步映射失败: $e');
    }

    // 推送模板
    if (templates != null && templates.isNotEmpty) {
      try {
        await pushTemplates(backend, templates);
        result.pushed++;
      } catch (e) {
        result.errors.add('推送模板失败: $e');
      }
    }

    // 推送片段
    if (snippets != null && snippets.isNotEmpty) {
      try {
        await pushSnippets(backend, snippets);
        result.pushed++;
      } catch (e) {
        result.errors.add('推送片段失败: $e');
      }
    }

    _logService.add(
      '云同步',
      '全量推送完成: ${result.pushed} 成功, ${result.errors.length} 失败',
      success: result.isSuccess,
    );
    return result;
  }

  /// 全量从云端拉取
  Future<SyncResult> pullAll(
    SyncBackend backend, {
    List<Article>? existingDrafts,
    required void Function(AppSettings) onSettingsLoaded,
    required SyncService syncService,
    void Function(List<Map<String, dynamic>>)? onTemplatesLoaded,
    void Function(List<Map<String, dynamic>>)? onSnippetsLoaded,
    required void Function(List<Article> drafts) onDraftsLoaded,
  }) async {
    final result = SyncResult();

    // 拉取草稿
    try {
      final drafts = await pullDrafts(backend, existingDrafts: existingDrafts);
      onDraftsLoaded(drafts);
      result.pulled += drafts.length;
    } catch (e) {
      result.errors.add('拉取草稿失败: $e');
    }

    // 拉取设置
    try {
      final settings = await pullSettings(backend);
      if (settings != null) {
        onSettingsLoaded(settings);
        result.pulled++;
      }
    } catch (e) {
      result.errors.add('拉取设置失败: $e');
    }

    // 拉取同步映射
    try {
      await pullSyncMappings(backend, syncService);
      result.pulled++;
    } catch (e) {
      result.errors.add('拉取同步映射失败: $e');
    }

    // 拉取模板
    if (onTemplatesLoaded != null) {
      try {
        final templates = await pullTemplatesRaw(backend);
        if (templates != null) {
          onTemplatesLoaded(templates);
          result.pulled++;
        }
      } catch (e) {
        result.errors.add('拉取模板失败: $e');
      }
    }

    // 拉取片段
    if (onSnippetsLoaded != null) {
      try {
        final snippets = await pullSnippetsRaw(backend);
        if (snippets != null) {
          onSnippetsLoaded(snippets);
          result.pulled++;
        }
      } catch (e) {
        result.errors.add('拉取片段失败: $e');
      }
    }

    _logService.add(
      '云同步',
      '全量拉取完成: ${result.pulled} 成功, ${result.errors.length} 失败',
      success: result.isSuccess,
    );
    return result;
  }

  // ============================================================
  // 加密/解密（简单 XOR + Base64，防明文泄露）
  // ============================================================

  String _encrypt(String plainText, String key) {
    final keyBytes = utf8.encode(key);
    final dataBytes = utf8.encode(plainText);
    final result = <int>[];
    for (var i = 0; i < dataBytes.length; i++) {
      result.add(dataBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    return base64Encode(result);
  }

  String _decrypt(String encrypted, String key) {
    final keyBytes = utf8.encode(key);
    final dataBytes = base64Decode(encrypted);
    final result = <int>[];
    for (var i = 0; i < dataBytes.length; i++) {
      result.add(dataBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    return utf8.decode(result);
  }
}