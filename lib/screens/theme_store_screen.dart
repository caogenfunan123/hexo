import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/ai/ai_session_manager.dart';
import '../core/ai/theme_migration_service.dart';
import '../models/app_settings.dart';
import '../models/repo_config.dart';
import '../models/theme_store_item.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import '../services/theme_store_service.dart';
import '../services/version_snapshot_service.dart';
import 'theme_migration_screen.dart';

/// 主题商店：浏览内置精选主题并一键安装到建站仓库
///
/// 三个入口：
/// - 「精选安装」：内置精选主题一键安装（下载 → 解压 → writeBatch → 改 config → 触发 CI）
/// - 「Hexo 官方主题」：内嵌浏览器浏览 hexo.io/themes 官方主题列表
/// - 「AI 迁移安装」：注入 AI 依赖后，任意框架主题经 AI 分析适配目标框架再写入
/// 深度定制请使用「AI 主题开发」对话。
class ThemeStoreScreen extends StatefulWidget {
  final List<RepoConfig> repos;
  final ThemeStoreService service;
  final void Function(String message)? onToast;

  // AI 迁移安装能力（可选；不注入时仅支持 Hexo 快速安装）
  final AiService? aiService;
  final GitHubService? githubService;
  final AiModelManager? modelManager;
  final AiRequestDispatcher? dispatcher;
  final ThemeMigrationService? migrationService;
  final AiSelfChecker? selfChecker;
  final AppSettings? settings;
  final StorageService? storageService;
  final VersionSnapshotService? snapshotService;
  final Future<void> Function(AppSettings)? onSettingsChanged;

  const ThemeStoreScreen({
    super.key,
    this.repos = const [],
    this.service = const ThemeStoreService(),
    this.onToast,
    this.aiService,
    this.githubService,
    this.modelManager,
    this.dispatcher,
    this.migrationService,
    this.selfChecker,
    this.settings,
    this.storageService,
    this.snapshotService,
    this.onSettingsChanged,
  });

  @override
  State<ThemeStoreScreen> createState() => _ThemeStoreScreenState();
}

class _ThemeStoreScreenState extends State<ThemeStoreScreen> {
  String? _repoId;
  String? _frameworkFilter;
  String? _installingThemeId;
  double _installProgress = 0.0;
  final Map<String, ThemeInstallResult> _results = {};

  // AI 迁移安装状态
  bool _aiMigrating = false;
  String? _aiMigrateThemeId;
  String? _aiMigrateStage;

  // Hexo 官方主题抓取
  InAppWebViewController? _officialWebCtrl;
  bool _officialLoading = true;
  bool _officialParsed = false;
  bool _officialFailed = false;
  List<ThemeStoreItem> _officialThemes = [];
  String _officialQuery = '';

  /// Hexo 官方主题列表页
  static const String officialThemesUrl = 'https://hexo.io/themes/';

  /// 注入页面抓取脚本：遍历 .plugin 卡片提取主题元数据并回传 Flutter
  ///
  /// 定位依赖官方页面的 DOM 结构（plugin / plugin-name / plugin-desc /
  /// plugin-tag / plugin-screenshot-img），改版时可据此调整选择器。
  static const String _injectScrapeScript = r'''
(function () {
  const out = [];
  const cards = document.querySelectorAll('.plugin');
  for (const li of cards) {
    const nameEl = li.querySelector('.plugin-name');
    if (!nameEl) continue;
    const href = (nameEl.getAttribute('href') || '').trim();
    const m = href.match(/github\.com\/([^\/]+)\/([^\/?#]+)/);
    if (!m) continue;
    const name = (nameEl.textContent || '').trim();
    const img = li.querySelector('.plugin-screenshot-img');
    let shot = null;
    if (img) {
      shot = img.getAttribute('data-src') || img.getAttribute('src');
      if (shot && shot.startsWith('/')) shot = location.origin + shot;
    }
    out.push({
      owner: m[1],
      repo: m[2],
      name: name,
      desc: (li.querySelector('.plugin-desc') || {}).textContent || '',
      tags: Array.from(li.querySelectorAll('.plugin-tag')).map(function (t) {
        return (t.textContent || '').trim();
      }),
      screenshot: shot,
    });
  }
  window.flutter_inappwebview.callHandler('themeScrape', JSON.stringify(out));
  return String(out.length);
})();
''';
  @override
  void initState() {
    super.initState();
    if (widget.repos.isNotEmpty) {
      _repoId = widget.repos.first.id;
      _frameworkFilter = widget.repos.first.frameworkId;
    }
    _loadOfficialThemesCache();
  }

  /// 官方主题缓存文件路径
  Future<File> _officialCacheFile() async {
    final root = await widget.storageService!.root;
    return File('${root.path}/official_themes.json');
  }

  /// 启动时读取已固化的官方主题缓存（抓取成功过一次即可离线使用）
  Future<void> _loadOfficialThemesCache() async {
    if (widget.storageService == null) return;
    try {
      final file = await _officialCacheFile();
      if (!await file.exists()) return;
      final text = await file.readAsString();
      final list = jsonDecode(text) as List;
      final items = list
          .whereType<Map>()
          .map((e) => ThemeStoreItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (items.isEmpty || !mounted) return;
      setState(() {
        _officialThemes = items;
        _officialParsed = true;
        _officialFailed = false;
        _officialLoading = false;
      });
    } catch (e) {
      debugPrint('ThemeStore: 读取官方主题缓存失败: $e');
    }
  }

  /// 固化石墨主题抓取结果，后续启动直接读缓存，避免依赖在线抓取
  Future<void> _cacheOfficialThemes() async {
    if (widget.storageService == null || _officialThemes.isEmpty) return;
    try {
      final file = await _officialCacheFile();
      await file.writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(_officialThemes.map((t) => t.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('ThemeStore: 固化官方主题缓存失败: $e');
    }
  }

  @override
  void dispose() {
    _officialWebCtrl?.dispose();
    _officialWebCtrl = null;
    super.dispose();
  }

  List<ThemeStoreItem> get _filteredThemes =>
      ThemeStoreService.themesForFramework(_frameworkFilter);

  RepoConfig? get _selectedRepo =>
      widget.repos.where((r) => r.id == _repoId).firstOrNull;

  Future<void> _install(ThemeStoreItem item) async {
    final repo = _selectedRepo;
    if (repo == null) {
      _toast('请先选择目标站点仓库');
      return;
    }
    setState(() {
      _installingThemeId = item.id;
      _installProgress = 0.2;
    });
    try {
      final result = await widget.service.installTheme(
        repo,
        item,
        onProgress: (d, t) {
          if (mounted) {
            setState(() => _installProgress = d / t);
          }
        },
      );
      if (mounted) {
        setState(() {
          _results[item.id] = result;
          _installingThemeId = null;
          _installProgress = 1.0;
        });
      }
      _toast('主题 ${item.name} 安装完成，共写入 ${result.fileCount} 个文件，CI 构建中');
    } catch (e) {
      if (mounted) {
        setState(() => _installingThemeId = null);
      }
      _toast('安装失败: $e');
    }
  }

  void _toast(String message) {
    if (widget.onToast != null) {
      widget.onToast!(message);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  /// 是否具备 AI 迁移安装能力
  bool get _canAiMigrate =>
      widget.aiService != null &&
      widget.githubService != null &&
      widget.modelManager != null &&
      widget.dispatcher != null &&
      widget.migrationService != null &&
      widget.selfChecker != null &&
      widget.settings != null;

  /// AI 迁移安装：下载主题源码 → AI 分析源框架 → AI 迁移适配目标框架 → 写入仓库
  ///
  /// 完成后进入「AI 主题迁移」对话页，让 AI 继续审查/美化。
  Future<void> _aiMigrateInstall(ThemeStoreItem item) async {
    final repo = _selectedRepo;
    if (repo == null) {
      _toast('请先选择目标站点仓库');
      return;
    }
    if (!_canAiMigrate) {
      _toast('AI 迁移能力未初始化，请使用快速安装');
      return;
    }

    setState(() {
      _aiMigrating = true;
      _aiMigrateThemeId = item.id;
      _aiMigrateStage = '下载主题源码...';
    });

    String? tempDir;
    try {
      // 1. 下载并解压到临时目录
      tempDir = await widget.service.downloadAndExtractToTemp(item);
      final migrationService = widget.migrationService!;

      if (!mounted) return;
      setState(() => _aiMigrateStage = '分析主题结构与源框架...');

      // 2. 读取目录结构与文件内容
      final dirStructure = await migrationService.readDirectoryStructure(
        tempDir,
      );
      final sourceFiles = await migrationService.readAllTextFiles(tempDir);

      // 3. AI 分析源框架
      final sourceCodeBuffer = StringBuffer();
      sourceCodeBuffer.writeln('=== 目录结构 ===');
      sourceCodeBuffer.writeln(dirStructure);
      sourceCodeBuffer.writeln('\n=== 文件内容 ===');
      for (final entry in sourceFiles.entries.take(20)) {
        final content = entry.value.length > 3000
            ? '${entry.value.substring(0, 3000)}\n... (截断)'
            : entry.value;
        sourceCodeBuffer.writeln('\n--- ${entry.key} ---');
        sourceCodeBuffer.writeln(content);
      }

      final analysis = await migrationService.analyzeSource(
        settings: widget.settings!,
        sourceCode: sourceCodeBuffer.toString(),
      );

      if (!mounted) return;
      setState(
        () => _aiMigrateStage =
            '识别到 ${analysis.sourceFrameworkName}，正在迁移为 ${repo.frameworkId}...',
      );

      // 4. 全量源码喂给 AI 做跨框架迁移
      final allSourceCode = StringBuffer();
      for (final entry in sourceFiles.entries) {
        final content = entry.value.length > 5000
            ? '${entry.value.substring(0, 5000)}\n... (截断)'
            : entry.value;
        allSourceCode.writeln('\n=== ${entry.key} ===');
        allSourceCode.writeln(content);
      }

      final themeName = _aiThemeFolderName(item);
      final migrationResult = await migrationService.migrate(
        settings: widget.settings!,
        sourceFramework: analysis.sourceFramework,
        targetFramework: repo.frameworkId,
        sourceCode: allSourceCode.toString(),
        themeName: themeName,
      );

      // 5. 自检
      String? selfCheckNote;
      if (migrationResult.files.isNotEmpty) {
        setState(() => _aiMigrateStage = '自动检测迁移产物...');
        final checkResult = await widget.selfChecker!.check(
          settings: widget.settings!,
          generatedContent: migrationResult.rawOutput,
          sessionType: AiSessionType.themeMigration,
          blogFramework: repo.frameworkId,
        );
        if (checkResult.hasError) {
          selfCheckNote = '⚠️ 自检发现问题：\n${checkResult.issues.join('\n')}';
        } else {
          selfCheckNote = '✅ ${checkResult.message}';
        }
      }

      if (!mounted) return;
      setState(
        () => _aiMigrateStage = '写入 ${migrationResult.files.length} 个文件...',
      );

      // 6. 迁移前快照
      if (widget.snapshotService != null) {
        try {
          await widget.snapshotService!.createSnapshot(
            'theme_store_${DateTime.now().millisecondsSinceEpoch}',
            '主题商店迁移前快照：${item.name} → ${repo.frameworkId}',
            allSourceCode.toString(),
          );
        } catch (e) {
          debugPrint('ThemeStore snapshot error: $e');
        }
      }

      // 7. 逐文件写入仓库
      var wrote = 0;
      for (final file in migrationResult.files) {
        await widget.githubService!.putRawFile(
          repo,
          file.path,
          file.content,
          commitMessage:
              'theme: install ${item.name} (AI migrate) - ${file.path}',
        );
        wrote++;
      }

      // 8. 写入成功 → 记录结果并清理临时目录
      _results[item.id] = ThemeInstallResult(
        themeName: themeName,
        fileCount: wrote,
        configChanged: false,
        configPath: 'themes/$themeName/',
      );

      if (!mounted) return;
      setState(() {
        _aiMigrating = false;
        _aiMigrateThemeId = null;
        _aiMigrateStage = null;
      });

      // 9. 打开 AI 主题迁移对话，让 AI 继续审查/美化
      _openMigrationChat(item, repo, themeName, selfCheckNote);
    } catch (e) {
      debugPrint('AI migrate install error: $e');
      if (mounted) {
        setState(() {
          _aiMigrating = false;
          _aiMigrateThemeId = null;
          _aiMigrateStage = null;
        });
      }
      _toast('AI 迁移安装失败: $e');
    } finally {
      if (tempDir != null) {
        try {
          final dir = Directory(tempDir);
          if (dir.existsSync()) {
            dir.deleteSync(recursive: true);
          }
        } catch (e) {
          debugPrint('ThemeStore temp cleanup error: $e');
        }
      }
    }
  }

  /// 打开 AI 主题迁移对话页，携带本次安装上下文
  void _openMigrationChat(
    ThemeStoreItem item,
    RepoConfig repo,
    String themeName,
    String? selfCheckNote,
  ) {
    if (!_canAiMigrate) return;
    final settings = widget.settings!;
    final frameworkName = repo.frameworkId;
    final initMsg = StringBuffer(
      '已通过 AI 迁移安装主题「${item.name}」到 '
      'themes/$themeName/（源：github.com/${item.fullName}）。\n\n'
      '已写入 ${_results[item.id]?.fileCount ?? 0} 个文件并提交。\n'
      '请帮我审查安装是否正确适配 $frameworkName，检查是否存在构建风险，'
      '并给出美化建议；如需调整可直接告诉我。',
    );
    if (selfCheckNote != null) {
      initMsg.write('\n\n自动检测结果：\n$selfCheckNote');
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThemeMigrationScreen(
          settings: settings,
          activeRepo: repo,
          repos: widget.repos,
          aiService: widget.aiService!,
          githubService: widget.githubService!,
          modelManager: widget.modelManager!,
          dispatcher: widget.dispatcher!,
          migrationService: widget.migrationService!,
          selfChecker: widget.selfChecker!,
          onSettingsChanged: widget.onSettingsChanged ?? (_) async {},
          storageService: widget.storageService,
          snapshotService: widget.snapshotService,
          initialMessage: initMsg.toString(),
        ),
      ),
    );
  }

  String _aiThemeFolderName(ThemeStoreItem item) {
    final repo = item.fullName.split('/').last;
    final name = item.name.isNotEmpty ? item.name : repo;
    final cleaned = name
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim()
        .replaceAll(RegExp(r'^-|-$'), '');
    return cleaned.isEmpty ? 'ai-${item.fullName.split('/').last}' : cleaned;
  }

  // ── Hexo 官方主题抓取 ──

  /// 从抓取到的卡片数据构建 ThemeStoreItem 列表
  List<ThemeStoreItem> _buildOfficialThemes(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    final items = <ThemeStoreItem>[];
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final owner = (raw['owner'] ?? '').toString();
      final repo = (raw['repo'] ?? '').toString();
      final name = (raw['name'] ?? '').toString();
      if (owner.isEmpty || repo.isEmpty || name.isEmpty) continue;
      final desc = (raw['desc'] ?? '').toString().trim();
      final tags = raw['tags'];
      final tagText = tags is List
          ? tags
                .map((t) => t.toString())
                .where((t) => t.isNotEmpty)
                .take(4)
                .join(' · ')
          : '';
      final screenshot = (raw['screenshot'] ?? '').toString();
      items.add(
        ThemeStoreItem(
          id: 'hexo-${owner}-$repo',
          name: name,
          description: desc.isEmpty
              ? (tagText.isEmpty ? 'Hexo 社区主题' : tagText)
              : desc,
          author: owner,
          frameworkId: 'hexo',
          repoOwner: owner,
          repoName: repo,
          defaultBranch: 'master',
          screenshotUrl: screenshot.isEmpty ? null : screenshot,
        ),
      );
    }
    return items;
  }

  /// 页面加载完成后注入抓取脚本并注册 JS handler
  void _setupOfficialScrape(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'themeScrape',
      callback: (args) {
        if (args.isEmpty) return null;
        final json = args.first?.toString() ?? '';
        if (json.isEmpty) return null;
        List<ThemeStoreItem> items;
        try {
          items = _buildOfficialThemes(json);
        } catch (e) {
          debugPrint('ThemeStore: 解析官方主题 JSON 失败: $e');
          if (mounted) {
            setState(() {
              _officialLoading = false;
              _officialFailed = true;
            });
          }
          return null;
        }
        if (!mounted) return null;
        setState(() {
          _officialThemes = items;
          _officialParsed = true;
          _officialLoading = false;
        });
        // 抓取成功即固化缓存，后续启动直接读缓存
        _cacheOfficialThemes();
        if (items.isEmpty) {
          _toast('未抓取到主题数据，已回退浏览模式');
        }
        return null;
      },
    );
  }

  /// 触发抓取（在 onLoadStop / 手动重试时调用）
  Future<void> _scrapeOfficialThemes() async {
    final ctrl = _officialWebCtrl;
    if (ctrl == null) return;
    try {
      await ctrl.evaluateJavascript(source: _injectScrapeScript);
      // 等待 JS handler 回传；若脚本执行但未触发 handler，则进入回退
      if (!mounted) return;
      _startParseTimeout();
    } catch (e) {
      debugPrint('ThemeStore: 注入抓取脚本失败: $e');
      if (mounted) {
        setState(() {
          _officialLoading = false;
          _officialFailed = true;
        });
      }
    }
  }

  void _startParseTimeout() {
    Future.delayed(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_officialParsed || _officialFailed) return;
      setState(() {
        _officialLoading = false;
        _officialFailed = true;
      });
    });
  }

  void _retryOfficialScrape() {
    setState(() {
      _officialLoading = true;
      _officialParsed = false;
      _officialFailed = false;
      _officialThemes = [];
    });
    // 重建 loading 态 webview，onLoadStop 会自动重新注入抓取脚本
    _officialWebCtrl?.dispose();
    _officialWebCtrl = null;
  }

  /// 官方主题搜索过滤
  List<ThemeStoreItem> get _filteredOfficial {
    final q = _officialQuery.trim().toLowerCase();
    if (q.isEmpty) return _officialThemes;
    return _officialThemes.where((t) {
      return t.name.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q) ||
          t.author.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themes = _filteredThemes;
    final frameworkNames = {
      'hexo': 'Hexo',
      'hugo': 'Hugo',
      'jekyll': 'Jekyll',
      'astro': 'Astro',
    };

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('主题商店'),
          actions: [
            IconButton(
              icon: const Icon(Icons.palette_outlined),
              tooltip: '需要深度定制？用 AI 主题开发',
              onPressed: _toast != null
                  ? () => _toast('深度定制请使用「AI 主题开发」对话')
                  : null,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '精选安装', icon: Icon(Icons.install_desktop, size: 18)),
              Tab(text: '官方主题', icon: Icon(Icons.language, size: 18)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1：精选安装
            Column(
              children: [
                // 仓库选择 + 框架筛选
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.repos.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _repoId,
                          decoration: const InputDecoration(
                            labelText: '目标站点仓库',
                            prefixIcon: Icon(Icons.storage_outlined),
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: widget.repos
                              .map(
                                (r) => DropdownMenuItem(
                                  value: r.id,
                                  child: Text('${r.name} (${r.fullName})'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() {
                            _repoId = v;
                            final r = widget.repos
                                .where((x) => x.id == v)
                                .firstOrNull;
                            _frameworkFilter =
                                r?.frameworkId ?? _frameworkFilter;
                          }),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '尚未配置站点仓库，请先到「站点管理」创建并同步仓库',
                            style: TextStyle(color: cs.onErrorContainer),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('全部'),
                              selected: _frameworkFilter == null,
                              onSelected: (_) =>
                                  setState(() => _frameworkFilter = null),
                            ),
                            for (final fw in [
                              'hexo',
                              'hugo',
                              'jekyll',
                              'astro',
                            ])
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: ChoiceChip(
                                  label: Text(frameworkNames[fw] ?? fw),
                                  selected: _frameworkFilter == fw,
                                  onSelected: (_) =>
                                      setState(() => _frameworkFilter = fw),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Divider(height: 1),
                // 主题列表
                Expanded(
                  child: themes.isEmpty
                      ? Center(
                          child: Text(
                            '暂无可安装的主题',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.6),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: themes.length,
                          itemBuilder: (context, i) =>
                              _buildThemeCard(cs, themes[i]),
                        ),
                ),
              ],
            ),
            // Tab 2：Hexo 官方主题
            _buildOfficialTab(cs),
          ],
        ),
      ),
    );
  }

  /// Hexo 官方主题 Tab：抓取成功渲染本地卡片流，失败回退只读 webview
  Widget _buildOfficialTab(ColorScheme cs) {
    if (_officialLoading) {
      return _buildOfficialLoading(cs);
    }
    if (_officialFailed) {
      return _buildOfficialWebFallback(cs);
    }
    if (_officialParsed) {
      return _buildOfficialList(cs);
    }
    // 初始态（webview 尚未加载完成）
    return _buildOfficialLoading(cs);
  }

  Widget _buildOfficialLoading(ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '正在从 hexo.io/themes 加载官方主题列表...',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
                ),
              ),
              TextButton(
                onPressed: _retryOfficialScrape,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(officialThemesUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              supportZoom: false,
            ),
            onWebViewCreated: (controller) {
              _officialWebCtrl = controller;
              _setupOfficialScrape(controller);
            },
            onLoadStop: (controller, url) => _scrapeOfficialThemes(),
            onReceivedError: (controller, request, error) {
              if (!mounted) return;
              setState(() {
                _officialLoading = false;
                _officialFailed = true;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOfficialList(ColorScheme cs) {
    final items = _filteredOfficial;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            onChanged: (v) => setState(() => _officialQuery = v),
            decoration: InputDecoration(
              hintText: '搜索官方主题（${_officialThemes.length} 个）...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _officialQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _officialQuery = ''),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    '未找到匹配的主题',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _buildThemeCard(cs, items[i]),
                ),
        ),
      ],
    );
  }

  /// 抓取失败兜底：只读浏览官方列表页
  Widget _buildOfficialWebFallback(ColorScheme cs) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          color: cs.errorContainer.withOpacity(0.3),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: cs.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '自动抓取失败，已切换为浏览模式',
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: _retryOfficialScrape,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(officialThemesUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              supportZoom: false,
            ),
            onWebViewCreated: (controller) => _officialWebCtrl = controller,
            onReceivedError: (controller, request, error) {},
          ),
        ),
      ],
    );
  }

  Widget _buildThemeCard(ColorScheme cs, ThemeStoreItem item) {
    final result = _results[item.id];
    final installing = _installingThemeId == item.id;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 截图缩略占位
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: item.screenshotUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        item.screenshotUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.palette_outlined,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    )
                  : Icon(Icons.palette_outlined, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.frameworkId,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${item.author} · ${item.fullName}',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (installing)
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '安装中 ${(_installProgress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(fontSize: 12, color: cs.primary),
                        ),
                      ],
                    )
                  else if (_aiMigrateThemeId == item.id)
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI 迁移中 · ${_aiMigrateStage ?? '准备中...'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cs.primary),
                          ),
                        ),
                      ],
                    )
                  else if (result != null)
                    Text(
                      '已安装 · 写入 ${result.fileCount} 文件'
                      '${result.configChanged ? ' · config 已切换' : ''}',
                      style: TextStyle(fontSize: 12, color: cs.primary),
                    )
                  else
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('安装'),
                          onPressed: _installingThemeId != null || _aiMigrating
                              ? null
                              : () => _install(item),
                        ),
                        if (_canAiMigrate) ...[
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.auto_fix_high, size: 18),
                            label: const Text('AI 迁移安装'),
                            onPressed:
                                _installingThemeId != null || _aiMigrating
                                ? null
                                : () => _aiMigrateInstall(item),
                          ),
                        ],
                        const SizedBox(width: 8),
                        if (_selectedRepo != null)
                          Text(
                            _selectedRepo!.frameworkId == item.frameworkId
                                ? ''
                                : _canAiMigrate
                                ? '将适配为 ${_selectedRepo!.frameworkId}'
                                : '与当前站点框架 ${_selectedRepo!.frameworkId} 不匹配',
                            style: TextStyle(
                              fontSize: 11,
                              color: _canAiMigrate
                                  ? cs.tertiary
                                  : cs.onSurface.withOpacity(0.5),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
