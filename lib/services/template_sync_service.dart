/// 模板同步服务
///
/// 参考 hexo-mobile (https://github.com/NoahDragon/hexo-mobile) FrontMatter 处理：
/// - 模板和片段的跨设备同步
/// - 使用 JSON 格式存储模板元数据
/// - 增量同步（仅同步变更的模板）
/// - 冲突解决策略
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// 模板类型
enum TemplateType {
  article('文章模板'),
  page('页面模板'),
  snippet('代码片段'),
  frontmatter('FrontMatter'),
  custom('自定义');

  final String label;
  const TemplateType(this.label);
}

/// 模板条目
class TemplateEntry {
  final String id;
  final String name;
  final String content;
  final TemplateType type;
  final String? description;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String sha256;
  final int size;
  final bool isBuiltIn;

  const TemplateEntry({
    required this.id,
    required this.name,
    required this.content,
    required this.type,
    this.description,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    required this.sha256,
    required this.size,
    this.isBuiltIn = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'content': content,
        'type': type.name,
        'description': description,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'sha256': sha256,
        'size': size,
        'isBuiltIn': isBuiltIn,
      };

  factory TemplateEntry.fromJson(Map<String, dynamic> j) => TemplateEntry(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        content: j['content']?.toString() ?? '',
        type: TemplateType.values.firstWhere(
          (t) => t.name == j['type']?.toString(),
          orElse: () => TemplateType.custom,
        ),
        description: j['description']?.toString(),
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(j['updatedAt']?.toString() ?? '') ?? DateTime.now(),
        sha256: j['sha256']?.toString() ?? '',
        size: (j['size'] as num?)?.toInt() ?? 0,
        isBuiltIn: j['isBuiltIn'] == true,
      );

  /// 计算内容哈希
  static String computeHash(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }
}

/// 模板同步状态
enum TemplateSyncState {
  idle,
  scanning,
  syncing,
  completed,
  conflict,
  error,
}

/// 模板同步冲突
class TemplateSyncConflict {
  final String templateId;
  final String templateName;
  final TemplateEntry localEntry;
  final TemplateEntry remoteEntry;

  const TemplateSyncConflict({
    required this.templateId,
    required this.templateName,
    required this.localEntry,
    required this.remoteEntry,
  });
}

/// 模板同步结果
class TemplateSyncResult {
  final int totalTemplates;
  final int synced;
  final int skipped;
  final int conflicts;
  final List<TemplateSyncConflict> conflictDetails;

  const TemplateSyncResult({
    required this.totalTemplates,
    required this.synced,
    required this.skipped,
    required this.conflicts,
    this.conflictDetails = const [],
  });
}

/// 模板同步服务
///
/// 管理模板和片段的跨设备同步，支持增量同步和冲突解决。
class TemplateSyncService {
  final Directory _templateDir;
  final String _deviceId;

  TemplateSyncState _state = TemplateSyncState.idle;
  String? _errorMessage;

  static const String _manifestFile = 'template_manifest.json';
  static const String _syncStateFile = '.template_sync_state';

  final StreamController<TemplateSyncState> _stateController =
      StreamController<TemplateSyncState>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  TemplateSyncService({
    required Directory templateDir,
    required String deviceId,
  })  : _templateDir = templateDir,
        _deviceId = deviceId;

  TemplateSyncState get state => _state;
  String? get errorMessage => _errorMessage;
  Stream<TemplateSyncState> get onStateChange => _stateController.stream;
  Stream<String> get onLog => _logController.stream;

  // ============================================================
  // 本地模板管理
  // ============================================================

  /// 获取所有本地模板
  Future<List<TemplateEntry>> getLocalTemplates() async {
    if (!await _templateDir.exists()) {
      await _templateDir.create(recursive: true);
      return [];
    }

    final templates = <TemplateEntry>[];
    await for (final entity in _templateDir.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.json') || entity.path.endsWith(_manifestFile)) {
        continue;
      }

      try {
        final content = await entity.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        templates.add(TemplateEntry.fromJson(json));
      } catch (_) {
        // 跳过无效文件
      }
    }

    return templates;
  }

  /// 保存模板到本地
  Future<void> saveTemplate(TemplateEntry entry) async {
    if (!await _templateDir.exists()) {
      await _templateDir.create(recursive: true);
    }

    final file = File('${_templateDir.path}/${entry.id}.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(entry.toJson()),
    );
  }

  /// 删除本地模板
  Future<void> deleteTemplate(String templateId) async {
    final file = File('${_templateDir.path}/$templateId.json');
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 创建新模板
  Future<TemplateEntry> createTemplate({
    required String name,
    required String content,
    required TemplateType type,
    String? description,
    List<String> tags = const [],
  }) async {
    final id = _generateTemplateId();
    final now = DateTime.now();
    final hash = TemplateEntry.computeHash(content);

    final entry = TemplateEntry(
      id: id,
      name: name,
      content: content,
      type: type,
      description: description,
      tags: tags,
      createdAt: now,
      updatedAt: now,
      sha256: hash,
      size: content.length,
    );

    await saveTemplate(entry);
    return entry;
  }

  /// 更新模板
  Future<TemplateEntry?> updateTemplate({
    required String id,
    String? name,
    String? content,
    TemplateType? type,
    String? description,
    List<String>? tags,
  }) async {
    final templates = await getLocalTemplates();
    final existing = templates.where((t) => t.id == id).firstOrNull;
    if (existing == null) return null;

    final now = DateTime.now();
    final newContent = content ?? existing.content;
    final hash = TemplateEntry.computeHash(newContent);

    final entry = TemplateEntry(
      id: id,
      name: name ?? existing.name,
      content: newContent,
      type: type ?? existing.type,
      description: description ?? existing.description,
      tags: tags ?? existing.tags,
      createdAt: existing.createdAt,
      updatedAt: now,
      sha256: hash,
      size: newContent.length,
      isBuiltIn: existing.isBuiltIn,
    );

    await saveTemplate(entry);
    return entry;
  }

  // ============================================================
  // 模板同步
  // ============================================================

  /// 同步远程模板到本地
  ///
  /// [remoteTemplates] 远程设备的模板列表
  /// [conflictStrategy] 冲突解决策略: 'local' | 'remote' | 'newer' | 'manual'
  Future<TemplateSyncResult> syncTemplates(
    List<TemplateEntry> remoteTemplates, {
    String conflictStrategy = 'newer',
    Future<String> Function(TemplateSyncConflict conflict)? manualResolver,
  }) async {
    _setState(TemplateSyncState.scanning);
    _log('开始同步模板，远程 ${remoteTemplates.length} 个模板...');

    int synced = 0;
    int skipped = 0;
    int conflicts = 0;
    final conflictDetails = <TemplateSyncConflict>[];

    try {
      final localTemplates = await getLocalTemplates();
      final localMap = {for (final t in localTemplates) t.id: t};

      _setState(TemplateSyncState.syncing);

      for (final remote in remoteTemplates) {
        final local = localMap[remote.id];

        if (local == null) {
          // 本地不存在，直接保存
          await saveTemplate(remote);
          synced++;
          _log('新增模板: ${remote.name}');
          continue;
        }

        // 本地存在，比较哈希
        if (local.sha256 == remote.sha256) {
          skipped++;
          continue;
        }

        // 有差异，需要解决冲突
        final conflict = TemplateSyncConflict(
          templateId: remote.id,
          templateName: remote.name,
          localEntry: local,
          remoteEntry: remote,
        );

        final resolution = await _resolveConflict(
          conflict,
          conflictStrategy,
          manualResolver,
        );

        switch (resolution) {
          case 'remote':
            await saveTemplate(remote);
            synced++;
            _log('已更新: ${remote.name} (使用远程)');
            break;
          case 'local':
            skipped++;
            _log('已跳过: ${remote.name} (保留本地)');
            break;
          case 'merge':
            // 合并策略：保留本地 frontmatter，使用远程内容
            final merged = _mergeTemplates(local, remote);
            await saveTemplate(merged);
            synced++;
            _log('已合并: ${remote.name}');
            break;
          default:
            conflicts++;
            conflictDetails.add(conflict);
            _log('冲突未解决: ${remote.name}');
        }
      }

      // 更新同步状态
      await _saveSyncState();
    } catch (e) {
      _setState(TemplateSyncState.error);
      _errorMessage = '同步失败: $e';
      _log('同步失败: $e');
    }

    _setState(TemplateSyncState.completed);
    _log('模板同步完成: 同步 $synced, 跳过 $skipped, 冲突 $conflicts');

    return TemplateSyncResult(
      totalTemplates: remoteTemplates.length,
      synced: synced,
      skipped: skipped,
      conflicts: conflicts,
      conflictDetails: conflictDetails,
    );
  }

  /// 导出模板清单（用于发送给其他设备）
  Future<List<TemplateEntry>> exportManifest() async {
    return getLocalTemplates();
  }

  /// 获取自上次同步以来变更的模板
  Future<List<TemplateEntry>> getChangedTemplates() async {
    final lastSync = await _getLastSyncTime();
    final templates = await getLocalTemplates();
    return templates.where((t) => t.updatedAt.isAfter(lastSync)).toList();
  }

  // ============================================================
  // 冲突解决
  // ============================================================

  Future<String> _resolveConflict(
    TemplateSyncConflict conflict,
    String strategy,
    Future<String> Function(TemplateSyncConflict)? manualResolver,
  ) async {
    switch (strategy) {
      case 'local':
        return 'local';
      case 'remote':
        return 'remote';
      case 'newer':
        return conflict.remoteEntry.updatedAt
                .isAfter(conflict.localEntry.updatedAt)
            ? 'remote'
            : 'local';
      case 'manual':
        if (manualResolver != null) {
          return await manualResolver(conflict);
        }
        return 'conflict';
      default:
        return 'conflict';
    }
  }

  /// 合并两个模板
  ///
  /// 保留本地模板的元数据（名称、标签等），使用远程模板的内容。
  TemplateEntry _mergeTemplates(TemplateEntry local, TemplateEntry remote) {
    final mergedContent = remote.content;
    final hash = TemplateEntry.computeHash(mergedContent);

    return TemplateEntry(
      id: local.id,
      name: local.name,
      content: mergedContent,
      type: local.type,
      description: local.description,
      tags: local.tags,
      createdAt: local.createdAt,
      updatedAt: DateTime.now(),
      sha256: hash,
      size: mergedContent.length,
      isBuiltIn: local.isBuiltIn,
    );
  }

  // ============================================================
  // 内部方法
  // ============================================================

  String _generateTemplateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'tpl_${now.toRadixString(16)}';
  }

  Future<DateTime> _getLastSyncTime() async {
    final file = File('${_templateDir.path}/$_syncStateFile');
    if (!await file.exists()) return DateTime(2000);
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final time = json['lastSyncTime']?.toString() ?? '';
      return DateTime.tryParse(time) ?? DateTime(2000);
    } catch (_) {
      return DateTime(2000);
    }
  }

  Future<void> _saveSyncState() async {
    final file = File('${_templateDir.path}/$_syncStateFile');
    await file.writeAsString(jsonEncode({
      'lastSyncTime': DateTime.now().toIso8601String(),
      'deviceId': _deviceId,
    }));
  }

  void _setState(TemplateSyncState newState) {
    _state = newState;
    if (newState != TemplateSyncState.error) {
      _errorMessage = null;
    }
    _stateController.add(newState);
  }

  void _log(String message) {
    _logController.add('[${DateTime.now().toIso8601String()}] $message');
  }

  // ============================================================
  // 清理
  // ============================================================

  void dispose() {
    _stateController.close();
    _logController.close();
    _state = TemplateSyncState.idle;
  }
}