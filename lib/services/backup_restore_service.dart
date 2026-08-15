import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 备份文件清单：storage root 下的核心数据文件。
const List<String> backupCoreFiles = [
  'settings.json',
  'repos.json',
  'drafts.json',
  'templates.json',
  'snippets.json',
  'writing_stats.json',
];

/// 备份恢复服务：将本地全部数据（配置/仓库/草稿/模板/片段/站点/写作统计）打包为
/// 单个 JSON 存档，支持导出到文件与从存档恢复。
///
/// 存档结构：
/// ```json
/// {
///   "version": 1,
///   "app": "HexoBlogManager",
///   "exportedAt": "2026-08-15T...",
///   "files": { "settings.json": "<base64>", "sites/xxx/tasks/task_1.json": "<base64>" }
/// }
/// ```
class BackupRestoreService {
  final Directory root;

  BackupRestoreService(this.root);

  static const int _version = 1;

  /// 导出全部数据为存档字节。
  Future<Uint8List> exportAll() async {
    final files = <String, String>{};

    // 1. 核心配置文件
    for (final name in backupCoreFiles) {
      final f = File('${root.path}/$name');
      if (await f.exists()) {
        files[name] = base64Encode(await f.readAsBytes());
      }
    }

    // 2. 站点目录（sites/ 下的任务、附件等）
    await _collectDirectory(
        Directory('${root.path}/sites'), 'sites', files,
        excludeNames: const {});

    // 3. 任务索引
    final taskIndex = File('${root.path}/task_index.json');
    if (await taskIndex.exists()) {
      files['task_index.json'] = base64Encode(await taskIndex.readAsBytes());
    }

    final bundle = {
      'version': _version,
      'app': 'HexoBlogManager',
      'exportedAt': DateTime.now().toIso8601String(),
      'files': files,
    };
    return Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(bundle)));
  }

  /// 恢复存档。`overwrite` 为 true 时覆盖现有文件。
  Future<BackupRestoreResult> restore(Uint8List bytes,
      {bool overwrite = true}) async {
    final missing = <String>[];
    Map<String, dynamic> bundle;
    try {
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map) return BackupRestoreResult(restored: 0, errors: ['存档格式无效']);
      bundle = Map<String, dynamic>.from(data);
    } catch (e) {
      return BackupRestoreResult(restored: 0, errors: ['无法解析存档: $e']);
    }

    final version = (bundle['version'] as num?)?.toInt() ?? 1;
    if (version > _version) {
      return BackupRestoreResult(
          restored: 0,
          errors: ['存档版本过高（$version），当前应用仅支持 v$_version']);
    }

    final filesRaw = bundle['files'];
    if (filesRaw is! Map) {
      return BackupRestoreResult(restored: 0, errors: ['存档缺少 files 字段']);
    }
    final files = filesRaw.map((k, v) => MapEntry(k.toString(), v?.toString()));

    int restored = 0;
    final errors = <String>[];
    for (final entry in files.entries) {
      final rel = entry.key;
      // 安全校验：禁止路径穿越
      if (rel.contains('..') || rel.startsWith('/') || rel.startsWith('\\')) {
        errors.add('跳过非法路径: $rel');
        continue;
      }
      try {
        final data = base64Decode(entry.value);
        final dest = File('${root.path}/$rel');
        if (!overwrite && await dest.exists()) {
          missing.add(rel);
          continue;
        }
        await dest.create(recursive: true);
        await dest.writeAsBytes(data, flush: true);
        restored++;
      } catch (e) {
        errors.add('恢复 $rel 失败: $e');
      }
    }

    return BackupRestoreResult(
      restored: restored,
      errors: errors,
      skipped: missing,
    );
  }

  /// 递归收集目录文件到 map，可选排除子目录/文件名。
  Future<void> _collectDirectory(
      Directory dir, String prefix, Map<String, String> out,
      {Set<String> excludeNames = const {}}) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      try {
        final name = entity.uri.pathSegments.last;
        if (excludeNames.contains(name)) continue;
        final rel = '$prefix/$name';
        if (entity is Directory) {
          await _collectDirectory(entity, rel, out,
              excludeNames: excludeNames);
        } else if (entity is File) {
          // 跳过临时文件与超大门槛（> 20MB）
          if (name.endsWith('.tmp') || name.endsWith('.bak')) continue;
          final stat = await entity.stat();
          if (stat.size > 20 * 1024 * 1024) continue;
          out[rel] = base64Encode(await entity.readAsBytes());
        }
      } catch (e) {
        debugPrint('BackupRestoreService: 收集 ${entity.path} 失败: $e');
      }
    }
  }
}

/// 恢复结果
class BackupRestoreResult {
  final int restored;
  final List<String> errors;
  final List<String> skipped;

  const BackupRestoreResult({
    this.restored = 0,
    this.errors = const [],
    this.skipped = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
}
