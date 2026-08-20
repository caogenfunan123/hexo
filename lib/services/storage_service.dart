import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';

import '../models/app_settings.dart';
import '../models/article.dart';
import '../models/repo_config.dart';
import '../models/template_item.dart';

/// 本地 JSON 持久化：桌面端用 path_provider，移动端用 MethodChannel，失败则用临时目录。
///
/// 全局统一存储目录规则：
/// - 默认使用应用私有目录
/// - 用户可在设置中选择「全局文件存储目录」，此后本地导出 MD/图片、云同步
///   上传下载、Git 拉取推送、分享临时 MD 缓存全部统一读写该目录
/// - 根目录下自动生成分类子文件夹：MD文章 / 文章长图 / 同步缓存 / Git博文 / 临时分享文件
class StorageService {
  static const _channel = MethodChannel('hexo/native');
  static const _settingsFile = 'settings.json';
  static const _reposFile = 'repos.json';
  static const _draftsFile = 'drafts.json';
  static const draftsFile = 'drafts.json';
  static const encDraftsFile = 'drafts.json.enc';
  static const _templatesFile = 'templates.json';
  static const _snippetsFile = 'snippets.json';
  static const _deviceKeyFile = '.device_key';

  // ── 全局统一存储目录分类子文件夹 ──
  static const String dirMdArticles = 'MD文章';
  static const String dirLongImages = '文章长图';
  static const String dirSyncCache = '同步缓存';
  static const String dirGitPosts = 'Git博文';
  static const String dirShareTemp = '临时分享文件';

  Directory? _root;
  String _customRoot = '';

  // ── Android SAF 自定义导出文件夹 ──
  Saf? _saf;
  String? _externalSafUri;

  /// 草稿加密钩子（由 DraftEncryptionService 注册）
  /// 保存时对明文 JSON 加密；加载时对加密 JSON 解密
  static String? Function(String plainJson)? draftsEncryptor;
  static String? Function(String encJson)? draftsDecryptor;

  /// 最近一次草稿加载的错误（如解密失败），供 UI 提示
  static String? lastDraftsError;

  /// 配置自定义全局存储根目录（空串表示重置为默认目录）
  void setCustomRoot(String path) {
    _customRoot = path.trim();
    _root = null; // 失效缓存，下次访问重建
  }

  /// 当前自定义根目录路径（未设置时为空）
  String get customRoot => _customRoot;

  // ── Android SAF 导出文件夹 ──

  /// 设置 SAF 授权目录 URI（为空清除）
  void setExternalSafUri(String? uri) {
    _externalSafUri = uri?.trim();
  }

  /// 当前 SAF 授权目录 URI（未设置时为空）
  String? get externalSafUri => _externalSafUri;

  Saf _getSaf() {
    _saf ??= Saf();
    return _saf!;
  }

  /// 唤起系统文件夹选择器，返回授权目录（含持久化权限）
  Future<SafDocumentFile?> pickExternalSafDir() async {
    return _getSaf().pickDirectory();
  }

  /// 导出内容到 SAF 授权目录，返回 true 表示成功
  Future<bool> exportToExternalSaf(String fileName, String content) async {
    if (_externalSafUri == null) return false;
    try {
      final saf = _getSaf();
      final bytes = Uint8List.fromList(utf8.encode(content));
      await saf.writeFileBytes(_externalSafUri!, fileName, 'text/markdown', bytes);
      return true;
    } catch (e) {
      debugPrint('exportToExternalSaf error: $e');
      return false;
    }
  }

  /// 从 SAF 授权目录读取文件内容，返回文本或 null
  Future<String?> importFromExternalSaf(String uri) async {
    try {
      final bytes = await _getSaf().readFileBytes(uri);
      return utf8.decode(bytes);
    } catch (e) {
      debugPrint('importFromExternalSaf error: $e');
      return null;
    }
  }

  Future<Directory> get root async {
    if (_root != null) return _root!;
    // 优先使用用户配置的全局统一存储目录
    if (_customRoot.isNotEmpty) {
      try {
        final custom = Directory(_customRoot);
        if (await custom.exists()) {
          _root = custom;
          await _ensureCategoryDirs();
          return _root!;
        }
      } catch (_) {}
    }
    // 桌面端：使用 Documents/拓墨 作为默认目录
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        final home = Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '';
        if (home.isNotEmpty) {
          final newPath = Directory('$home/Documents/拓墨');
          final oldPath = Directory('$home/.hexo_app');
          // 自动迁移：旧路径存在且新路径不存在时，
          // 优先同分区 rename（O(1) 瞬间完成，不阻塞启动）；
          // rename 失败（跨分区/设备）则后台异步复制，本会话继续使用旧路径。
          if (await oldPath.exists() && !await newPath.exists()) {
            var migrated = false;
            try {
              await newPath.parent.create(recursive: true);
              await oldPath.rename(newPath.path);
              migrated = true;
            } catch (e) {
              debugPrint('StorageService: 同分区迁移失败，改用后台复制: $e');
            }
            if (!migrated) {
              _scheduleBackgroundCopy(oldPath, newPath);
            }
          }
          if (await newPath.exists()) {
            _root = newPath;
          } else if (await oldPath.exists()) {
            // 后台迁移进行中：本会话继续使用旧路径，数据不丢
            _root = oldPath;
          } else {
            _root = newPath;
          }
          if (!await _root!.exists()) await _root!.create(recursive: true);
          await _ensureCategoryDirs();
          return _root!;
        }
      } catch (e) {
        debugPrint('StorageService: desktop root failed: $e');
      }
    }
    // 移动端：使用应用内部文件目录（保证老用户数据路径不变）
    try {
      final path = await _channel.invokeMethod<String>('getFilesDir');
      if (path != null && path.isNotEmpty) {
        _root = Directory(path);
        if (!await _root!.exists()) await _root!.create(recursive: true);
        await _ensureCategoryDirs();
        return _root!;
      }
    } catch (_) {}
    // 最终降级：系统临时目录
    _root = Directory('${Directory.systemTemp.path}/hexo_blog_manager');
    if (!await _root!.exists()) await _root!.create(recursive: true);
    await _ensureCategoryDirs();
    return _root!;
  }

  /// 在根目录自动创建分类子文件夹
  Future<void> _ensureCategoryDirs() async {
    if (_root == null) return;
    for (final name in [
      dirMdArticles,
      dirLongImages,
      dirSyncCache,
      dirGitPosts,
      dirShareTemp,
    ]) {
      final d = Directory('${_root!.path}/$name');
      if (!await d.exists()) await d.create(recursive: true);
    }
  }

  /// 自动创建分类子文件夹（供外部调用）
  Future<void> ensureCategoryDirs() async {
    await root;
    await _ensureCategoryDirs();
  }

  // ── 分类子文件夹访问器 ──

  /// MD 文章导出目录
  Future<Directory> mdArticlesDir() async {
    final d = Directory('${(await root).path}/$dirMdArticles');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 文章长图导出目录
  Future<Directory> longImagesDir() async {
    final d = Directory('${(await root).path}/$dirLongImages');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 云同步缓存目录
  Future<Directory> syncCacheDir() async {
    final d = Directory('${(await root).path}/$dirSyncCache');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Git 博文目录
  Future<Directory> gitPostsDir() async {
    final d = Directory('${(await root).path}/$dirGitPosts');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 临时分享文件目录
  Future<Directory> shareTempDir() async {
    final d = Directory('${(await root).path}/$dirShareTemp');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 一键迁移旧目录全部历史文件到当前全局根目录
  /// [oldRoot] 旧根目录路径；返回迁移的文件/目录数量
  /// [onProgress] 可选进度回调，参数为 (已处理数量, 总数量)
  Future<int> migrateFrom(String oldRoot, {void Function(int done, int total)? onProgress}) async {
    final source = Directory(oldRoot);
    if (!await source.exists()) return 0;
    final target = await root;
    if (source.path == target.path) return 0;
    var count = 0;
    final total = await _countEntities(source);
    onProgress?.call(0, total);
    await for (final entity in source.list(followLinks: false)) {
      try {
        final name = entity.uri.pathSegments.last;
        if (entity is Directory) {
          await _copyDirectory(entity, Directory('${target.path}/$name'));
          count++;
        } else if (entity is File) {
          await entity.copy('${target.path}/$name');
          count++;
        }
        onProgress?.call(count, total);
      } catch (e) {
        debugPrint('StorageService.migrateFrom skip: $e');
      }
    }
    return count;
  }

  Future<int> _countEntities(Directory dir) async {
    var n = 0;
    try {
      await for (final _ in dir.list(followLinks: false)) {
        n++;
      }
    } catch (_) {}
    return n;
  }

  Future<void> _copyDirectory(Directory src, Directory dest) async {
    if (!await dest.exists()) await dest.create(recursive: true);
    await for (final entity in src.list(followLinks: false)) {
      try {
        if (entity is Directory) {
          await _copyDirectory(entity, Directory('${dest.path}/${entity.uri.pathSegments.last}'));
        } else if (entity is File) {
          await entity.copy('${dest.path}/${entity.uri.pathSegments.last}');
        }
      } catch (e) {
        debugPrint('StorageService._copyDirectory skip: $e');
      }
    }
  }

  /// 后台异步复制旧目录到新目录（跨分区迁移兜底），不阻塞启动
  void _scheduleBackgroundCopy(Directory src, Directory dest) {
    // fire-and-forget，不在 root getter 内等待
    Future<void>(() async {
      try {
        debugPrint('StorageService: 开始后台迁移 ${src.path} -> ${dest.path}');
        await _copyDirectory(src, dest);
        debugPrint('StorageService: 后台迁移完成 ${dest.path}');
      } catch (e) {
        debugPrint('StorageService: 后台迁移失败: $e');
      }
    });
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
    } catch (e) {
      debugPrint('Storage: 读取 $name 失败（文件可能损坏），返回空配置: $e');
    }
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
    } catch (e) {
      debugPrint('Storage: 读取 $name 失败（文件可能损坏），返回空列表: $e');
    }
    return [];
  }

  Future<void> _write(String name, Object data) async {
    final f = await _file(name);
    // 临时文件 + rename 原子写入，防止崩溃留下截断文件；
    // 唯一后缀避免并发写同一文件时互相截断
    final tmp = File('${f.path}.tmp.${DateTime.now().microsecondsSinceEpoch}.${Random().nextInt(0xFFFFFF)}');
    await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data), flush: true);
    await tmp.rename(f.path);
  }

  Future<AppSettings> loadSettings() async {
    final f = await _file(_settingsFile);
    final exists = await f.exists();
    final m = await _readMap(_settingsFile);
    // 存量用户升级引导：设置文件已存在但尚无 appMode 记录 → 弹出模式选择
    final needsGuide = exists && !m.containsKey('appMode');
    return AppSettings.fromJson(m, needsModeGuide: needsGuide);
  }

  Future<void> saveSettings(AppSettings s) => _write(_settingsFile, s.toJson());

  Future<List<RepoConfig>> loadRepos() async {
    final list = await _readList(_reposFile);
    final repos = list
        .whereType<Map>()
        .map((e) => RepoConfig.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    // 迁移：强制所有仓库的 postDatePrefix 为 false（用户要求纯标题）
    bool needsSave = false;
    for (int i = 0; i < repos.length; i++) {
      final r = repos[i];
      if (r.fileNameRule.postDatePrefix || r.postDatePrefix) {
        repos[i] = r.copyWith(
          postDatePrefix: false,
          fileNameRule: FileNameRule(postDatePrefix: false, dateFormat: r.fileNameRule.dateFormat),
        );
        needsSave = true;
      }
      // 迁移：校正模板与框架不匹配的问题
      final expectedPostTpl = RepoConfig.defaultPostTemplateForFramework(r.frameworkId);
      final expectedPageTpl = RepoConfig.defaultPageTemplateForFramework(r.frameworkId);
      if (expectedPostTpl != null && r.defaultPostTemplateId != expectedPostTpl) {
        repos[i] = repos[i].copyWith(defaultPostTemplateId: expectedPostTpl);
        needsSave = true;
      }
      if (expectedPageTpl != null && r.defaultPageTemplateId != expectedPageTpl) {
        repos[i] = repos[i].copyWith(defaultPageTemplateId: expectedPageTpl);
        needsSave = true;
      }
    }
    if (needsSave) {
      await saveRepos(repos);
    }
    return repos;
  }

  Future<void> saveRepos(List<RepoConfig> repos) =>
      _write(_reposFile, repos.map((e) => e.toJson()).toList());

  Future<List<Article>> loadDrafts() async {
    // 加密开启时优先读取加密文件
    if (draftsDecryptor != null) {
      final encText = await _readRaw(encDraftsFile);
      if (encText != null && encText.trim().isNotEmpty) {
        try {
          final plain = draftsDecryptor!(encText.trim());
          if (plain != null) {
            final list = jsonDecode(plain);
            if (list is List) {
              return list
                  .whereType<Map>()
                  .map((e) => Article.fromJson(Map<String, dynamic>.from(e)))
                  .toList();
            }
          }
        } catch (e) {
          // 解密失败：不静默回退明文（加密态明文不存在或为陈旧备份，
          // 读它会掩盖"密码错误/文件损坏"这一真实状态，导致草稿静默丢失）。
          lastDraftsError = '草稿解密失败：$e';
          debugPrint('Storage: 草稿解密失败（不回退明文）: $e');
          return const [];
        }
      }
    }
    final list = await _readList(_draftsFile);
    return list
        .whereType<Map>()
        .map((e) => Article.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveDrafts(List<Article> drafts) async {
    final plain = const JsonEncoder.withIndent('  ')
        .convert(drafts.map((e) => e.toJson()).toList());
    // 加密开启时写入加密文件
    if (draftsEncryptor != null) {
      final enc = draftsEncryptor!(plain);
      if (enc != null) {
        await _writeRaw(encDraftsFile, enc);
        return;
      }
    }
    await _writeRaw(_draftsFile, plain);
  }

  /// 读取原始文件内容（不存在返回 null）
  Future<String?> _readRaw(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      return text;
    } catch (e) {
      debugPrint('Storage: 读取 $name 失败: $e');
      return null;
    }
  }

  /// 写入原始文本（原子写入）
  Future<void> _writeRaw(String name, String content) async {
    final f = await _file(name);
    final tmp = File('${f.path}.tmp.${DateTime.now().microsecondsSinceEpoch}.${Random().nextInt(0xFFFFFF)}');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(f.path);
  }

  Future<Directory> draftsDir() async {
    return mdArticlesDir();
  }

  Future<void> exportDraftMarkdown(Article a) async {
    final dir = await draftsDir();
    final f = File('${dir.path}/${_safePathSegment(a.id)}_${a.fileName()}');
    await f.writeAsString(a.toMarkdownWithFrontMatter());
  }

  /// 将文件保存到用户可见的目录
  /// 优先顺序：SAF 授权目录 → MediaStore Downloads → 内部 mdArticlesDir
  /// 返回保存后的 URI/路径，null 表示全部失败
  Future<String?> saveToUserVisibleDir(String fileName, String content) async {
    // 1. SAF 优先
    if (Platform.isAndroid && _externalSafUri != null) {
      final ok = await exportToExternalSaf(fileName, content);
      if (ok) return _externalSafUri; // SAF 目录 URI
    }
    // 2. Android: MediaStore Downloads
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final tmp = File('${(await root).path}/.tmp_${DateTime.now().millisecondsSinceEpoch}_$fileName');
        await tmp.writeAsString(content);
        final result = await _channel.invokeMethod<String>('exportFile', {
          'sourcePath': tmp.path,
          'fileName': fileName,
        });
        try { await tmp.delete(); } catch (_) {}
        return result;
      } catch (e) {
        debugPrint('StorageService.saveToUserVisibleDir error: $e');
      }
    }
    // 3. 兜底：写入内部 mdArticlesDir
    final dir = await mdArticlesDir();
    final f = File('${dir.path}/$fileName');
    await f.writeAsString(content);
    return f.path;
  }

  /// 将不可信字符串消毒为安全的单一路径段（用于文件名拼接）
  static String _safePathSegment(String input) {
    return input
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  // ── 原生悬浮速记窗 md 导入 ──

  /// 导入原生悬浮速记窗写入的 md 文件到草稿箱。
  ///
  /// 规则（与原生 NativeQuickNoteStore 约定一致）：
  /// - 只导入 {@code MD文章/} 根下以「毫秒时间戳_标题」命名、无 frontmatter、
  ///   且尚未被导入（无 {@code .md.imported} 标记）的 md 文件
  /// - 导入成功后写入 {@code .md.imported} 标记，避免重复导入
  /// - 跳过带 frontmatter（以 {@code ---} 开头）的导出/发布文件
  ///
  /// 返回新导入的草稿列表（调用方负责并入并持久化 drafts）。
  Future<List<Article>> importNativeQuickNotes() async {
    final dir = await mdArticlesDir();
    final imported = <Article>[];
    try {
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.endsWith('.md') || name.endsWith('.imported')) continue;
        final marker = File('${e.path}.imported');
        if (await marker.exists()) continue;
        String content;
        try {
          content = await e.readAsString();
        } catch (_) {
          continue;
        }
        // 带 frontmatter 的是导出/发布文件，跳过
        if (content.trimLeft().startsWith('---')) continue;
        final createdAt = _nativeMdTimestamp(name) ?? (await e.stat()).modified;
        imported.add(Article(
          id: 'native_${createdAt.millisecondsSinceEpoch}',
          title: _nativeMdTitle(name, content),
          content: content.trim(),
          createdAt: createdAt,
          updatedAt: createdAt,
          isDraft: true,
        ));
        try {
          await marker.writeAsString('imported');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Storage: 导入原生速记失败: $e');
    }
    return imported;
  }

  /// 从文件名 {@code <epochMillis>_<title>.md} 解析毫秒时间戳
  DateTime? _nativeMdTimestamp(String name) {
    final idx = name.indexOf('_');
    if (idx <= 0) return null;
    final ts = int.tryParse(name.substring(0, idx));
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }

  /// 从文件名取标题（去时间戳前缀与 .md 后缀），空则回落「速记」
  String _nativeMdTitle(String name, String content) {
    final idx = name.indexOf('_');
    var t = idx > 0 ? name.substring(idx + 1) : name;
    t = t.replaceAll(RegExp(r'\.md$'), '').trim();
    if (t.isEmpty) t = '速记';
    return t;
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
    // 合并：内置模板始终使用代码中最新版本（不被磁盘缓存覆盖）
    // 用户自定义模板（非 builtin_ 前缀 ID）正常加载
    final Map<String, TemplateItem> merged = {};
    for (final t in builtin) {
      merged[t.id] = t;
    }
    for (final t in saved) {
      // 内置模板跳过，确保使用代码中的最新版本
      if (t.id.startsWith('builtin_')) continue;
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

  /// 生成一个随机设备密钥（128-bit 熵，用于云端同步 AES-GCM 加密）
  String _generateDeviceKey() {
    final rand = Random.secure();
    final bytes = List.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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
