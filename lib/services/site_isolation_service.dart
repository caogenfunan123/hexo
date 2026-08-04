/// 站点隔离服务
///
/// 参考 obsidian-flutter (https://github.com/maverick98/obsidian-flutter) 多工作区隔离：
/// - 每个站点独立的数据目录
/// - 站点切换时自动保存/加载对应数据
/// - 站点级别的加密支持
/// - 站点配置文件管理
library;

import 'dart:convert';
import 'dart:io';

import 'site_encryption_service.dart';

/// 站点工作区配置（站点隔离）
///
/// 注意：与 [SiteConfig]（controllers/site_controller.dart）不同，
/// 此类管理的是站点工作区的隔离配置，包括加密状态和元数据。
class IsolatedSiteConfig {
  final String id;
  final String name;
  final String description;
  final bool isEncrypted;
  final DateTime createdAt;
  final DateTime lastOpenedAt;
  final Map<String, String> metadata;

  const IsolatedSiteConfig({
    required this.id,
    required this.name,
    this.description = '',
    this.isEncrypted = false,
    required this.createdAt,
    required this.lastOpenedAt,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'isEncrypted': isEncrypted,
        'createdAt': createdAt.toIso8601String(),
        'lastOpenedAt': lastOpenedAt.toIso8601String(),
        'metadata': metadata,
      };

  factory IsolatedSiteConfig.fromJson(Map<String, dynamic> j) => IsolatedSiteConfig(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        isEncrypted: j['isEncrypted'] == true,
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
        lastOpenedAt:
            DateTime.tryParse(j['lastOpenedAt']?.toString() ?? '') ??
                DateTime.now(),
        metadata: Map<String, String>.from(j['metadata'] ?? {}),
      );

  IsolatedSiteConfig copyWith({
    String? name,
    String? description,
    bool? isEncrypted,
    DateTime? lastOpenedAt,
    Map<String, String>? metadata,
  }) {
    return IsolatedSiteConfig(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      createdAt: createdAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// 站点隔离服务
///
/// 管理多个站点的工作区隔离，每个站点拥有独立的数据目录和加密策略。
class SiteIsolationService {
  final Directory _baseDir;
  final Map<String, Directory> _siteDirs = {};
  final Map<String, IsolatedSiteConfig> _siteConfigs = {};

  IsolatedSiteConfig? _currentSite;
  String? _currentSiteId;

  /// 站点切换并发互斥锁
  bool _isSwitching = false;

  static const String _configFileName = 'site_config.json';
  static const String _indexFileName = 'sites_index.json';

  SiteIsolationService(this._baseDir);

  // ============================================================
  // 站点管理
  // ============================================================

  /// 获取所有站点配置
  Future<List<IsolatedSiteConfig>> getSites() async {
    await _loadIndex();
    return _siteConfigs.values.toList()
      ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
  }

  /// 获取当前站点配置
  IsolatedSiteConfig? get currentSite => _currentSite;

  /// 获取当前站点 ID
  String? get currentSiteId => _currentSiteId;

  /// 获取站点数据目录
  ///
  /// [siteId] 站点 ID
  Future<Directory> getSiteDir(String siteId) async {
    if (_siteDirs.containsKey(siteId)) {
      return _siteDirs[siteId]!;
    }

    final dir = Directory('${_baseDir.path}/sites/$siteId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _siteDirs[siteId] = dir;
    return dir;
  }

  /// 创建新站点
  ///
  /// [name] 站点名称
  /// [description] 站点描述
  /// [isEncrypted] 是否启用加密
  /// [password] 加密密码（如果启用加密）
  Future<IsolatedSiteConfig> createSite({
    required String name,
    String description = '',
    bool isEncrypted = false,
    String? password,
  }) async {
    final siteId = _generateSiteId();
    final now = DateTime.now();

    final config = IsolatedSiteConfig(
      id: siteId,
      name: name,
      description: description,
      isEncrypted: isEncrypted,
      createdAt: now,
      lastOpenedAt: now,
    );

    // 创建站点目录
    final dir = await getSiteDir(siteId);

    // 保存站点配置
    final configFile = File('${dir.path}/$_configFileName');
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );

    // 如果启用加密，初始化加密
    if (isEncrypted && password != null) {
      final keyFile = File('${dir.path}/.encryption_key');
      // 保存加密标记（实际密钥派生由 SiteEncryptionService 处理）
      await keyFile.writeAsString('encrypted:true');
    }

    _siteConfigs[siteId] = config;
    await _saveIndex();

    return config;
  }

  /// 切换到指定站点
  ///
  /// [siteId] 目标站点 ID
  Future<void> switchSite(String siteId) async {
    if (_currentSiteId == siteId || _isSwitching) return;
    _isSwitching = true;
    try {
      // 保存当前站点状态
      if (_currentSiteId != null) {
        await _saveCurrentSiteState();
      }

      // 加载目标站点
      final config = _siteConfigs[siteId];
      if (config == null) {
        throw Exception('站点不存在: $siteId');
      }

      // 更新最后打开时间
      final updatedConfig = config.copyWith(lastOpenedAt: DateTime.now());
      _siteConfigs[siteId] = updatedConfig;
      _currentSite = updatedConfig;
      _currentSiteId = siteId;

      // 确保目录存在
      await getSiteDir(siteId);

      // 保存索引
      await _saveIndex();
    } finally {
      _isSwitching = false;
    }
  }

  /// 删除站点
  ///
  /// [siteId] 站点 ID
  /// [deleteData] 是否同时删除站点数据
  Future<void> deleteSite(String siteId, {bool deleteData = true}) async {
    if (_currentSiteId == siteId) {
      _currentSite = null;
      _currentSiteId = null;
    }

    _siteConfigs.remove(siteId);

    if (deleteData) {
      final dir = _siteDirs.remove(siteId);
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      } else {
        // 如果不在缓存中，直接从路径删除
        final dataDir = Directory('${_baseDir.path}/sites/$siteId');
        if (await dataDir.exists()) {
          await dataDir.delete(recursive: true);
        }
      }
    }

    await _saveIndex();
  }

  /// 更新站点配置
  Future<void> updateSiteConfig(String siteId, IsolatedSiteConfig config) async {
    _siteConfigs[siteId] = config;

    final dir = await getSiteDir(siteId);
    final configFile = File('${dir.path}/$_configFileName');
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );

    await _saveIndex();
  }

  // ============================================================
  // 站点加密
  // ============================================================

  /// 加密站点数据
  ///
  /// [siteId] 站点 ID
  /// [password] 加密密码
  Future<void> encryptSiteData(String siteId, String password) async {
    final dir = await getSiteDir(siteId);

    // 遍历站点目录下的所有 .md 文件并加密
    final files = await dir
        .list(recursive: true)
        .where((e) => e is File && e.path.endsWith('.md'))
        .toList();

    for (final entity in files) {
      final file = entity as File;
      final content = await file.readAsString();
      try {
        final encrypted = SiteEncryptionService.encrypt(content, password);
        final encryptedPath = '${file.path}.enc';
        await File(encryptedPath).writeAsString(encrypted);
        // 加密成功后删除原文
        await file.delete();
      } catch (_) {
        // 加密失败，跳过此文件
      }
    }

    // 更新站点配置
    final config = _siteConfigs[siteId];
    if (config != null) {
      await updateSiteConfig(siteId, config.copyWith(isEncrypted: true));
    }
  }

  /// 解密站点数据
  ///
  /// [siteId] 站点 ID
  /// [password] 解密密码
  Future<void> decryptSiteData(String siteId, String password) async {
    final dir = await getSiteDir(siteId);

    // 遍历站点目录下的所有 .enc 文件并解密
    final files = await dir
        .list(recursive: true)
        .where((e) => e is File && e.path.endsWith('.md.enc'))
        .toList();

    for (final entity in files) {
      final file = entity as File;
      final encrypted = await file.readAsString();
      try {
        final decrypted = SiteEncryptionService.decrypt(encrypted, password);
        final originalPath = file.path.replaceAll('.enc', '');
        await File(originalPath).writeAsString(decrypted);
        // 解密成功后删除加密文件
        await file.delete();
      } catch (_) {
        // 解密失败，跳过此文件
      }
    }

    // 更新站点配置
    final config = _siteConfigs[siteId];
    if (config != null) {
      await updateSiteConfig(siteId, config.copyWith(isEncrypted: false));
    }
  }

  /// 验证站点密码
  ///
  /// [siteId] 站点 ID
  /// [password] 待验证密码
  Future<bool> verifySitePassword(String siteId, String password) async {
    final dir = await getSiteDir(siteId);

    // 找到第一个加密文件并验证
    final files = await dir
        .list(recursive: true)
        .where((e) => e is File && e.path.endsWith('.md.enc'))
        .toList();

    if (files.isEmpty) return true; // 没有加密文件

    for (final entity in files) {
      final file = entity as File;
      final encrypted = await file.readAsString();
      try {
        SiteEncryptionService.decrypt(encrypted, password);
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  // ============================================================
  // 站点数据路径
  // ============================================================

  /// 获取站点内的文章目录
  Future<Directory> getPostsDir(String siteId) async {
    final dir = await getSiteDir(siteId);
    final postsDir = Directory('${dir.path}/posts');
    if (!await postsDir.exists()) {
      await postsDir.create(recursive: true);
    }
    return postsDir;
  }

  /// 获取站点内的草稿目录
  Future<Directory> getDraftsDir(String siteId) async {
    final dir = await getSiteDir(siteId);
    final draftsDir = Directory('${dir.path}/drafts');
    if (!await draftsDir.exists()) {
      await draftsDir.create(recursive: true);
    }
    return draftsDir;
  }

  /// 获取站点内的媒体目录
  Future<Directory> getMediaDir(String siteId) async {
    final dir = await getSiteDir(siteId);
    final mediaDir = Directory('${dir.path}/media');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }

  /// 获取站点内的模板目录
  Future<Directory> getTemplatesDir(String siteId) async {
    final dir = await getSiteDir(siteId);
    final templatesDir = Directory('${dir.path}/templates');
    if (!await templatesDir.exists()) {
      await templatesDir.create(recursive: true);
    }
    return templatesDir;
  }

  // ============================================================
  // 内部方法
  // ============================================================

  /// 生成站点 ID
  String _generateSiteId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hex = now.toRadixString(16);
    return 'site_$hex';
  }

  /// 保存当前站点状态
  Future<void> _saveCurrentSiteState() async {
    if (_currentSiteId == null) return;
    // 状态保存逻辑（如当前打开的文章、光标位置等）
    // 由调用方负责具体实现
  }

  /// 加载站点索引
  Future<void> _loadIndex() async {
    final indexFile = File('${_baseDir.path}/$_indexFileName');
    if (!await indexFile.exists()) return;

    try {
      final json = await indexFile.readAsString();
      final list = jsonDecode(json) as List;
      for (final item in list) {
        final config = IsolatedSiteConfig.fromJson(Map<String, dynamic>.from(item));
        _siteConfigs[config.id] = config;
      }
    } catch (_) {
      // 索引文件损坏，从各站点目录恢复
      await _recoverIndex();
    }
  }

  /// 保存站点索引
  Future<void> _saveIndex() async {
    final indexFile = File('${_baseDir.path}/$_indexFileName');
    await indexFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        _siteConfigs.values.map((c) => c.toJson()).toList(),
      ),
    );
  }

  /// 从站点目录恢复索引
  Future<void> _recoverIndex() async {
    final sitesDir = Directory('${_baseDir.path}/sites');
    if (!await sitesDir.exists()) return;

    final dirs = await sitesDir.list().toList();
    for (final entity in dirs) {
      if (entity is Directory) {
        final configFile = File('${entity.path}/$_configFileName');
        if (await configFile.exists()) {
          try {
            final json = await configFile.readAsString();
            final config =
                IsolatedSiteConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
            _siteConfigs[config.id] = config;
          } catch (_) {
            // 跳过损坏的配置
          }
        }
      }
    }
    await _saveIndex();
  }

  /// 初始化服务
  Future<void> init() async {
    if (!await _baseDir.exists()) {
      await _baseDir.create(recursive: true);
    }
    await _loadIndex();
  }

  /// 释放资源
  void dispose() {
    _siteDirs.clear();
    _siteConfigs.clear();
    _currentSite = null;
    _currentSiteId = null;
  }
}