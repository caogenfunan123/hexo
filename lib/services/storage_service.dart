import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/article.dart';
import '../models/repo_config.dart';
import '../models/template_item.dart';

/// 本地 JSON 持久化：桌面端用 path_provider，移动端用 MethodChannel，失败则用临时目录。
class StorageService {
  static const _channel = MethodChannel('hexo/native');
  static const _settingsFile = 'settings.json';
  static const _reposFile = 'repos.json';
  static const _draftsFile = 'drafts.json';
  static const _templatesFile = 'templates.json';
  static const _snippetsFile = 'snippets.json';
  static const _deviceKeyFile = '.device_key';

  Directory? _root;

  Future<Directory> get root async {
    if (_root != null) return _root!;
    // 桌面端：使用 path_provider 获取应用支持目录
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        final appDir = await getApplicationSupportDirectory();
        _root = Directory('${appDir.path}/hexo_blog_manager');
        if (!await _root!.exists()) await _root!.create(recursive: true);
        return _root!;
      } catch (e) {
        debugPrint('StorageService: path_provider failed: $e');
      }
    }
    // 移动端：使用 MethodChannel 获取应用文件目录
    try {
      final path = await _channel.invokeMethod<String>('getFilesDir');
      if (path != null && path.isNotEmpty) {
        _root = Directory(path);
        if (!await _root!.exists()) await _root!.create(recursive: true);
        return _root!;
      }
    } catch (_) {}
    // 最终降级：系统临时目录
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

  // ── 模板管理 ──
  Future<List<TemplateItem>> loadTemplates() async {
    final list = await _readList(_templatesFile);
    return list
        .whereType<Map>()
        .map((e) => TemplateItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveTemplates(List<TemplateItem> templates) =>
      _write(_templatesFile, templates.map((e) => e.toJson()).toList());

  /// 加载模板（含内置预设）
  Future<List<TemplateItem>> loadAllTemplates() async {
    final saved = await loadTemplates();
    final builtin = TemplatePresets.all();
    // 合并：内置模板优先，但用户自定义覆盖同名
    final Map<String, TemplateItem> merged = {};
    for (final t in builtin) {
      merged[t.id] = t;
    }
    for (final t in saved) {
      merged[t.id] = t;
    }
    return merged.values.toList()
      ..sort((a, b) {
        if (a.isBuiltin && !b.isBuiltin) return 1;
        if (!a.isBuiltin && b.isBuiltin) return -1;
        return a.name.compareTo(b.name);
      });
  }

  // ── 片段库 ──
  Future<List<SnippetItem>> loadSnippets() async {
    final list = await _readList(_snippetsFile);
    return list
        .whereType<Map>()
        .map((e) => SnippetItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveSnippets(List<SnippetItem> snippets) =>
      _write(_snippetsFile, snippets.map((e) => e.toJson()).toList());

  // ── 设备密钥（用于云端同步加密） ──
  Future<String> loadDeviceKey() async {
    try {
      final f = await _file(_deviceKeyFile);
      if (await f.exists()) {
        final text = await f.readAsString();
        if (text.trim().isNotEmpty) return text.trim();
      }
    } catch (_) {}
    // 生成新的设备密钥
    final key = _generateDeviceKey();
    await saveDeviceKey(key);
    return key;
  }

  Future<void> saveDeviceKey(String key) async {
    final f = await _file(_deviceKeyFile);
    await f.writeAsString(key);
  }

  /// 生成一个伪随机设备密钥
  String _generateDeviceKey() {
    final r = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final s = (DateTime.now().hashCode.abs() & 0xFFFF).toRadixString(16);
    return 'hexo_${r}_$s';
  }
}

/// 自定义内容片段
class SnippetItem {
  final String id;
  final String name;
  final String content;
  final String category; // 分类：友链、公告、版权、代码块、自定义
  final DateTime createdAt;

  const SnippetItem({
    required this.id,
    required this.name,
    required this.content,
    this.category = '自定义',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'content': content,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SnippetItem.fromJson(Map<String, dynamic> j) => SnippetItem(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        content: j['content']?.toString() ?? '',
        category: j['category']?.toString() ?? '自定义',
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );

  SnippetItem copyWith({
    String? id,
    String? name,
    String? content,
    String? category,
    DateTime? createdAt,
  }) {
    return SnippetItem(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
