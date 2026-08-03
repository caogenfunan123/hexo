import 'dart:convert';
import 'dart:io';

import 'log_service.dart';

/// 版本快照条目
class VersionSnapshot {
  final String id;
  final String articleId;
  final String articleTitle;
  final String content;
  final DateTime createdAt;
  final int contentLength;
  final String? label; // 用户自定义标签

  const VersionSnapshot({
    required this.id,
    required this.articleId,
    required this.articleTitle,
    required this.content,
    required this.createdAt,
    required this.contentLength,
    this.label,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'articleId': articleId,
    'articleTitle': articleTitle,
    'createdAt': createdAt.toIso8601String(),
    'contentLength': contentLength,
    if (label != null) 'label': label,
  };

  factory VersionSnapshot.fromJson(Map<String, dynamic> j, String content) => VersionSnapshot(
    id: j['id']?.toString() ?? '',
    articleId: j['articleId']?.toString() ?? '',
    articleTitle: j['articleTitle']?.toString() ?? '',
    content: content,
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
    contentLength: (j['contentLength'] as num?)?.toInt() ?? 0,
    label: j['label']?.toString(),
  );
}

/// 版本快照服务
/// 定时保存文档快照，支持回退到历史版本
class VersionSnapshotService {
  final LogService _logService;
  late Directory _snapshotDir;

  static const _indexFile = 'snapshot_index.json';
  static const int _maxSnapshotsPerArticle = 30;
  static const int _autoCleanDays = 7;

  VersionSnapshotService(this._logService);

  Future<void> init(Directory appDir) async {
    _snapshotDir = Directory('${appDir.path}/snapshots');
    if (!await _snapshotDir.exists()) {
      await _snapshotDir.create(recursive: true);
    }
  }

  /// 获取文章快照目录
  Directory _articleDir(String articleId) {
    final d = Directory('${_snapshotDir.path}/$articleId');
    return d;
  }

  /// 创建快照
  Future<VersionSnapshot?> createSnapshot(String articleId, String articleTitle, String content) async {
    if (content.isEmpty) return null;

    final dir = _articleDir(articleId);
    if (!await dir.exists()) await dir.create(recursive: true);

    // 检查是否与最新快照相同
    final existing = await _loadIndex(articleId);
    if (existing.isNotEmpty) {
      final latest = existing.last;
      final latestFile = File('${dir.path}/${latest.id}.md');
      if (await latestFile.exists()) {
        final latestContent = await latestFile.readAsString();
        if (latestContent == content) return null; // 无变化，跳过
      }
    }

    final snapshotId = DateTime.now().millisecondsSinceEpoch.toString();
    final snapshot = VersionSnapshot(
      id: snapshotId,
      articleId: articleId,
      articleTitle: articleTitle,
      content: content,
      createdAt: DateTime.now(),
      contentLength: content.length,
    );

    // 保存内容
    final contentFile = File('${dir.path}/$snapshotId.md');
    await contentFile.writeAsString(content);

    // 保存索引
    final index = await _loadIndex(articleId);
    index.add(snapshot);
    // 超过最大数量时删除旧快照
    while (index.length > _maxSnapshotsPerArticle) {
      final old = index.removeAt(0);
      final oldFile = File('${dir.path}/${old.id}.md');
      if (await oldFile.exists()) await oldFile.delete();
    }
    await _saveIndex(articleId, index);

    return snapshot;
  }

  /// 获取文章的所有快照
  Future<List<VersionSnapshot>> getSnapshots(String articleId) async {
    final index = await _loadIndex(articleId);
    final dir = _articleDir(articleId);
    final result = <VersionSnapshot>[];

    for (final meta in index) {
      final contentFile = File('${dir.path}/${meta.id}.md');
      if (await contentFile.exists()) {
        final content = await contentFile.readAsString();
        result.add(VersionSnapshot.fromJson(meta.toJson(), content));
      }
    }
    return result;
  }

  /// 获取指定快照的内容
  Future<String?> getSnapshotContent(String articleId, String snapshotId) async {
    final dir = _articleDir(articleId);
    final contentFile = File('${dir.path}/$snapshotId.md');
    if (await contentFile.exists()) {
      return await contentFile.readAsString();
    }
    return null;
  }

  /// 删除指定快照
  Future<void> deleteSnapshot(String articleId, String snapshotId) async {
    final dir = _articleDir(articleId);
    final contentFile = File('${dir.path}/$snapshotId.md');
    if (await contentFile.exists()) await contentFile.delete();

    final index = await _loadIndex(articleId);
    index.removeWhere((s) => s.id == snapshotId);
    await _saveIndex(articleId, index);
  }

  /// 删除文章的所有快照
  Future<void> deleteAllSnapshots(String articleId) async {
    final dir = _articleDir(articleId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 自动清理超过指定天数的快照
  Future<int> autoClean({int days = _autoCleanDays}) async {
    int cleaned = 0;
    final cutoff = DateTime.now().subtract(Duration(days: days));

    if (!await _snapshotDir.exists()) return 0;

    final articleDirs = await _snapshotDir.list().toList();
    for (final entity in articleDirs) {
      if (entity is! Directory) continue;
      final articleId = entity.path.split('/').last;
      final index = await _loadIndex(articleId);
      final toDelete = index.where((s) => s.createdAt.isBefore(cutoff)).toList();

      for (final snapshot in toDelete) {
        final file = File('${entity.path}/${snapshot.id}.md');
        if (await file.exists()) await file.delete();
        index.remove(snapshot);
        cleaned++;
      }

      if (index.isEmpty) {
        await entity.delete(recursive: true);
      } else {
        await _saveIndex(articleId, index);
      }
    }

    if (cleaned > 0) {
      _logService.add('快照清理', '已自动清理 $cleaned 个过期快照');
    }
    return cleaned;
  }

  /// 获取快照总数
  Future<int> get totalSnapshots async {
    int count = 0;
    if (!await _snapshotDir.exists()) return 0;
    final dirs = await _snapshotDir.list().toList();
    for (final entity in dirs) {
      if (entity is Directory) {
        final index = await _loadIndex(entity.path.split('/').last);
        count += index.length;
      }
    }
    return count;
  }

  /// 加载索引
  Future<List<VersionSnapshot>> _loadIndex(String articleId) async {
    final dir = _articleDir(articleId);
    final indexFile = File('${dir.path}/$_indexFile');
    if (!await indexFile.exists()) return [];
    try {
      final json = await indexFile.readAsString();
      final list = jsonDecode(json) as List;
      return list
          .map((e) => VersionSnapshot(
                id: e['id']?.toString() ?? '',
                articleId: e['articleId']?.toString() ?? '',
                articleTitle: e['articleTitle']?.toString() ?? '',
                content: '', // 不加载内容
                createdAt: DateTime.tryParse(e['createdAt']?.toString() ?? '') ?? DateTime.now(),
                contentLength: (e['contentLength'] as num?)?.toInt() ?? 0,
                label: e['label']?.toString(),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存索引
  Future<void> _saveIndex(String articleId, List<VersionSnapshot> snapshots) async {
    final dir = _articleDir(articleId);
    if (!await dir.exists()) await dir.create(recursive: true);
    final indexFile = File('${dir.path}/$_indexFile');
    await indexFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshots.map((s) => s.toJson()).toList()),
    );
  }
}