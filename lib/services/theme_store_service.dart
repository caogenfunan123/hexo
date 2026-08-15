import 'dart:convert';
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
      screenshotUrl: 'https://raw.githubusercontent.com/next-theme/hexo-theme-next/master/images/schemes.png',
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

  Future<List<int>> _download(String url) async {
    final resp = await http.get(Uri.parse(url))
        .timeout(_downloadTimeout);
    if (resp.statusCode != 200) {
      throw Exception('下载主题包失败 (HTTP ${resp.statusCode})');
    }
    return resp.bodyBytes;
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
  String? _findRootDir(Archive archive) {
    if (archive.files.isEmpty) return null;
    final first = archive.files.first.name;
    final idx = first.indexOf('/');
    return idx > 0 ? first.substring(0, idx) : null;
  }

  /// 去掉顶层目录前缀
  String? _stripRoot(String name, String root) {
    if (name.startsWith('$root/')) {
      return name.substring(root.length + 1);
    }
    if (name == root) return '';
    return null;
  }

  /// 过滤示例内容与文档（避免主题仓库夹带无关文件）
  bool _isExcluded(String rel) {
    final lower = rel.toLowerCase();
    if (lower.startsWith('.git')) return true;
    if (lower.startsWith('.github')) return true;
    if (lower.startsWith('docs/') ||
        lower.startsWith('doc/') ||
        lower == 'readme.md' ||
        lower.startsWith('screenshots') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif')) {
      return true;
    }
    return false;
  }

  /// 读取配置文件并改写 theme 字段；返回是否发生变更
  Future<bool> _setConfigTheme(
      RepoConfig repo, String configPath, ThemeStoreItem item) async {
    final existing = await _github.readFile(repo, configPath);
    var content = existing?['content'] ?? '';

    final newThemeValue = item.configKey;
    final String updated;
    if (content.trim().isEmpty) {
      updated = '$newThemeValue: ${item.name}\n';
    } else {
      // 处理 hugo.toml / config.toml 的 [params] 风格与 YAML 两种
      updated = _replaceThemeField(content, newThemeValue, item.name);
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

  String _replaceThemeField(String content, String key, String themeName) {
    final lines = content.split('\n');
    final buf = <String>[];
    for (final line in lines) {
      // 匹配顶层 `theme: xxx`（YAML）或 `theme = "xxx"`（TOML）
      final yamlMatch = RegExp(r'^(\s*)theme\s*:\s*(.*)$').firstMatch(line);
      final tomlMatch = RegExp(r'^(\s*)theme\s*=\s*"[^"]*"').firstMatch(line);
      if (yamlMatch != null) {
        final indent = yamlMatch.group(1) ?? '';
        buf.add('${indent}theme: $themeName');
        continue;
      }
      if (tomlMatch != null) {
        buf.add('theme = "$themeName"');
        continue;
      }
      buf.add(line);
    }
    final joined = buf.join('\n');
    // 未匹配到 theme 字段则追加
    if (joined == content) {
      return '$content\ntheme: $themeName\n';
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
