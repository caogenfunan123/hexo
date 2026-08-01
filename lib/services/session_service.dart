import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/session_state.dart';

/// 会话持久化服务：APP 被杀后台后恢复上次页面状态
class SessionService {
  static const _fileName = 'session.json';
  static const _autoSaveDir = 'auto_save';

  SessionState _cached = SessionState.empty;

  SessionState get current => _cached;

  /// 获取会话文件路径
  Future<File> _sessionFile() async {
    final dir = await _baseDir();
    return File('${dir.path}/$_fileName');
  }

  /// 获取自动保存目录
  Future<Directory> _autoSaveDirectory() async {
    final dir = await _baseDir();
    final d = Directory('${dir.path}/$_autoSaveDir');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Directory> _baseDir() async {
    // 使用应用文档目录
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/tmp';
    final dir = Directory('$home/.hexo_app');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 保存当前会话快照
  Future<void> saveSession(SessionState state) async {
    _cached = state;
    try {
      final f = await _sessionFile();
      await f.writeAsString(state.toJsonString());
    } catch (_) {
      // 静默失败
    }
  }

  /// 读取上次会话快照
  Future<SessionState> loadSession() async {
    try {
      final f = await _sessionFile();
      if (!await f.exists()) return SessionState.empty;
      final content = await f.readAsString();
      _cached = SessionState.fromJsonString(content);
      return _cached;
    } catch (_) {
      return SessionState.empty;
    }
  }

  /// 清除会话（用户手动退出文章时调用）
  Future<void> clearSession() async {
    _cached = SessionState.empty;
    try {
      final f = await _sessionFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 保存自动保存草稿快照
  Future<String> saveAutoSnapshot({
    required String articleId,
    required String content,
    required String title,
    String tags = '',
    String categories = '',
    String cover = '',
  }) async {
    final dir = await _autoSaveDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${articleId}_$ts.md';
    final f = File('${dir.path}/$fileName');

    final buffer = StringBuffer();
    buffer.writeln('---');
    buffer.writeln('id: $articleId');
    buffer.writeln('title: "$title"');
    if (tags.isNotEmpty) buffer.writeln('tags: [$tags]');
    if (categories.isNotEmpty) buffer.writeln('categories: [$categories]');
    if (cover.isNotEmpty) buffer.writeln('cover: $cover');
    buffer.writeln('auto_saved_at: ${DateTime.now().toIso8601String()}');
    buffer.writeln('---');
    buffer.writeln(content);

    await f.writeAsString(buffer.toString());
    return f.path;
  }

  /// 获取文章的所有自动保存快照，按时间倒序
  Future<List<AutoSaveSnapshot>> listSnapshots(String articleId) async {
    final dir = await _autoSaveDirectory();
    if (!await dir.exists()) return [];

    final result = <AutoSaveSnapshot>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.md')) {
        final name = entity.path.split('/').last.replaceAll('.md', '');
        final parts = name.split('_');
        if (parts.length >= 2 && parts[0] == articleId) {
          final ts = int.tryParse(parts.last) ?? 0;
          result.add(AutoSaveSnapshot(
            path: entity.path,
            articleId: articleId,
            timestamp: ts,
          ));
        }
      }
    }
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  /// 读取指定快照内容
  Future<String> readSnapshotContent(String path) async {
    final f = File(path);
    if (!await f.exists()) return '';
    return await f.readAsString();
  }

  /// 清理旧快照，只保留最近 N 个
  Future<void> cleanupSnapshots(String articleId, {int keep = 20}) async {
    final snapshots = await listSnapshots(articleId);
    if (snapshots.length <= keep) return;
    for (final s in snapshots.skip(keep)) {
      try {
        final f = File(s.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// 获取自动保存目录路径
  Future<String> autoSaveDirPath() async {
    final dir = await _autoSaveDirectory();
    return dir.path;
  }
}

class AutoSaveSnapshot {
  final String path;
  final String articleId;
  final int timestamp;

  const AutoSaveSnapshot({
    required this.path,
    required this.articleId,
    required this.timestamp,
  });

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp);
}