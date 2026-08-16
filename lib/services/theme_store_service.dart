import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/git_provider.dart';
import '../models/repo_config.dart';
import '../models/theme_store_item.dart';
import 'git_providers.dart';

/// 主题商店服务
///
/// 内置精选主题索引（不内置主题包）。安装流程：
/// 1. codeload 下载源仓库 tar.gz
/// 2. GZip + Tar 解压，定位顶层目录
/// 3. writeBatch 一次性写入仓库 themes/<name>/
/// 4. 读 _config.yml 并改写 theme 字段
/// 5. 写回 config，触发一次 CI 构建
class ThemeStoreService {
  const ThemeStoreService({GitHubProvider? githubProvider})
    : _github = githubProvider ?? const GitHubProvider();

  final GitHubProvider _github;

  /// 下载超时
  static const _downloadTimeout = Duration(seconds: 60);

  /// 内置精选主题索引
  static const List<ThemeStoreItem> builtinThemes = [
    ThemeStoreItem(
      id: 'hexo-next',
      name: 'NexT',
      description: 'Hexo 最流行的简洁主题，支持暗色模式、数学公式、多语言',
      author: 'theme-next',
      frameworkId: 'hexo',
      repoOwner: 'next-theme',
      repoName: 'hexo-theme-next',
      defaultBranch: 'master',
      screenshotUrl:
          'https://raw.githubusercontent.com/next-theme/hexo-theme-next/master/images/schemes.png',
    ),
    ThemeStoreItem(
      id: 'hexo-fluid',
      name: 'Fluid',
      description: 'Hexo 清爽主题，Material Design 风格，支持暗色模式',
      author: 'Fluid-dev',
      frameworkId: 'hexo',
      repoOwner: 'Fluid-dev',
      repoName: 'hexo-theme-fluid',
      defaultBranch: 'master',
    ),
    ThemeStoreItem(
      id: 'hexo-butterfly',
      name: 'Butterfly',
      description: 'Hexo 多功能主题，丰富的卡片布局与自定义能力',
      author: 'jerryc127',
      frameworkId: 'hexo',
      repoOwner: 'jerryc127',
      repoName: 'hexo-theme-butterfly',
      defaultBranch: 'master',
    ),
    ThemeStoreItem(
      id: 'hexo-volantis',
      name: 'Volantis',
      description: 'Hexo 高性能主题，专注文章排版与阅读体验',
      author: 'volantis-x',
      frameworkId: 'hexo',
      repoOwner: 'volantis-x',
      repoName: 'hexo-theme-volantis',
      defaultBranch: 'master',
    ),
    ThemeStoreItem(
      id: 'hugo-stack',
      name: 'Stack',
      description: 'Hugo 卡片式主题，类博客主页设计，支持暗色模式',
      author: 'CaiJimmy',
      frameworkId: 'hugo',
      repoOwner: 'CaiJimmy',
      repoName: 'hugo-theme-stack',
      defaultBranch: 'master',
    ),
    ThemeStoreItem(
      id: 'hugo-paper',
      name: 'Paper',
      description: 'Hugo 极简主题，专注阅读，无 JavaScript 依赖',
      author: 'nanxiaobei',
      frameworkId: 'hugo',
      repoOwner: 'nanxiaobei',
      repoName: 'hugo-theme-paper',
      defaultBranch: 'master',
    ),
  ];

  /// 按框架过滤
  static List<ThemeStoreItem> themesForFramework(String? frameworkId) {
    if (frameworkId == null || frameworkId.isEmpty) return builtinThemes;
    return builtinThemes.where((t) => t.frameworkId == frameworkId).toList();
  }

  /// 安装主题到站点仓库
  ///
  /// 返回安装报告（写入文件数 / 更新后的 config 摘要）。
  Future<ThemeInstallResult> installTheme(
    RepoConfig repo,
    ThemeStoreItem item, {
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (repo.provider != GitProviderType.github) {
      throw Exception('主题安装仅支持 GitHub 仓库，当前为 ${repo.provider.name}');
    }
    if (repo.token.isEmpty) {
      throw Exception('目标仓库未配置 Token');
    }

    // 1. 下载 tar.gz
    final bytes = await _download(item.tarballUrl);

    // 2. 解压
    final archive = _extractTarGz(bytes);
    final root = _findRootDir(archive);
    if (root == null) {
      throw Exception('主题包结构异常：未找到顶层目录');
    }

    // 3. 收集主题文件（排除常见示例/文档冗余）
    final themeFiles = <({String path, List<int> data})>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final rel = _stripRoot(f.name, root);
      if (rel == null || rel.isEmpty) continue;
      if (_isExcluded(rel)) continue;
      themeFiles.add((
        path: 'themes/${item.name}/$rel',
        data: Uint8List.fromList(f.content as List<int>),
      ));
    }
    if (themeFiles.isEmpty) {
      throw Exception('主题包为空，无法安装');
    }

    // 4. 一次性写入 themes/<name>/
    await _github.writeBatch(
      repo,
      themeFiles.map((f) => (path: f.path, bytes: f.data)).toList(),
      message: 'feat: install theme ${item.name} from ${item.fullName}',
      authorName: 'Hexo Blog Manager',
    );

    // 5. 改写 _config.yml 的 theme 字段
    final configPath = repo.frameworkId == 'hugo' ? 'hugo.toml' : '_config.yml';
    final changed = await _setConfigTheme(repo, configPath, item);

    return ThemeInstallResult(
      themeName: item.name,
      fileCount: themeFiles.length,
      configChanged: changed,
      configPath: configPath,
    );
  }

  Future<List<int>> _download(String url, {bool allow404 = false}) async {
    final resp = await http.get(Uri.parse(url)).timeout(_downloadTimeout);
    if (resp.statusCode == 404 && allow404) {
      return const [];
    }
    if (resp.statusCode != 200) {
      throw Exception('下载主题包失败 (HTTP ${resp.statusCode})');
    }
    return resp.bodyBytes;
  }

  /// 下载主题包并解压到本地临时目录，返回解压后的顶层目录路径
  ///
  /// 供「AI 迁移安装」使用：拿到源码后由 AI 分析并适配目标框架。
  Future<String> downloadAndExtractToTemp(ThemeStoreItem item) async {
    var bytes = await _download(item.tarballUrl, allow404: true);
    var archive = _extractTarGz(bytes);

    // 默认分支不可用时回退探测 main（官方主题常默认 master，但不少仓库是 main）
    if ((bytes.isEmpty || archive.files.isEmpty) &&
        item.defaultBranch != 'main') {
      try {
        final mainUrl =
            'https://codeload.github.com/${item.repoOwner}/'
            '${item.repoName}/tar.gz/refs/heads/main';
        bytes = await _download(mainUrl, allow404: true);
        archive = _extractTarGz(bytes);
      } catch (e) {
        debugPrint('ThemeStore: main 分支回退失败: $e');
      }
    }

    if (bytes.isEmpty) {
      throw Exception('主题包下载失败：默认分支与 main 均不可用');
    }

    final root = _findRootDir(archive);
    if (root == null) {
      throw Exception('主题包结构异常：未找到顶层目录');
    }
    final tempDir =
        '${Directory.systemTemp.path}/theme_store_${DateTime.now().millisecondsSinceEpoch}';
    final dest = Directory(tempDir);
    if (await dest.exists()) {
      await dest.delete(recursive: true);
    }
    await dest.create(recursive: true);
    final base = Directory('$tempDir/$root');
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    var wrote = 0;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final rel = _stripRoot(f.name, root);
      if (rel == null || rel.isEmpty) continue;
      final out = File('$tempDir/$root/$rel');
      try {
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>, flush: true);
        wrote++;
      } catch (_) {
        // 跳过无法写入的文件
      }
    }
    if (wrote == 0) {
      throw Exception('主题包为空，无法安装');
    }
    return '$tempDir/$root';
  }

  /// GZip + Tar 解压
  Archive _extractTarGz(List<int> bytes) {
    try {
      final gz = GZipDecoder().decodeBytes(bytes);
      return TarDecoder().decodeBytes(gz);
    } catch (e) {
      debugPrint('ThemeStore: tar.gz 解压失败: $e');
      rethrow;
    }
  }

  /// 找出 tarball 顶层目录名（如 next-theme-hexo-theme-next-master/）
  ///
  /// 要求所有文件共享同一顶层目录前缀，否则返回 null（避免混合结构包
  /// 只安装一部分导致"安装成功但文件不全"）。
  String? _findRootDir(Archive archive) {
    if (archive.files.isEmpty) return null;
    final roots = <String>{};
    for (final f in archive.files) {
      final name = f.name;
      final idx = name.indexOf('/');
      if (idx <= 0) {
        // 存在无目录前缀的顶层文件 → 结构不规则
        return null;
      }
      roots.add(name.substring(0, idx));
      if (roots.length > 1) return null;
    }
    return roots.isEmpty ? null : roots.first;
  }

  /// 去掉顶层目录前缀；对非法路径（穿越/绝对/空段）返回 null
  String? _stripRoot(String name, String root) {
    final String rel;
    if (name.startsWith('$root/')) {
      rel = name.substring(root.length + 1);
    } else if (name == root) {
      rel = '';
    } else {
      return null;
    }
    // 安全校验：拒绝路径穿越、绝对路径、Windows 分隔符与空路径
    if (rel.isEmpty) return null;
    if (rel.contains('..') ||
        rel.startsWith('/') ||
        rel.startsWith('\\') ||
        rel.contains('\\') ||
        rel.contains('//')) {
      return null;
    }
    return rel;
  }

  /// 过滤示例内容与文档（避免主题仓库夹带无关文件）
  ///
  /// 仅排除 screenshots/screenshot 目录下的图片与常见文档，保留主题自身资源图。
  bool _isExcluded(String rel) {
    final lower = rel.toLowerCase();
    if (lower.startsWith('.git')) return true;
    if (lower.startsWith('.github')) return true;
    if (lower.startsWith('docs/') ||
        lower.startsWith('doc/') ||
        lower == 'readme.md') {
      return true;
    }
    final isScreenshot =
        lower.startsWith('screenshots/') || lower.startsWith('screenshot/');
    if (isScreenshot &&
        (lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.gif'))) {
      return true;
    }
    return false;
  }

  /// 读取配置文件并改写 theme 字段；返回是否发生变更
  Future<bool> _setConfigTheme(
    RepoConfig repo,
    String configPath,
    ThemeStoreItem item,
  ) async {
    final existing = await _github.readFile(repo, configPath);
    var content = existing?['content'] ?? '';

    final newThemeValue = item.configKey;
    // 依据配置文件后缀区分 YAML（Hexo _config.yml）与 TOML（Hugo hugo.toml/config.toml）
    final isToml = configPath.endsWith('.toml');
    final String updated;
    if (content.trim().isEmpty) {
      updated = isToml ? 'theme = "${item.name}"\n' : 'theme: ${item.name}\n';
    } else {
      updated = _replaceThemeField(content, newThemeValue, item.name, isToml);
    }
    if (updated == content) return false;

    await _github.writeFile(
      repo,
      configPath,
      utf8.encode(updated),
      sha: existing?['sha'],
      message: 'chore: switch theme to ${item.name}',
    );
    return true;
  }

  String _replaceThemeField(
    String content,
    String key,
    String themeName,
    bool isToml,
  ) {
    final lines = content.split('\n');
    final buf = <String>[];
    for (final line in lines) {
      if (isToml) {
        // TOML：theme = "xxx"（单双引号均可）
        final tomlMatch = RegExp(
          "^(\\s*)theme\\s*=\\s*(\".*\"|'.*')",
        ).firstMatch(line);
        if (tomlMatch != null) {
          buf.add('theme = "$themeName"');
          continue;
        }
      } else {
        // YAML：仅匹配顶层 theme（无缩进）或保持缩进一致的字段
        final yamlMatch = RegExp(r'^(\s*)theme\s*:\s*(.*)$').firstMatch(line);
        if (yamlMatch != null) {
          final indent = yamlMatch.group(1) ?? '';
          buf.add('${indent}theme: $themeName');
          continue;
        }
      }
      buf.add(line);
    }
    final joined = buf.join('\n');
    // 未匹配到 theme 字段则追加（TOML 用合法语法）
    if (joined == content) {
      return isToml
          ? '$content\ntheme = "$themeName"\n'
          : '$content\ntheme: $themeName\n';
    }
    return joined;
  }
}

/// 主题安装结果
class ThemeInstallResult {
  final String themeName;
  final int fileCount;
  final bool configChanged;
  final String configPath;

  const ThemeInstallResult({
    required this.themeName,
    required this.fileCount,
    required this.configChanged,
    required this.configPath,
  });
}
