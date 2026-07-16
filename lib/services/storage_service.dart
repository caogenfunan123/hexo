import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/article.dart';
import '../models/repo_config.dart';

/// 本地 JSON 持久化：优先 MethodChannel 应用目录，失败则用临时目录。
class StorageService {
  static const _channel = MethodChannel('hexo/native');
  static const _settingsFile = 'settings.json';
  static const _reposFile = 'repos.json';
  static const _draftsFile = 'drafts.json';

  Directory? _root;

  Future<Directory> get root async {
    if (_root != null) return _root!;
    try {
      final path = await _channel.invokeMethod<String>('getFilesDir');
      if (path != null && path.isNotEmpty) {
        _root = Directory(path);
        if (!await _root!.exists()) await _root!.create(recursive: true);
        return _root!;
      }
    } catch (_) {}
    _root = Directory('${Directory.systemTemp.path}/hexo_blog_manager');
    if (!await _root!.exists()) await _root!.create(recursive: true);
    return _root!;
  }

  Future<File> _file(String name) async => File('${(await root).path}/$name');

  Future<Map<String, dynamic>> _readMap(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return {};
      final text = await f.readAsString();
      if (text.trim().isEmpty) return {};
      final data = jsonDecode(text);
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {}
    return {};
  }

  Future<List<dynamic>> _readList(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return [];
      final text = await f.readAsString();
      if (text.trim().isEmpty) return [];
      final data = jsonDecode(text);
      if (data is List) return data;
    } catch (_) {}
    return [];
  }

  Future<void> _write(String name, Object data) async {
    final f = await _file(name);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  Future<AppSettings> loadSettings() async {
    final m = await _readMap(_settingsFile);
    return AppSettings.fromJson(m);
  }

  Future<void> saveSettings(AppSettings s) => _write(_settingsFile, s.toJson());

  Future<List<RepoConfig>> loadRepos() async {
    final list = await _readList(_reposFile);
    return list
        .whereType<Map>()
        .map((e) => RepoConfig.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveRepos(List<RepoConfig> repos) =>
      _write(_reposFile, repos.map((e) => e.toJson()).toList());

  Future<List<Article>> loadDrafts() async {
    final list = await _readList(_draftsFile);
    return list
        .whereType<Map>()
        .map((e) => Article.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveDrafts(List<Article> drafts) =>
      _write(_draftsFile, drafts.map((e) => e.toJson()).toList());

  Future<Directory> draftsDir() async {
    final d = Directory('${(await root).path}/drafts_md');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> exportDraftMarkdown(Article a) async {
    final dir = await draftsDir();
    final f = File('${dir.path}/${a.id}_${a.fileName()}');
    await f.writeAsString(a.toMarkdownWithFrontMatter());
  }
}
