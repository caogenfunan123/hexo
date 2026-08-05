import 'dart:convert';
import 'dart:io';

import '../models/article.dart';

/// 回收站条目
class RecycleBinEntry {
  final String id;
  final String originalPath;
  final String fileName;
  final Article article;
  final DateTime deletedAt;
  final int fileSize;

  const RecycleBinEntry({
    required this.id,
    required this.originalPath,
    required this.fileName,
    required this.article,
    required this.deletedAt,
    required this.fileSize,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'originalPath': originalPath,
    'fileName': fileName,
    'article': article.toJson(),
    'deletedAt': deletedAt.toIso8601String(),
    'fileSize': fileSize,
  };

  factory RecycleBinEntry.fromJson(Map<String, dynamic> j) => RecycleBinEntry(
    id: j['id']?.toString() ?? '',
    originalPath: j['originalPath']?.toString() ?? '',
    fileName: j['fileName']?.toString() ?? '',
    article: Article.fromJson(Map<String, dynamic>.from(j['article'] ?? {})),
    deletedAt: DateTime.tryParse(j['deletedAt']?.toString() ?? '') ?? DateTime.now(),
    fileSize: (j['fileSize'] as num?)?.toInt() ?? 0,
  );
}

/// 回收站服务
/// 删除文件时移入回收站目录，支持恢复和永久删除
class RecycleBinService {
  static const _indexFile = 'recycle_index.json';
  static const _trashDir = '.trash';

  late Directory _rootDir;

  /// 初始化回收站目录
  Future<void> init(Directory appDir) async {
    _rootDir = Directory('${appDir.path}/$_trashDir');
    if (!await _rootDir.exists()) {
      await _rootDir.create(recursive: true);
    }
  }

  /// 获取回收站目录
  Directory get trashDir => _rootDir;

  /// 加载回收站索引
  Future<List<RecycleBinEntry>> loadEntries() async {
    final indexFile = File('${_rootDir.path}/$_indexFile');
    if (!await indexFile.exists()) return [];
    try {
      final json = await indexFile.readAsString();
      final list = jsonDecode(json) as List;
      return list
          .map((e) => RecycleBinEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存回收站索引
  Future<void> _saveEntries(List<RecycleBinEntry> entries) async {
    final indexFile = File('${_rootDir.path}/$_indexFile');
    await indexFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(entries.map((e) => e.toJson()).toList()),
    );
  }

  /// 移入回收站
  /// [filePath] 原始文件路径
  /// [article] 文章对象（用于恢复时重建）
  /// 返回 entry id
  Future<String> moveToTrash(String filePath, Article article) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    final entryId = DateTime.now().millisecondsSinceEpoch.toString();
    final trashFileName = '${entryId}_${article.fileName()}';
    final trashPath = '${_rootDir.path}/$trashFileName';

    // 复制到回收站
    await file.copy(trashPath);

    final fileSize = await file.length();
    final entry = RecycleBinEntry(
      id: entryId,
      originalPath: filePath,
      fileName: trashFileName,
      article: article,
      deletedAt: DateTime.now(),
      fileSize: fileSize,
    );

    final entries = await loadEntries();
    entries.add(entry);
    await _saveEntries(entries);

    return entryId;
  }

  /// 从回收站恢复文件
  Future<String> restore(String entryId) async {
    final entries = await loadEntries();
    final idx = entries.indexWhere((e) => e.id == entryId);
    if (idx < 0) throw Exception('回收站条目不存在: $entryId');

    final entry = entries[idx];
    final trashFile = File('${_rootDir.path}/${entry.fileName}');
    if (!await trashFile.exists()) {
      throw Exception('回收站文件已丢失: ${entry.fileName}');
    }

    // 恢复文件到原始路径
    final targetFile = File(entry.originalPath);
    // 如果目标已存在，添加后缀
    var finalPath = entry.originalPath;
    if (await targetFile.exists()) {
      final base = entry.originalPath.replaceAll('.md', '');
      finalPath = '${base}_restored.md';
    }
    await trashFile.copy(finalPath);
    await trashFile.delete();

    entries.removeAt(idx);
    await _saveEntries(entries);

    return finalPath;
  }

  /// 永久删除回收站条目
  Future<void> permanentlyDelete(String entryId) async {
    final entries = await loadEntries();
    final idx = entries.indexWhere((e) => e.id == entryId);
    if (idx < 0) return;

    final entry = entries[idx];
    final trashFile = File('${_rootDir.path}/${entry.fileName}');
    if (await trashFile.exists()) {
      await trashFile.delete();
    }

    entries.removeAt(idx);
    await _saveEntries(entries);
  }

  /// 批量永久删除
  Future<void> permanentlyDeleteBatch(List<String> entryIds) async {
    for (final id in entryIds) {
      await permanentlyDelete(id);
    }
  }

  /// 清空回收站
  Future<int> emptyTrash() async {
    int count = 0;
    final entries = await loadEntries();
    for (final entry in entries) {
      final trashFile = File('${_rootDir.path}/${entry.fileName}');
      if (await trashFile.exists()) {
        await trashFile.delete();
        count++;
      }
    }
    await _saveEntries([]);
    return count;
  }

  /// 获取回收站条目数量
  Future<int> get count async {
    final entries = await loadEntries();
    return entries.length;
  }

  /// 自动清理超过指定天数的条目
  Future<int> autoClean(int daysToKeep) async {
    final entries = await loadEntries();
    final cutoff = DateTime.now().subtract(Duration(days: daysToKeep));
    final toDelete = entries.where((e) => e.deletedAt.isBefore(cutoff)).toList();
    for (final entry in toDelete) {
      await permanentlyDelete(entry.id);
    }
    return toDelete.length;
  }
}