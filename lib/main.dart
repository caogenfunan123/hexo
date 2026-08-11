import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'controllers/controllers.dart';

import 'models/ai_profile.dart';
import 'models/app_settings.dart';
import 'models/article_type.dart';
import 'models/article.dart';
import 'models/blog_framework.dart';
import 'models/blog_site_config.dart';
import 'models/blog_post.dart';
import 'models/github_token_profile.dart';
import 'models/repo_config.dart';
import 'models/session_state.dart';
import 'models/template_item.dart';
import 'l10n/app_localizations.dart';
import 'core/ai/ai_model_manager.dart';
import 'core/ai/ai_request_dispatcher.dart';
import 'core/ai/site_dispatcher_manager.dart';
import 'core/ai/ai_self_checker.dart';
import 'core/ai/ai_session_manager.dart';
import 'core/ai/theme_migration_service.dart';
import 'core/template_engine/template_resolver.dart';
import 'screens/ai_article_chat_screen.dart';
import 'screens/ai_audit_screen.dart';
import 'screens/agent_workbench_screen.dart';
import 'screens/ai_model_manager_screen.dart';
import 'screens/ai_template_chat_screen.dart';
import 'screens/ai_theme_chat_screen.dart';
import 'screens/article_reader_screen.dart';
import 'screens/blog_site_editor_screen.dart';
import 'screens/drafts_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/remote_posts_screen.dart';
import 'screens/all_static_blogs_screen.dart';
import 'screens/static_blog_posts_screen.dart';
import 'screens/sync_screen.dart';
import 'screens/sync_settings_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/rss_screen.dart';
import 'screens/history_screen.dart';
import 'screens/folder_upload_screen.dart';
import 'screens/preview_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/site_editor_screen.dart';
import 'screens/site_management_screen.dart';
import 'screens/template_manager_screen.dart';
import 'screens/theme_migration_screen.dart';
import 'screens/tool_library_screen.dart';
import 'screens/log_screen.dart';
import 'core/tools/skill_manager.dart';
import 'core/tools/remote_cms_tools.dart';
import 'core/cancel_token.dart';
import 'core/shared_bootstrap.dart';
import 'core/site_manager.dart';
import 'core/repository/blog_repository.dart';
import 'core/repository/static_blog_repository.dart';
import 'services/ai_service.dart';
import 'services/github_service.dart';
import 'services/image_service.dart';
import 'services/rss_service.dart';
import 'services/session_service.dart';
import 'services/storage_service.dart';
import 'services/cms_draft_service.dart';
import 'services/webdav_service.dart';
import 'services/log_service.dart';
import 'services/sync_service.dart';
import 'services/cloud_sync_service.dart';
import 'services/static_blog_batch_publish_service.dart';
import 'services/template_service.dart';
import 'theme/app_theme.dart';

// ── 移动端新功能集成 ──
import 'widgets/typewriter_scroll.dart';
import 'widgets/unified_markdown_styles.dart';
import 'widgets/orientation_guard.dart';
import 'widgets/ai_selection_edit_mobile.dart';
import 'services/site_isolation_service.dart';
import 'services/p2p_sync_service.dart';
import 'screens/p2p_sync_screen.dart';
import 'services/template_sync_service.dart';
import 'services/full_text_search_isolate.dart';
import 'services/recycle_bin_service.dart';
import 'services/version_snapshot_service.dart';
import 'core/utils/word_count_util.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(HexoApp(initialSettings: loadInitialSettings()));
}

AppSettings loadInitialSettings() {
  try {
    return AppSettings.fromJson({});
  } catch (e) {
    debugPrint('Load initial settings error: $e');
    return AppSettings();
  }
}

class HexoApp extends StatefulWidget {
  final AppSettings initialSettings;
  const HexoApp({super.key, required this.initialSettings});

  @override
  State<HexoApp> createState() => _HexoAppState();
}

class _HexoAppState extends State<HexoApp> {
  late AppSettings _settings;

  // ── 控制器（全局单例，注入到 Provider 树） ──
  final DocumentController _docCtrl = DocumentController();
  final LayoutController _layoutCtrl = LayoutController();
  final EditorController _editorCtrl = EditorController();
  final SyncController _syncCtrl = SyncController();
  final SiteController _siteCtrl = SiteController();
  final FrontMatterController _frontMatterCtrl = FrontMatterController();
  final UiStateController _uiStateCtrl = UiStateController();

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  @override
  void dispose() {
    _docCtrl.dispose();
    _layoutCtrl.dispose();
    _editorCtrl.dispose();
    _syncCtrl.dispose();
    _siteCtrl.dispose();
    _frontMatterCtrl.dispose();
    _uiStateCtrl.dispose();
    super.dispose();
  }

  void updateTheme(Color c) {
    setState(() => _settings = _settings.copyWith(themeColor: c.value));
  }

  /// 接收完整的 AppSettings 更新，触发 MaterialApp 重建（DesignConfig 变化时主题实时更新）
  void updateSettings(AppSettings s) {
    setState(() => _settings = s);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _docCtrl),
        ChangeNotifierProvider.value(value: _layoutCtrl),
        ChangeNotifierProvider.value(value: _editorCtrl),
        ChangeNotifierProvider.value(value: _syncCtrl),
        ChangeNotifierProvider.value(value: _siteCtrl),
        ChangeNotifierProvider.value(value: _frontMatterCtrl),
        ChangeNotifierProvider.value(value: _uiStateCtrl),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Hexo 写作',
        locale: AppLanguage.fromCode(_settings.language).toLocale(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightFromConfig(_settings.ui.designConfig),
        darkTheme: AppTheme.darkFromConfig(_settings.ui.designConfig),
        home: RootShell(
            onThemeChanged: updateTheme,
            onSettingsChanged: updateSettings,
            initialSettings: _settings),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  final void Function(Color) onThemeChanged;
  final void Function(AppSettings)? onSettingsChanged;
  final AppSettings initialSettings;
  const RootShell(
      {super.key,
      required this.onThemeChanged,
      this.onSettingsChanged,
      required this.initialSettings});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  final storage = StorageService();
  final github = GitHubService();
  late final imageService = ImageService(github);
  final aiService = AiService();
  late final aiModelManager = AiModelManager(storage);
  late final siteDispatcherManager =
      SiteDispatcherManager(aiService, aiModelManager);
  bool _siteDispatcherManagerUsed = false;

  /// 当前站点对应的调度器（站点隔离：每个站点独立上下文）
  AiRequestDispatcher get aiDispatcher {
    _siteDispatcherManagerUsed = true;
    return siteDispatcherManager.forSite(settings.effectiveActiveSiteId);
  }
  late final themeMigrationService = ThemeMigrationService(aiService, github);
  late final aiSelfChecker = AiSelfChecker(aiService);
  final skillManager = SkillManager();
  final rssService = RssService();
  final webdavService = WebDavService();
  final sessionService = SessionService();
  final cmsDraftService = CmsDraftService();
  final logService = LogService();
  late final SyncService syncService;
  late final CloudSyncService cloudSyncService;

  /// 站点管理器：统一管理静态仓库和动态 CMS 站点
  late SiteManager siteManager;
  /// 标记 siteManager 是否已初始化（避免 dispose 时 LateInitializationError）
  bool siteManagerInitialized = false;

  AppSettings settings = const AppSettings();
  List<RepoConfig> repos = [];
  List<Article> drafts = [];
  List<GitHubFileItem> remotePosts = [];
  List<RssItem> rssItems = [];
  List<GitCommitItem> commits = [];
  List<TemplateItem> templates = [];
  List<SnippetItem> snippets = [];

  int _currentPage = 0;
  bool loading = true;
  bool busy = false;
  String? error;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _sessionRestored = false;

  // ── 自动保存（P0 修复：每草稿独立防抖 + 三重落盘） ──
  Timer? _autoSaveTimer;
  Timer? _autoSyncTimer; // 云端自动同步
  /// 每草稿独立防抖定时器，杜绝多草稿相互阻塞
  final Map<String, _DebounceEntry> _debounceTimers = {};
  /// 每草稿独立上次保存内容，切换草稿不丢失
  final Map<String, String> _lastSavedContentMap = {};

  // Editor state
  RepoConfig? _editorRepo;
  bool _editorBusy = false;
  String? _editorStatus;
  final CancelToken _publishCancelToken = CancelToken();
  Uint8List? _failedImageBytes; // 缓存上传失败的图片字节

  // ── 新功能：打字机滚动 ──
  final _editorScrollCtrl = ScrollController();
  late final TypewriterScrollController _typewriterCtrl;

  // ── 新功能：专注模式 ──
  bool _focusModeEnabled = false;

  // ── 极简编辑界面：正文首次进入显示淡提示，输入后永久隐藏 ──
  bool _contentHintDismissed = false;

  // ── 新功能：横竖屏状态保持 ──
  late final EditorStateManager _orientationManager;

  // ── 新功能：站点隔离 + P2P + 模板同步 + 全文检索 ──
  SiteIsolationService? _siteIsolation;
  late final P2PSyncService _p2pSyncService;
  TemplateSyncService? _templateSync;
  FullTextSearchIsolate? _searchIsolate;
  RecycleBinService? _recycleBin;
  VersionSnapshotService? _snapshotService;

  RepoConfig? get activeRepo {
    if (repos.isEmpty) return null;
    for (final r in repos) {
      if (r.id == settings.activeRepoId) return r;
    }
    for (final r in repos) {
      if (r.isDefault) return r;
    }
    return repos.first;
  }

  RepoConfig? get effectiveRepo {
    final r = activeRepo;
    if (r == null) return null;
    if (r.token.isNotEmpty) return r;
    final t = settings.effectiveGithubToken;
    if (t.isEmpty) return r;
    return r.copyWith(token: t);
  }

  /// 更新站点管理器（在 repos 或 settings 变更时调用）
  void _updateSiteManager() {
    // 释放旧实例，避免反复创建 SiteManager 导致适配器/HTTP 客户端泄漏
    if (siteManagerInitialized) {
      siteManager.disposeAll();
    }
    final activeId = settings.effectiveActiveSiteId;
    siteManager = SiteManager(
      staticRepos: repos,
      dynamicSites: settings.blogSiteConfigs,
      appSettings: settings,
      activeSiteId: activeId.isNotEmpty ? activeId : (activeRepo?.id ?? ''),
    );
    siteManagerInitialized = true;
    // 将站点管理器注入到工具系统
    // TODO: 这是临时方案，后续应改为依赖注入，避免设置全局静态字段
    RemoteCmsTools.siteManager = siteManager;
  }

  /// 全部动态 CMS 站点适配器（用于远程文章多站点聚合查看）
  List<BlogRepository> get _allCmsAdapters {
    final result = <BlogRepository>[];
    for (final site in siteManager.dynamicSites) {
      final adapter = siteManager.getAdapter(site.id);
      if (adapter != null) result.add(adapter);
    }
    return result;
  }

  /// 全部静态博客仓库适配器（用于远程文章多站点聚合查看）
  List<BlogRepository> get _allStaticAdapters {
    final result = <BlogRepository>[];
    for (final repo in repos) {
      result.add(StaticBlogRepository(
        repoConfig: _resolvedRepoFor(repo),
        appSettings: settings,
        githubService: github,
        logService: logService,
      ));
    }
    return result;
  }

  /// 全部站点适配器（静态博客 + 动态 CMS，用于远程文章统一聚合管理）
  List<BlogRepository> get _allSiteAdapters {
    final result = <BlogRepository>[];
    result.addAll(_allStaticAdapters);
    result.addAll(_allCmsAdapters);
    return result;
  }

  /// 解析仓库的 GitHub Token（优先仓库自身 Token，否则回退全局 Token）
  RepoConfig _resolvedRepoFor(RepoConfig repo) {
    if (repo.token.isNotEmpty) return repo;
    final t = settings.effectiveGithubToken;
    if (t.isEmpty) return repo;
    return repo.copyWith(token: t);
  }

  String get _pageTitle {
    final l10n = AppLocalizations.ofContext(context);
    switch (_currentPage) {
      case 0:
        return l10n.translate('nav_write');
      case 1:
        return l10n.translate('nav_drafts');
      case 2:
        return siteManager.isDynamicSite
            ? l10n.translate('nav_remote')
            : l10n.translate('nav_remote_single');
      case 3:
        return l10n.translate('nav_dashboard');
      case 4:
        return 'RSS';
      case 5:
        return l10n.translate('nav_history');
      case 6:
        return l10n.translate('nav_upload');
      case 7:
        return l10n.translate('nav_preview');
      case 8:
        return l10n.translate('nav_settings');
      case 9:
        return l10n.translate('page_read');
      case 10:
        return l10n.translate('nav_ai_theme_migrate');
      case 11:
        return l10n.translate('nav_log');
      case 12:
        return l10n.translate('nav_sync_status');
      case 13:
        return l10n.translate('nav_cloud_sync');
      default:
        return '';
    }
  }

  // ── 控制器访问器（从 Provider 获取） ──
  EditorController get _editor => context.read<EditorController>();
  SiteController get _site => context.read<SiteController>();
  DocumentController get _doc => context.read<DocumentController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    syncService = SyncService(logService);
    cloudSyncService = CloudSyncService(logService);
    _p2pSyncService = P2PSyncService(deviceName: 'Mobile-${DateTime.now().millisecondsSinceEpoch}');
    _typewriterCtrl = TypewriterScrollController(
      scrollController: _editorScrollCtrl,
      lineHeight: 22.0,
      visibleLines: 30,
    );
    _orientationManager = EditorStateManager(
      scrollController: _editorScrollCtrl,
      textController: _doc.contentCtrl,
    );
    // 先初始化空的站点管理器，避免任何路径下访问 late 字段触发
    // LateInitializationError（bootstrap 完成后会重新更新为完整配置）
    siteManager = SiteManager(
      staticRepos: const [],
      dynamicSites: const [],
      appSettings: AppSettings(),
      activeSiteId: '',
    );
    siteManagerInitialized = true;
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoSave();
    _stopAutoSync();
    _typewriterCtrl.dispose();
    _editorScrollCtrl.dispose();
    _orientationManager.dispose();
    _searchIsolate?.cancel();
    _p2pSyncService.dispose();
    _templateSync?.dispose();
    _siteIsolation?.dispose();
    if (siteManagerInitialized) {
      siteManager.disposeAll();
    }
    if (_siteDispatcherManagerUsed) {
      siteDispatcherManager.disposeAll();
    }
    cloudSyncService.dispose();
    cmsDraftService.close();
    _publishCancelToken.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => loading = true);
    try {
      var s = await storage.loadSettings();
      var r = await storage.loadRepos();
      // 同步全局统一存储目录配置
      storage.setCustomRoot(s.storageRootDir);
      final d = await storage.loadDrafts();
      final t = await storage.loadAllTemplates();
      final sn = await storage.loadSnippets();
      s = _ensureGithubTokensFromLegacy(s, r);
      await storage.saveSettings(s);
      if (r.isEmpty) {
        r = [
          RepoConfig(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: '我的博客',
            owner: 'caogenfunan123',
            repo: 'xiamend',
            branch: 'main',
            postsPath: 'source/_posts',
            siteUrl: '',
            token: s.effectiveGithubToken,
            isDefault: true,
          )
        ];
        await storage.saveRepos(r);
        s = s.copyWith(
            activeRepoId: r.first.id,
            imageBedOwner: 'caogenfunan123',
            imageBedRepo: 'xiamend');
        await storage.saveSettings(s);
      } else {
        final eff = s.effectiveGithubToken;
        if (eff.isNotEmpty) {
          var changed = false;
          r = r.map((repo) {
            if (repo.token.isEmpty) {
              changed = true;
              return repo.copyWith(token: eff);
            }
            return repo;
          }).toList();
          if (changed) await storage.saveRepos(r);
        }
      }
      _editorRepo = activeRepo ?? (r.isNotEmpty ? r.first : null);
      _doc.setEditorRepoId(_editorRepo?.id);
      // 自动解析编辑器默认模板
      String? autoTemplateId;
      if (_editorRepo != null) {
        autoTemplateId = TemplateResolver.resolvePostTemplateId(_editorRepo!, t);
        _doc.setSelectedTemplateId(autoTemplateId);
      }

      // 同步到站点控制器
      final staticSites = r.map((repo) => SiteConfig(
        id: repo.id,
        name: repo.name,
        repoUrl: 'https://github.com/${repo.owner}/${repo.repo}',
        branch: repo.branch,
        isDefault: repo.isDefault,
        isStatic: true,
        tokenId: repo.token.isNotEmpty ? repo.id : null,
      )).toList();
      final dynamicSites = s.blogSiteConfigs.map((cfg) => SiteConfig(
        id: cfg.id,
        name: cfg.name,
        repoUrl: cfg.siteUrl,
        isStatic: false,
      )).toList();
      _site.setSites(staticSites, dynamicSites);

      setState(() {
        settings = s;
        repos = r;
        drafts = d..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        templates = t;
        snippets = sn;
        loading = false;
      });
      _doc.setDrafts(drafts);
      _doc.setTemplates(templates);
      // 初始化站点管理器（统一管理静态仓库和动态 CMS 站点）
      _updateSiteManager();
      // 会话恢复
      if (s.restoreSession) {
        await _restoreSession();
      }
    } catch (e) {
      debugPrint('Bootstrap error: $e');
      if (mounted) setState(() {
        loading = false;
        error = e.toString();
      });
    }
    // 初始化工具系统
    try {
      await skillManager.init(await storage.root);
    } catch (e) {
      debugPrint('SkillManager init error: $e');
    }
    // 初始化云同步后端
    _initCloudSync();

    // ── 初始化新功能服务 ──
    _initNewServices();
  }

  /// 初始化新功能服务（站点隔离、P2P、模板同步、全文检索）
  Future<void> _initNewServices() async {
    try {
      final root = await storage.root;
      _siteIsolation = SiteIsolationService(root);
      await _siteIsolation!.init();
      // 日志持久化
      await logService.init(root);
      _templateSync = TemplateSyncService(
        templateDir: Directory('${root.path}/templates'),
        deviceId: 'mobile-${DateTime.now().millisecondsSinceEpoch}',
      );
      _searchIsolate = FullTextSearchIsolate(logService);
      _recycleBin = RecycleBinService();
      await _recycleBin!.init(root);
      _snapshotService = VersionSnapshotService(logService);
      await _snapshotService!.init(root);
    } catch (e) {
      debugPrint('Init new services error: $e');
    }
  }

  /// 初始化云同步后端
  Future<void> _initCloudSync() async {
    // 初始化设备密钥
    final deviceKey = await storage.loadDeviceKey();
    cloudSyncService.initDeviceKey(deviceKey);

    // 注册 GitHub 后端 — 使用独立同步仓库，不与网站仓库混用
    final githubBackend = GitHubSyncBackend(github);
    cloudSyncService.registerBackend(githubBackend);
    githubBackend.configureFromSyncSettings(settings.sync);

    // 注册 WebDAV 后端
    final webdavBackend = WebDavSyncBackend();
    webdavBackend.configureFromSettings(settings);
    cloudSyncService.registerBackend(webdavBackend);

    // 启动自动同步（仅当 draftSyncEnabled 开启时生效）
    _startAutoSync();

    // 如果后端已配置且草稿同步开启，启动后自动拉取一次
    if (cloudSyncService.hasConfiguredBackend && settings.draftSyncEnabled) {
      _autoPullFromCloud();
    }
  }

  /// 启动云端自动同步定时器
  void _startAutoSync() {
    _stopAutoSync();
    if (!settings.draftSyncEnabled) return;
    _autoSyncTimer = Timer.periodic(
      Duration(seconds: settings.webdavAutoSyncIntervalSeconds),
      (_) => _autoSyncToCloud(),
    );
  }

  void _stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  // ── 生命周期感知同步 ──

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!settings.draftSyncEnabled) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // 三重落盘：APP 转入后台/被销毁时强制冲刷所有等待中的保存任务
      _flushAllPendingSaves();
      // 异步触发云端同步，不阻塞生命周期回调
      _autoSyncToCloud();
    } else if (state == AppLifecycleState.resumed) {
      _autoPullFromCloud();
    }
  }

  /// 打开 P2P 同步界面
  void _openP2PSync() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => P2PSyncScreen(
          p2pService: _p2pSyncService,
          localArticles: drafts,
          onFilesReceived: (files) {
            for (final file in files) {
              final existingIndex = drafts.indexWhere((d) => d.fileName() == file.path);
              final article = Article(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: file.path.replaceAll('.md', ''),
                content: file.content,
                createdAt: file.modifiedAt,
                updatedAt: DateTime.now(),
                isDraft: true,
              );
              if (existingIndex >= 0) {
                drafts[existingIndex] = article;
              } else {
                drafts.add(article);
              }
            }
            storage.saveDrafts(drafts);
            if (mounted) setState(() {});
            _showToast('已接收 ${files.length} 个文件');
          },
        ),
      ),
    );
  }

  /// 自动同步到云端（推送）
  Future<void> _autoSyncToCloud() async {
    if (busy) return;
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) return;

    try {
      await cloudSyncService.pushDrafts(backend, drafts);
      await cloudSyncService.pushSyncMappings(backend, syncService);
    } catch (e) {
      debugPrint('Auto sync error: $e');
    }
  }

  /// 自动从云端拉取（后台静默，不弹 toast）
  Future<void> _autoPullFromCloud() async {
    if (busy) return;
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) return;

    try {
      final pulled = await cloudSyncService.pullDrafts(backend, existingDrafts: drafts);
      if (pulled.isNotEmpty) {
        if (mounted) setState(() {
          drafts = pulled..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        });
        storage.saveDrafts(drafts);
      }
      await cloudSyncService.pullSyncMappings(backend, syncService);
    } catch (e) {
      debugPrint('Auto sync error: $e');
    }
  }

  AppSettings _ensureGithubTokensFromLegacy(
      AppSettings s, List<RepoConfig> repos) {
    return ensureGithubTokensFromLegacy(s, repos);
  }

  void _navigateTo(int page) {
    // 离开编辑器时停止自动保存
    if (_currentPage == 0 && page != 0) {
      _stopAutoSave();
    }
    setState(() => _currentPage = page);
    // 仅在抽屉打开时才关闭抽屉，避免对根路由执行无意义的 pop
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    // 进入编辑器时启动自动保存
    if (page == 0) {
      _startAutoSave();
    }
    if (page == 2 && remotePosts.isEmpty) _refreshRemote();
    if (page == 4 && rssItems.isEmpty) _refreshRss();
    if (page == 5 && commits.isEmpty) _refreshCommits();
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  // ============ 会话管理 ============

  Future<void> _restoreSession() async {
    if (_sessionRestored) return;
    _sessionRestored = true;
    try {
      final session = await sessionService.loadSession();
      if (!session.hasArticle || session.isHome) return;

      // 恢复文章数据
      final article = Article(
        id: session.articleId,
        title: session.articleTitle,
        content: session.articleContent,
        tags: session.articleTags
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        categories: session.articleCategories
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        cover: session.articleCover.isEmpty ? null : session.articleCover,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isDraft: true,
        repoId: session.articleRepoId,
        remotePath: session.articleRemotePath,
        remoteSha: session.articleRemoteSha,
      );

      if (session.pageType == SessionPageType.editor) {
        _enterEditorFromReader(article);
      } else if (session.pageType == SessionPageType.reader) {
        _openReader(article);
      }
    } catch (e) {
      debugPrint('Restore session error: $e');
    }
  }

  Future<void> _saveSession(SessionPageType pageType) async {
    if (!settings.restoreSession) return;
    final state = SessionState(
      pageType: pageType,
      articleId: _doc.currentArticle.id,
      articleSource: ArticleSource.local,
      articleTitle: _doc.titleCtrl.text,
      articleContent: _doc.contentCtrl.text,
      articleTags: _doc.tagsCtrl.text,
      articleCategories: _doc.categoriesCtrl.text,
      articleCover: _doc.coverCtrl.text,
      articleRepoId: _doc.currentArticle.repoId ?? '',
      articleRemotePath: _doc.currentArticle.remotePath ?? '',
      articleRemoteSha: _doc.currentArticle.remoteSha ?? '',
    );
    await sessionService.saveSession(state);
  }

  Future<void> _clearSession() async {
    await sessionService.clearSession();
  }

  // ============ 退出弹窗 ============

  Future<bool> _showExitDialog() async {
    final hasChanges = _doc.hasUnsavedChanges;
    if (!hasChanges) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认退出'),
          content: const Text('确认退出当前文章？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认退出')),
          ],
        ),
      );
      return ok == true;
    }

    // 有未保存改动
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('是否退出当前文章？'),
        content: const Text('检测到未保存的改动，请选择处理方式：'),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'publish'),
                icon: const Icon(Icons.cloud_upload, size: 18),
                label: const Text('保存并发布'),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'save'),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('仅本地保存，暂不发布'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'discard'),
                child: const Text('放弃修改，直接退出',
                    style: TextStyle(color: Colors.red)),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('取消'),
              ),
            ],
          ),
        ],
      ),
    );
    if (result == null || result == 'cancel') return false;

    switch (result) {
      case 'publish':
        await _publish();
        break;
      case 'save':
        await _saveLocal();
        break;
      case 'discard':
        break;
    }
    return true;
  }

  /// 点击 × 关闭按钮 → 退出弹窗 → 回到写文章首页
  Future<void> _onCloseEditor() async {
    final ok = await _showExitDialog();
    if (!ok) return;
    _stopAutoSave();
    await _clearSession();
    _resetEditor();
    setState(() => _currentPage = 0);
  }

  Future<void> _onCloseReader() async {
    await _clearSession();
    setState(() => _currentPage = 0);
  }

  void _resetEditor() {
    final repo = activeRepo;
    _editorRepo = repo;
    String? autoTemplateId;
    if (repo != null) {
      autoTemplateId = TemplateResolver.resolvePostTemplateId(repo, templates);
    }
    final article = Article(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: '',
      content: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDraft: true,
      repoId: repo?.id,
      articleType: ArticleType.post,
      templateId: autoTemplateId,
    );
    _doc.setCurrentArticle(article);
    _doc.setArticleType(ArticleType.post);
    _doc.setSelectedTemplateId(autoTemplateId);
    _doc.setEditorRepoId(repo?.id);
  }

  /// 根据当前文章类型和仓库配置自动选择模板
  void _autoSelectTemplate() {
    final repo = _editorRepo;
    if (repo == null) return;
    _doc.setSelectedTemplateId(_doc.articleType == ArticleType.post
        ? TemplateResolver.resolvePostTemplateId(repo, templates)
        : TemplateResolver.resolvePageTemplateId(repo, templates));
  }

  // ============ 自动保存 ============

  void _startAutoSave() {
    _stopAutoSave();
    if (!settings.autoSaveEnabled) return;
    _autoSaveTimer = Timer.periodic(
      Duration(seconds: settings.autoSaveIntervalSeconds),
      (_) {
        // 定时自动保存：仅保存当前文章，防止串草稿
        final current = _doc.contentCtrl.text;
        _autoSaveSnapshot(
          articleId: _doc.currentArticle.id,
          content: current,
          title: _doc.titleCtrl.text,
        );
      },
    );
  }

  void _stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _flushAllPendingSaves();
  }

  /// 冲刷所有等待中的保存任务（三重落盘：文本变更 / 页面切换 / APP 转入后台）
  void _flushAllPendingSaves() {
    for (final entry in _debounceTimers.entries) {
      entry.value.cancel();
      final articleId = entry.key;
      final content = entry.value.content;
      if (content.isNotEmpty && content != _lastSavedContentMap[articleId]) {
        _autoSaveSnapshot(
          articleId: articleId,
          content: content,
          title: entry.value.title,
        );
      }
    }
    _debounceTimers.clear();
  }

  void _onContentChanged() {
    final current = _doc.contentCtrl.text;
    _editor.updateStats(current);
    if (current == _doc.lastSavedContent) {
      _doc.markSaved();
      return;
    }
    _doc.markUnsaved();
    // 每草稿独立防抖，杜绝多草稿相互阻塞
    final articleId = _doc.currentArticle.id;
    final title = _doc.titleCtrl.text;
    _debounceTimers[articleId]?.cancel();
    _debounceTimers[articleId] = _DebounceEntry(
      content: current,
      title: title,
      timer: Timer(const Duration(seconds: 2), () {
        final entry = _debounceTimers.remove(articleId);
        if (entry != null) {
          _autoSaveSnapshot(
            articleId: articleId,
            content: entry.content,
            title: entry.title,
          );
        }
      }),
    );
  }

  Future<void> _autoSaveSnapshot({
    required String articleId,
    required String content,
    String title = '',
  }) async {
    if (content.isEmpty || content == _lastSavedContentMap[articleId]) return;
    // 保存时应以文档当前最新状态为准，但防止串草稿：
    // 仅当用户当前仍在此文章时才标记 saved
    final isCurrent = _doc.currentArticle.id == articleId;
    try {
      await sessionService.saveAutoSnapshot(
        articleId: articleId,
        content: content,
        title: title.isEmpty ? '未命名' : title,
        tags: _doc.tagsCtrl.text,
        categories: _doc.categoriesCtrl.text,
        cover: _doc.coverCtrl.text,
      );
      _lastSavedContentMap[articleId] = content;
      if (isCurrent) _doc.markSaved();
      await sessionService.cleanupSnapshots(articleId);
      // 同时保存草稿到 storage
      await _saveDraft(_collect(draft: true));
      if (mounted) {
        _showToast('草稿已自动保存');
      }
    } catch (e) {
      debugPrint('Auto save snapshot error: $e');
    }
  }

  // ============ 阅读页 / 编辑器切换 ============

  void _openReader(Article article) {
    _doc.setCurrentArticle(article);
    _saveSession(SessionPageType.reader);
    setState(() => _currentPage = 9); // 阅读页
  }

  void _enterEditorFromReader(Article article) {
    _doc.setCurrentArticle(article);
    _editorRepo = repos
            .where((r) => r.id == article.repoId)
            .firstOrNull ??
        activeRepo;
    _doc.setEditorRepoId(_editorRepo?.id);
    _startAutoSave();
    _saveSession(SessionPageType.editor);
    setState(() => _currentPage = 0); // 回到编辑器
  }

  // --- Editor methods ---
  Article _collect({bool draft = true}) {
    _doc.setEditorRepoId(_editorRepo?.id);
    return _doc.collectArticle(draft: draft);
  }

  RepoConfig? get _resolvedRepo {
    final r = _editorRepo;
    if (r == null) return null;
    if (r.token.isNotEmpty) return r;
    final t = settings.effectiveGithubToken;
    if (t.isEmpty) return r;
    return r.copyWith(token: t);
  }

  Future<void> _saveLocal() async {
    final a = _collect(draft: true);
    setState(() {
      _doc.setCurrentArticle(a);
      _editorStatus = '本地已保存';
    });
    await _saveDraft(a);
    // 动态 CMS 站点：同时保存到 SQLite 草稿表
    if (siteManager.isDynamicSite) {
      final adapter = siteManager.currentAdapter;
      if (adapter != null) {
        final post = BlogPost(
          title: a.title,
          contentMd: a.content,
          status: 'draft',
          slug: _generateSlug(a.title),
          tags: a.tags,
          categories: a.categories,
          date: DateTime.now(),
          siteId: adapter.config.id,
          siteType: adapter.config.type,
        );
        await cmsDraftService.saveDraft(post);
      }
    }
    logService.add('保存草稿', '标题: ${a.title.isNotEmpty ? a.title : "(无标题)"}');
    if (mounted) _showToast('草稿已保存到本地');
  }

  Future<void> _publish() async {
    // ── 发布确认对话框 ──
    final publishTarget = siteManager.isDynamicSite
        ? siteManager.currentBlogType.displayName
        : (_resolvedRepo?.fullName ?? 'GitHub');
    final dynamicSiteCount = siteManager.dynamicSites.length;
    final staticRepoCount = siteManager.staticRepos.length;
    bool saveMdBackup = false;
    bool publishToAllStatic = false;

    final confirmed = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.cloud_upload_outlined,
                  color: Theme.of(context).colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              const Text('确认发布', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('即将发布到: $publishTarget',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text(
                '标题: ${_doc.titleCtrl.text.isNotEmpty ? _doc.titleCtrl.text : "(无标题)"}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              // 保存 MD 备份选项
              CheckboxListTile(
                value: saveMdBackup,
                onChanged: (v) {
                  setDialogState(() => saveMdBackup = v ?? false);
                },
                title: const Text('同时保存一份 MD 备份到本地目录',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text('备份到文档目录的 hexo_backups/ 文件夹',
                    style: TextStyle(fontSize: 11)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              // 静态站点：同时发布到所有静态博客站点
              if (!siteManager.isDynamicSite && staticRepoCount > 1)
                CheckboxListTile(
                  value: publishToAllStatic,
                  onChanged: (v) {
                    setDialogState(() => publishToAllStatic = v ?? false);
                  },
                  title: const Text('同时发布到所有静态博客站点',
                      style: TextStyle(fontSize: 13)),
                  subtitle: Text('将本文发布到全部 $staticRepoCount 个静态仓库',
                      style: const TextStyle(fontSize: 11)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: const Text('取消'),
            ),
            // 多动态站点：一键发布到全部站点
            if (siteManager.isDynamicSite && dynamicSiteCount > 1)
              TextButton.icon(
                icon: const Icon(Icons.cloud_done_outlined, size: 18),
                label: Text('发布到全部站点 ($dynamicSiteCount)'),
                onPressed: () => Navigator.pop(ctx, 2),
              ),
            FilledButton.icon(
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('确认发布'),
              onPressed: () => Navigator.pop(ctx, 1),
            ),
          ],
        ),
      ),
    );

    if (confirmed == null || confirmed == 0 || !mounted) return;

    // ── 保存 MD 备份 ──
    if (saveMdBackup) {
      await _saveMdBackup();
    }

    // 一键发布到全部动态 CMS 站点
    if (confirmed == 2) {
      await _publishToAllCmsSites();
      return;
    }

    // 动态 CMS 站点：推送到远程 CMS
    if (siteManager.isDynamicSite) {
      await _publishToCms();
      return;
    }
    // 静态站点：勾选了"同时发布到所有静态站点"则批量发布
    if (publishToAllStatic) {
      await _publishToAllStaticSites();
      return;
    }
    // 静态站点：Git 推送
    final repo = _resolvedRepo;
    if (repo == null || repo.token.isEmpty) {
      _showToast('请先配置仓库与 Token');
      return;
    }
    setState(() {
      _editorBusy = true;
      _editorStatus = '正在发布...';
    });
    try {
      final a = _collect(draft: false);
      final pub = await github.upsertArticle(repo, a, templates: templates);
      if (mounted) setState(() {
        _doc.setCurrentArticle(pub);
        _editorStatus = '已发布';
      });
      await _saveDraft(pub.copyWith(isDraft: false, published: true));
      await _refreshRemote();
      // 触发 Cloudflare Pages 重新部署
      if (settings.cloudflareDeployHook.isNotEmpty) {
        final deployed = await GitHubService.triggerCloudflareDeploy(settings.cloudflareDeployHook);
        logService.add('Cloudflare 部署', deployed ? '已触发重新部署' : '部署钩子触发失败', success: deployed);
      }
      logService.add('发布成功', '已发布到 ${repo.fullName}: ${pub.title}');
      if (mounted) _showToast('已发布到 ${repo.fullName}');
    } catch (e) {
      if (mounted) setState(() => _editorStatus = '发布失败');
      logService.add('发布失败', '$e', success: false);
      if (mounted) _showToast('发布失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
  }

  /// 发布到动态 CMS（WordPress / Ghost / Typecho）
  Future<void> _publishToCms() async {
    final adapter = siteManager.currentAdapter;
    if (adapter == null) {
      _showToast('当前站点未配置动态 CMS 适配器，请先添加 CMS 站点');
      return;
    }

    final a = _collect(draft: false);

    // ── 发布前置校验 ──
    if (settings.activeAiProfile != null) {
      final checkResult = await aiSelfChecker.check(
        settings: settings,
        generatedContent: a.content,
        sessionType: AiSessionType.article,
        blogFramework: adapter.config.type.displayName,
      );
      if (checkResult.hasError) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 8),
                Text('发布前自检发现问题'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(checkResult.message, style: const TextStyle(fontSize: 14)),
                  if (checkResult.issues.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('具体问题:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...checkResult.issues.map((i) => Padding(
                          padding: const EdgeInsets.only(top: 4, left: 8),
                          child: Text(i, style: const TextStyle(fontSize: 13, color: Color(0xFFEF4444))),
                        )),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消发布'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('仍然发布'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      } else if (!checkResult.isPassed && checkResult.issues.isNotEmpty) {
        // 仅有警告，记录但不阻断
        if (mounted) {
          _showToast('自检警告: ${checkResult.issues.first}');
        }
      }
    }

    setState(() {
      _editorBusy = true;
      final isUpdate = _doc.currentArticle.remoteSha != null;
      _editorStatus = isUpdate
          ? '正在更新到 ${adapter.config.type.displayName}...'
          : '正在发布到 ${adapter.config.type.displayName}...';
    });
    try {
      // 从 remoteSha 中提取远程文章 ID（加载远程文章时记录）
      final remoteId = _doc.currentArticle.remoteSha != null
          ? int.tryParse(_doc.currentArticle.remoteSha!)
          : null;
      final post = BlogPost(
        id: remoteId,
        title: a.title,
        contentMd: a.content,
        status: 'publish',
        slug: _generateSlug(a.title),
        tags: a.tags,
        categories: a.categories,
        date: DateTime.now(),
        siteId: adapter.config.id,
        siteType: adapter.config.type,
      );

      // ── 带重试的发布/更新 ──
      _publishCancelToken.reset();
      BlogPost? result;
      int attempts = 0;
      const maxRetries = 3;
      while (result == null) {
        _publishCancelToken.throwIfCancelled();
        attempts++;
        // 防止 createPost/updatePost 正常返回 null 时无限忙循环
        if (attempts > maxRetries) {
          throw BlogRepositoryException(
            500,
            '发布失败：远端未返回有效文章数据，请重试',
            '${adapter.config.type.displayName} 未返回文章 ID',
          );
        }
        try {
          if (attempts > 1) {
            final action = remoteId != null ? '更新' : '发布';
            if (mounted) setState(() => _editorStatus = '正在重试$action (第 $attempts 次)...');
          }
          result = remoteId != null
              ? await adapter.updatePost(post)
              : await adapter.createPost(post);
        } on BlogRepositoryException catch (e) {
          // 4xx 客户端错误不重试（鉴权失败、参数错误等）
          if (e.statusCode >= 400 && e.statusCode < 500) {
            rethrow;
          }
          // 5xx 服务端错误，尝试重试
          if (attempts >= maxRetries) rethrow;
          if (mounted) setState(() => _editorStatus = '发布失败，${2 * attempts}s 后重试...');
          await Future.delayed(Duration(seconds: 2 * attempts));
          _publishCancelToken.throwIfCancelled();
        } catch (e) {
          if (e is CancelledException) rethrow;
          // 网络错误等其他异常，也尝试重试
          if (attempts >= maxRetries) rethrow;
          if (mounted) setState(() => _editorStatus = '网络异常，${2 * attempts}s 后重试...');
          await Future.delayed(Duration(seconds: 2 * attempts));
          _publishCancelToken.throwIfCancelled();
        }
      }
      final finalResult = result;
      final isUpdate = remoteId != null;
      // 更新本地文章状态，记录远程 ID
      final pub = a.copyWith(
        isDraft: false,
        published: true,
        remotePath: finalResult.link,
        remoteSha: finalResult.id?.toString(),
      );
      if (mounted) setState(() {
        _doc.setCurrentArticle(pub);
        _editorStatus = isUpdate
            ? '已更新到 ${adapter.config.type.displayName}'
            : '已发布到 ${adapter.config.type.displayName}';
      });
      await _saveDraft(pub);
      // 保存到 CMS SQLite 草稿表
      await cmsDraftService.saveDraft(finalResult);
      // 更新同步映射
      if (finalResult.id != null) {
        syncService.setMapping(SyncMapping(
          localArticleId: pub.id,
          remotePostId: finalResult.id!,
          siteId: adapter.config.id,
          lastSyncAt: DateTime.now(),
          localModifiedAt: pub.updatedAt,
          remoteModifiedAt: finalResult.modifiedDate,
        ));
      }
      final actionLabel = isUpdate ? '更新' : '发布';
      logService.add('CMS$actionLabel成功', '已${actionLabel}到 ${adapter.config.type.displayName}: ${finalResult.title}');
      if (mounted) {
        _showToast('已${actionLabel}到 ${adapter.config.type.displayName}: ${finalResult.link ?? finalResult.title}');
      }
    } on BlogRepositoryException catch (e) {
      if (mounted) setState(() => _editorStatus = '发布失败');
      logService.add('CMS发布失败', e.message, success: false);
      if (mounted) _showToast('发布失败: ${e.message}');
    } on CancelledException {
      if (mounted) setState(() => _editorStatus = '已取消发布');
      logService.add('发布已取消', '用户取消了发布操作');
      if (mounted) _showToast('发布已取消');
    } catch (e) {
      if (mounted) setState(() => _editorStatus = '发布失败');
      logService.add('CMS发布失败', '$e', success: false);
      if (mounted) _showToast('发布失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
  }

  /// 一键发布当前文章到所有已保存的动态 CMS 站点
  /// 每个站点使用其自身的适配器（Typecho/WordPress/Ghost 等）；
  /// 若该站点已有映射（此前发布过），则更新，否则新建。
  Future<void> _publishToAllCmsSites() async {
    final adapters = _allCmsAdapters;
    if (adapters.isEmpty) {
      _showToast('没有已保存的动态 CMS 站点，请先在「设置」中添加');
      return;
    }

    final a = _collect(draft: false);
    if (a.title.trim().isEmpty) {
      _showToast('请先填写文章标题');
      return;
    }
    final slug = _generateSlug(a.title);

    setState(() {
      _editorBusy = true;
      _editorStatus = '正在发布到 ${adapters.length} 个站点...';
    });

    int success = 0;
    final details = <String, String>{};
    try {
      for (final adapter in adapters) {
        final siteName = adapter.config.name;
        if (mounted) setState(() => _editorStatus = '正在发布到 $siteName...');
        try {
          // 该站点已有远程映射 → 更新；否则新建
          final existing = syncService.findByLocalId(adapter.config.id, a.id);
          final post = BlogPost(
            id: existing?.remotePostId,
            title: a.title,
            contentMd: a.content,
            status: 'publish',
            slug: slug,
            tags: a.tags,
            categories: a.categories,
            date: DateTime.now(),
            siteId: adapter.config.id,
            siteType: adapter.config.type,
          );
          final result = existing != null
              ? await adapter.updatePost(post)
              : await adapter.createPost(post);
          success++;
          details[siteName] = '成功 (ID: ${result.id})';
          await cmsDraftService.saveDraft(result);
          if (result.id != null) {
            syncService.setMapping(SyncMapping(
              localArticleId: a.id,
              remotePostId: result.id!,
              siteId: adapter.config.id,
              lastSyncAt: DateTime.now(),
              localModifiedAt: a.updatedAt,
              remoteModifiedAt: result.modifiedDate,
            ));
          }
        } catch (e) {
          final msg = e is BlogRepositoryException ? e.message : '$e';
          details[siteName] = '失败: $msg';
          logService.add('多站点发布失败', '$siteName: $msg', success: false);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _editorBusy = false;
          _editorStatus = '多站点发布完成: 成功 $success/${adapters.length}';
        });
      }
    }

    logService.add(
        '多站点发布', '《${a.title}》成功 $success/${adapters.length} 个站点');
    if (mounted) {
      _showToast('多站点发布完成: 成功 $success/${adapters.length} 个站点');
      final lines = details.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('发布结果 ($success/${adapters.length})'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(lines, style: const TextStyle(fontSize: 13)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  /// 从标题生成 URL slug
  String _generateSlug(String title) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? 'untitled' : slug;
  }

  /// 一键发布当前文章到所有静态博客站点（带预览确认）
  Future<void> _publishToAllStaticSites() async {
    final a = _collect(draft: false);
    if (a.title.trim().isEmpty) {
      _showToast('请先填写文章标题');
      return;
    }
    final slug = _generateSlug(a.title);
    final post = BlogPost(
      title: a.title,
      contentMd: a.content,
      status: 'publish',
      slug: slug,
      tags: a.tags,
      categories: a.categories,
      date: DateTime.now(),
    );

    setState(() {
      _editorBusy = true;
      _editorStatus = '正在生成多站点发布预览...';
    });

    final service = StaticBlogBatchPublishService(
      settings: settings,
      siteManager: siteManager,
      githubService: github,
      templateService: TemplateService(),
    );

    try {
      final preview = await service.buildPreview(post);
      if (!mounted) return;
      final confirmed = await _showStaticPublishPreviewDialog(preview);
      if (confirmed != true) {
        if (mounted) setState(() => _editorStatus = '已取消');
        return;
      }

      await service.publishFromPreview(
        post,
        preview,
        onProgress: (current, total, message) {
          if (mounted) setState(() => _editorStatus = message);
        },
        onComplete: (success, message, results) {
          logService.add('多静态站点发布', message, success: success);
          if (mounted) {
            setState(() {
              _editorBusy = false;
              _editorStatus = message;
            });
            _showStaticPublishResult(results);
          }
        },
      );
    } catch (e) {
      logService.add('多静态站点发布失败', '$e', success: false);
      if (mounted) {
        setState(() {
          _editorBusy = false;
          _editorStatus = '发布失败';
        });
        _showToast('发布失败: $e');
      }
    }
  }

  /// 展示静态站点发布预览确认对话框
  Future<bool?> _showStaticPublishPreviewDialog(MultiSitePublishPreview preview) async {
    final sites = preview.publishable;
    final skipped = preview.skippedCount;
    final title = _doc.titleCtrl.text.isNotEmpty
        ? _doc.titleCtrl.text
        : '(无标题)';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('多站点发布预览'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('《$title》将发布到以下站点:',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: sites.map<Widget>((site) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.cloud_done_outlined,
                          size: 18,
                          color: const Color(0xFF059669),
                        ),
                        title: Text(site.siteName,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(site.path,
                            style: const TextStyle(fontSize: 11)),
                        trailing: const Text('可发布',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF059669),
                            )),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (skipped > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('$skipped 个站点未配置 Token 将被跳过',
                      style: const TextStyle(fontSize: 12, color: Colors.orange)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: const Text('确认发布'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }

  /// 展示静态站点发布结果
  Future<void> _showStaticPublishResult(Map<String, dynamic> results) async {
    final lines = results.entries.map((e) {
      final v = e.value;
      final ok = v is Map && v['success'] == true;
      final msg = v is Map ? (v['message']?.toString() ?? '') : '$v';
      return '${ok ? '✓' : '✗'} ${e.key}: $msg';
    }).join('\n');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发布结果'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(lines.isEmpty ? '无结果' : lines,
                style: const TextStyle(fontSize: 13)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _insertText(String t) {
    final sel = _doc.contentCtrl.selection;
    final txt = _doc.contentCtrl.text;
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _doc.contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(s, e, t),
        selection: TextSelection.collapsed(offset: s + t.length));
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

  void _wrap(String l, String r, {String p = ''}) {
    final sel = _doc.contentCtrl.selection;
    final txt = _doc.contentCtrl.text;
    if (!sel.isValid || sel.start == sel.end) {
      final body = p.isEmpty ? '' : p;
      final ins = '$l$body$r';
      final s = sel.isValid ? sel.start : txt.length;
      _doc.contentCtrl.value = TextEditingValue(
          text: txt.replaceRange(s, s, ins),
          selection:
              TextSelection.collapsed(offset: s + l.length + body.length));
      _doc.contentFocus.requestFocus();
      _onContentChanged();
      return;
    }
    final sel2 = txt.substring(sel.start, sel.end);
    _doc.contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(sel.start, sel.end, '$l$sel2$r'),
        selection: TextSelection.collapsed(
            offset: sel.start + l.length + sel2.length));
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

  void _insertHeading(int level) {
    final prefix = '${'#' * level} ';
    final txt = _doc.contentCtrl.text;
    final s = _doc.contentCtrl.selection.isValid
        ? _doc.contentCtrl.selection.start
        : txt.length;
    final lineStart = txt.lastIndexOf('\n', s - 1) + 1;
    _doc.contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(lineStart, lineStart, prefix),
        selection: TextSelection.collapsed(offset: s + prefix.length));
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

  void _insertList(String marker) {
    final sel = _doc.contentCtrl.selection;
    if (sel.isValid && sel.start != sel.end) {
      final selected = _doc.contentCtrl.text.substring(sel.start, sel.end);
      final lines = selected
          .split('\n')
          .map((l) => l.isEmpty ? l : '$marker$l')
          .join('\n');
      final txt = _doc.contentCtrl.text;
      _doc.contentCtrl.value = TextEditingValue(
          text: txt.replaceRange(sel.start, sel.end, lines),
          selection: TextSelection.collapsed(offset: sel.start + lines.length));
      _doc.contentFocus.requestFocus();
      _onContentChanged();
      return;
    }
    _insertText('\n$marker');
  }

  void _insertCodeBlock() {
    final sel = _doc.contentCtrl.selection;
    final txt = _doc.contentCtrl.text;
    final selected = (sel.isValid && sel.start != sel.end)
        ? txt.substring(sel.start, sel.end)
        : '';
    final fence = '```\n$selected\n```\n';
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _doc.contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(s, e, fence),
        selection: TextSelection.collapsed(offset: s + 4));
    _doc.contentFocus.requestFocus();
    _onContentChanged();
  }

  Future<void> _insertImage() async {
    setState(() {
      _editorBusy = true;
      _editorStatus = '正在选择图片...';
    });
    try {
      final bytes = await imageService.pickImageBytes();
      if (bytes == null) {
        if (mounted) setState(() => _editorStatus = '已取消');
        return;
      }
      _failedImageBytes = bytes; // 缓存以备重试
      final sizeKB = (bytes.length / 1024).toStringAsFixed(1);
      if (mounted) setState(() => _editorStatus = '正在上传图片 ($sizeKB KB)...');
      final url = await imageService.uploadToImageBed(bytes, settings);
      _insertText(imageService.markdownImage(url));
      _failedImageBytes = null; // 清除失败缓存
      if (mounted) setState(() => _editorStatus = '图片已插入');
    } catch (e) {
      // 缓存失败图片字节，插入重试标记
      final retryMark = '\n> ⚠️ 图片上传失败，[点击重试](#retry-upload)\n';
      _insertText(retryMark);
      if (mounted) setState(() => _editorStatus = '上传失败（可点击重试）');
      if (mounted) _showToast('上传失败，点击文中标记可重试');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
  }

  /// 批量插入图片并上传到图床（含预处理）
  Future<void> _batchInsertImages() async {
    setState(() {
      _editorBusy = true;
      _editorStatus = '正在选择图片...';
    });
    try {
      final bytesList = await imageService.pickMultipleImageBytes();
      if (bytesList == null || bytesList.isEmpty) {
        if (mounted) setState(() => _editorStatus = '已取消');
        return;
      }
      final total = bytesList.length;

      // ── 预处理阶段：批量压缩 ──
      if (mounted) setState(() => _editorStatus = '正在预处理 $total 张图片...');
      final preResult = await imageService.preprocessImages(
        bytesList,
        settings,
        onProgress: (current, total, beforeKB, afterKB) {
          if (mounted) {
            setState(() =>
                _editorStatus = '预处理 $current/$total: ${beforeKB}KB → ${afterKB}KB');
          }
        },
      );
      logService.add('图片预处理', preResult.summary);

      // ── 上传阶段 ──
      int uploaded = 0;
      int failed = 0;
      final buf = StringBuffer();
      for (var i = 0; i < total; i++) {
        if (mounted) setState(() => _editorStatus = '正在上传图片 ${i + 1}/$total...');
        try {
          final url = await imageService.uploadToImageBed(
            preResult.images[i],
            settings,
            skipCompress: true, // 已预处理，跳过重复压缩
          );
          buf.writeln(imageService.markdownImage(url));
          uploaded++;
        } catch (e) { debugPrint('App: image pick failed: $e');
          // 缓存失败图片字节，写标准重试标记，使用户可点击重试
          _failedImageBytes = preResult.images[i];
          buf.writeln('\n> ⚠️ 图片上传失败，[点击重试](#retry-upload)');
          failed++;
        }
      }
      _insertText('\n\n${buf.toString()}');
      logService.add('批量上传图片', '成功: $uploaded, 失败: $failed');
      if (mounted) setState(() => _editorStatus = '完成: $uploaded/$total 张上传成功');
    } catch (e) {
      if (mounted) setState(() => _editorStatus = '批量上传失败');
      if (mounted) _showToast('批量上传失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
  }

  /// 重试上传失败图片
  Future<void> _retryUploadImage() async {
    final bytes = _failedImageBytes;
    if (bytes == null) {
      _showToast('没有可重试的图片');
      return;
    }
    // 移除重试标记文本
    final txt = _doc.contentCtrl.text;
    final retryIdx = txt.indexOf('> ⚠️ 图片上传失败');
    if (retryIdx >= 0) {
      final markIdx = txt.indexOf('#retry-upload', retryIdx);
      if (markIdx >= 0) {
        final endIdx = txt.indexOf('\n', markIdx);
        final removeEnd = endIdx >= 0 ? endIdx + 1 : txt.length;
        _doc.contentCtrl.text = txt.replaceRange(retryIdx, removeEnd, '');
        _onContentChanged();
      }
    }

    setState(() {
      _editorBusy = true;
      _editorStatus = '正在重试上传...';
    });
    try {
      final url = await imageService.uploadToImageBed(bytes, settings);
      _insertText(imageService.markdownImage(url));
      _failedImageBytes = null;
      if (mounted) setState(() => _editorStatus = '图片已插入');
    } catch (e) {
      if (mounted) setState(() => _editorStatus = '重试失败');
      if (mounted) _showToast('重试上传失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
  }

  Future<void> _aiAction(String action) async {
    setState(() {
      _editorBusy = true;
      _editorStatus = 'AI 处理中...';
    });
    try {
      String result;
      final text = _doc.contentCtrl.text;
      switch (action) {
        case 'polish':
          result = await aiService.polish(settings, text);
          _doc.contentCtrl.text = result;
          _onContentChanged();
          break;
        case 'continue':
          result = await aiService.continueWrite(settings, text);
          _insertText('\n\n$result');
          break;
        case 'summary':
          result = await aiService.summarize(settings, text);
          if (mounted)
            await showDialog(
                context: context,
                builder: (_) => AlertDialog(
                    title: const Text('AI 摘要'),
                    content: Text(result),
                    actions: [
                      TextButton(
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: result));
                            Navigator.pop(context);
                          },
                          child: const Text('复制')),
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭')),
                    ]));
          break;
        case 'outline':
          result = await aiService.generateOutline(
              settings,
              _doc.titleCtrl.text.isEmpty ? text : _doc.titleCtrl.text);
          _doc.contentCtrl.text = result;
          _onContentChanged();
          break;
        case 'code':
          final ctrl = TextEditingController();
          final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                  title: const Text('AI 生成代码'),
                  content: TextField(
                      controller: ctrl,
                      maxLines: 5,
                      decoration: const InputDecoration(
                          hintText: '描述需要的代码')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('生成')),
                  ]));
          if (ok != true) {
            ctrl.dispose();
            break;
          }
          result = await aiService.generateCode(
              settings,
              ctrl.text.trim().isEmpty
                  ? '写一段示例代码'
                  : ctrl.text.trim());
          ctrl.dispose();
          _insertText('\n\n$result\n');
          break;
        case 'rewrite':
          final sel = _doc.contentCtrl.selection;
          if (!sel.isValid || sel.start == sel.end) {
            throw Exception('请先选中要改写的文字');
          }
          final selected = text.substring(sel.start, sel.end);
          final instrCtrl =
              TextEditingController(text: '更简洁专业');
          final ok2 = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                  title: const Text('AI 改写'),
                  content: TextField(controller: instrCtrl),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('改写')),
                  ]));
          if (ok2 != true) {
            instrCtrl.dispose();
            break;
          }
          result = await aiService.rewriteSelection(
              settings, selected, instrCtrl.text.trim());
          instrCtrl.dispose();
          final txt = _doc.contentCtrl.text;
          _doc.contentCtrl.value = TextEditingValue(
              text: txt.replaceRange(
                  sel.start, sel.end, result),
              selection: TextSelection.collapsed(
                  offset: sel.start + result.length));
          _doc.contentFocus.requestFocus();
          _onContentChanged();
          break;
        case 'format':
          result = await aiService.polish(settings,
              '请对以下 Markdown 内容进行排版优化：统一标题层级、规范空行、修正列表缩进、对齐表格格式。\n\n$text');
          _doc.contentCtrl.text = result;
          _onContentChanged();
          break;
      }
      if (mounted) setState(() => _editorStatus = 'AI 完成');
    } catch (e) {
      if (mounted) _showToast('AI 失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
  }

  /// 移动端 AI 选区编辑：选中文本后弹出 AI 编辑工具栏
  void _showAiSelectionEdit() {
    final sel = _doc.contentCtrl.selection;
    if (!sel.isValid || sel.start == sel.end) {
      _showToast('请先选中要编辑的文本');
      return;
    }
    final selectedText = _doc.contentCtrl.text.substring(sel.start, sel.end);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AiSelectionEditMobile(
        selectedText: selectedText,
        aiService: aiService,
        settings: settings,
        onAccept: (acceptedText) {
          final txt = _doc.contentCtrl.text;
          _doc.contentCtrl.value = TextEditingValue(
            text: txt.replaceRange(sel.start, sel.end, acceptedText),
            selection: TextSelection.collapsed(
              offset: sel.start + acceptedText.length),
          );
          _doc.contentFocus.requestFocus();
          _onContentChanged();
        },
      ),
    );
  }

  // --- Data methods ---
  Future<void> _saveDraft(Article a) async {
    final i = drafts.indexWhere((e) => e.id == a.id);
    if (i >= 0) drafts[i] = a;
    else drafts.insert(0, a);
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await storage.saveDrafts(drafts);
    await storage.exportDraftMarkdown(a);
    if (mounted) setState(() {});
  }

  Future<void> _deleteDraft(Article a) async {
    drafts.removeWhere((e) => e.id == a.id);
    await storage.saveDrafts(drafts);
    logService.add('删除草稿', '标题: ${a.title.isNotEmpty ? a.title : "(无标题)"}');
    if (mounted) setState(() {});
  }

  Future<void> _refreshRemote() async {
    final repo = effectiveRepo;
    if (repo == null || repo.token.isEmpty) return;
    setState(() => busy = true);
    try {
      remotePosts = await github.listPosts(repo, recursive: true);
    } catch (e) {
      debugPrint('Refresh remote error: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _refreshRss() async {
    final url = activeRepo?.siteUrl.isNotEmpty == true
        ? activeRepo!.siteUrl
        : (settings.sitePreviewUrl.isNotEmpty ? settings.sitePreviewUrl : '');
    try {
      rssItems = await rssService.fetch(url);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Refresh RSS error: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> _refreshCommits() async {
    final repo = effectiveRepo;
    if (repo == null || repo.token.isEmpty) return;
    try {
      commits = await github.listCommits(repo);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Refresh commits error: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> _updateSettings(AppSettings s) async {
    setState(() => settings = s);
    _updateSiteManager();
    _startAutoSync(); // 重启自动同步（间隔/开关可能变化）
    // 同步全局统一存储目录
    storage.setCustomRoot(s.storageRootDir);
    await storage.saveSettings(s);
    widget.onThemeChanged(Color(s.themeColor));
    // 通知父 widget 重建 MaterialApp（DesignConfig 变化时主题实时更新）
    widget.onSettingsChanged?.call(s);
  }

  Future<void> _updateRepos(List<RepoConfig> r) async {
    setState(() => repos = r);
    _updateSiteManager();
    await storage.saveRepos(r);
  }

  Future<void> _persistSettings() => storage.saveSettings(settings);
  Future<void> _persistRepos() => storage.saveRepos(repos);

  Future<void> _saveMdBackup() async {
    try {
      final a = _collect(draft: false);
      final dir = await storage.mdArticlesDir();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final safeTitle = a.title.isNotEmpty
          ? a.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          : 'untitled';
      final fileName = '${timestamp}_$safeTitle.md';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(a.content);
      if (mounted) _showToast('MD 已保存到 ${storage.dirMdArticles}/$fileName\n${dir.path}');
    } catch (e) {
      if (mounted) _showToast('MD 保存失败: $e');
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2)));
  }

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定')),
        ],
      ),
    );
    return ok == true;
  }

  String _fmt(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

  // ============ WebDAV ============

  Future<void> _showWebDavDialog() async {
    final c = TextEditingController(text: settings.webdavUrl);
    final u = TextEditingController(text: settings.webdavUsername);
    final pw = TextEditingController(text: settings.webdavPassword);
    final f = TextEditingController(text: settings.webdavFolder);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('WebDAV 备份'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: c,
                    decoration: const InputDecoration(
                        labelText: 'WebDAV 网址',
                        hintText: 'https://dav.jianguoyun.com/dav')),
                const SizedBox(height: 12),
                TextField(
                    controller: u,
                    decoration: const InputDecoration(labelText: '账号')),
                const SizedBox(height: 12),
                TextField(
                    controller: pw,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: '密码')),
                const SizedBox(height: 12),
                TextField(
                    controller: f,
                    decoration:
                        const InputDecoration(labelText: '文件夹')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            TextButton(
              onPressed: () {
                settings = settings.copyWith(
                  webdavUrl: c.text.trim(),
                  webdavUsername: u.text.trim(),
                  webdavPassword: pw.text,
                  webdavFolder: f.text.trim().isEmpty
                      ? 'hexo-backup'
                      : f.text.trim(),
                );
                _persistSettings();
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    c.dispose();
    u.dispose();
    pw.dispose();
    f.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _syncWebDavToLocal() async {
    if (settings.webdavUrl.isEmpty) {
      await _showWebDavDialog();
      if (mounted && settings.webdavUrl.isEmpty) return;
    }
    try {
      loading = true;
      if (mounted) setState(() {});
      final svc = WebDavService();
      final drafts = await storage.loadDrafts();
      final folder = settings.webdavFolder.endsWith('/')
          ? settings.webdavFolder
          : '${settings.webdavFolder}/';
      final remote = await svc.list(settings.webdavUrl,
          settings.webdavUsername, settings.webdavPassword, folder);
      final localIds = drafts.map((a) => '${a.id}.md').toSet();
      int count = 0;
      for (final item in remote) {
        if (!item.isDir && item.name.endsWith('.md')) {
          final id = item.name.replaceAll(RegExp(r'\.md$'), '');
          if (!localIds.contains(item.name)) {
            final bytes = await svc.downloadFile(settings.webdavUrl,
                settings.webdavUsername, settings.webdavPassword,
                folder, item.name);
            final md = utf8.decode(bytes);
            final article = Article.fromMarkdown(md, id: id);
            drafts.add(article);
            count++;
          }
        }
      }
      await storage.saveDrafts(drafts);
      if (mounted) {
        setState(() {
          loading = false;
          this.drafts = drafts
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        });
        _showToast('已从云端同步 $count 篇草稿到本地');
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => loading = false);
        _showToast('WebDAV 同步失败: $e');
      }
    }
  }

  Future<void> _syncDraftsToWebDav() async {
    if (settings.webdavUrl.isEmpty) {
      await _showWebDavDialog();
      if (mounted && settings.webdavUrl.isEmpty) return;
    }
    try {
      loading = true;
      if (mounted) setState(() {});
      final svc = WebDavService();
      final drafts = await storage.loadDrafts();
      final folder = settings.webdavFolder.endsWith('/')
          ? settings.webdavFolder
          : '${settings.webdavFolder}/';
      await svc.createFolder(settings.webdavUrl, settings.webdavUsername,
          settings.webdavPassword, folder);
      final remote = await svc.list(settings.webdavUrl,
          settings.webdavUsername, settings.webdavPassword, folder);
      final names = remote
          .where((e) => e.name.endsWith('.md'))
          .map((e) => e.name)
          .toSet();
      int count = 0;
      for (final a in drafts) {
        if (!names.contains('${a.id}.md')) {
          await svc.putFile(
              settings.webdavUrl,
              settings.webdavUsername,
              settings.webdavPassword,
              '$folder${a.id}.md',
              a.toMarkdownWithFrontMatter(templates: templates));
          count++;
        }
      }
      if (mounted) {
        setState(() => loading = false);
        _showToast('已上传 $count 篇草稿');
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => loading = false);
        _showToast('WebDAV 失败: $e');
      }
    }
  }

  // ============ 云同步 ============

  /// 全量推送到云端
  Future<void> _pushAllToCloud() async {
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) {
      _showToast('请先配置同步后端');
      return;
    }

    setState(() => busy = true);
    try {
      final result = await cloudSyncService.pushAll(
        backend,
        drafts: drafts,
        settings: settings,
        syncService: syncService,
        templates: templates,
        snippets: snippets,
      );
      if (mounted) {
        setState(() => busy = false);
        if (result.isSuccess) {
          _showToast('推送完成: ${result.pushed} 项');
        } else {
          _showToast('推送完成: ${result.pushed} 成功, ${result.errors.length} 失败');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        _showToast('推送失败: $e');
      }
    }
  }

  /// 全量从云端拉取
  Future<void> _pullAllFromCloud() async {
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) {
      _showToast('请先配置同步后端');
      return;
    }

    setState(() => busy = true);
    try {
      await cloudSyncService.pullAll(
        backend,
        existingDrafts: drafts,
        syncService: syncService,
        onSettingsLoaded: (s) {
          setState(() => settings = s);
          _updateSiteManager();
          _startAutoSync();
          storage.saveSettings(s);
        },
        onDraftsLoaded: (d) {
          setState(() {
            drafts = d..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          });
          storage.saveDrafts(drafts);
        },
        onTemplatesLoaded: (tList) {
          // 合并远程模板到本地：按 ID 覆盖，保留本地独有
          final remoteMap = <String, Map<String, dynamic>>{};
          for (final t in tList) {
            remoteMap[t['id']?.toString() ?? ''] = t;
          }
          final merged = <TemplateItem>[];
          final seen = <String>{};
          for (final t in templates) {
            if (remoteMap.containsKey(t.id)) {
              // 远程有同 ID → 使用远程版本（更新）
              final remote = remoteMap[t.id]!;
              merged.add(TemplateItem.fromJson(remote));
              seen.add(t.id);
            } else {
              // 本地独有 → 保留
              merged.add(t);
              seen.add(t.id);
            }
          }
          // 远程独有 → 添加
          for (final entry in remoteMap.entries) {
            if (!seen.contains(entry.key)) {
              merged.add(TemplateItem.fromJson(entry.value));
            }
          }
          setState(() => templates = merged);
          storage.saveTemplates(merged);
        },
        onSnippetsLoaded: (sList) {
          // 合并远程片段到本地：按 ID 覆盖
          final remoteMap = <String, Map<String, dynamic>>{};
          for (final s in sList) {
            remoteMap[s['id']?.toString() ?? ''] = s;
          }
          final merged = <SnippetItem>[];
          final seen = <String>{};
          for (final s in snippets) {
            if (remoteMap.containsKey(s.id)) {
              merged.add(SnippetItem.fromJson(remoteMap[s.id]!));
              seen.add(s.id);
            } else {
              merged.add(s);
              seen.add(s.id);
            }
          }
          for (final entry in remoteMap.entries) {
            if (!seen.contains(entry.key)) {
              merged.add(SnippetItem.fromJson(entry.value));
            }
          }
          setState(() => snippets = merged);
          storage.saveSnippets(merged);
        },
      );
      if (mounted) {
        setState(() => busy = false);
        _showToast('拉取完成');
      }
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        _showToast('拉取失败: $e');
      }
    }
  }

  // ============ Theme ============

  Future<void> _showThemeColorPicker() async {
    const colors = [
      Color(0xFF0EA5E9),
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFFF43F5E),
      Color(0xFF10B981),
      Color(0xFF14B8A6),
      Color(0xFFF59E0B),
      Color(0xFF64748B),
      Color(0xFF1E293B),
    ];
    const names = [
      '天蓝', '靛蓝', '紫色', '粉色', '玫瑰红', '翡翠绿', '青绿', '琥珀', '石板灰', '深灰'
    ];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择主题颜色'),
        content: SizedBox(
          width: 300,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(colors.length, (i) {
              return GestureDetector(
                onTap: () async {
                  settings =
                      settings.copyWith(themeColor: colors[i].value);
                  await _persistSettings();
                  widget.onThemeChanged(colors[i]);
                  _showToast('主题色已切换为${names[i]}');
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors[i],
                        borderRadius: BorderRadius.circular(14),
                        border: settings.themeColor == colors[i].value
                            ? Border.all(
                                color: Colors.black, width: 2.5)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(names[i],
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              );
            }),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  // ============ Site Editor ============

  Future<void> _showSiteEditor() async {
    final repo = effectiveRepo;
    if (repo == null) {
      _showToast('请先配置仓库');
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SiteEditorScreen(
          repo: repo,
          github: github,
          onSaved: () => _showToast('站点内容已同步到 GitHub，稍后自动部署'),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// 打开动态 CMS 站点管理页面
  Future<void> _showBlogSiteManager() async {
    await Navigator.of(context).push<BlogSiteConfig?>(
      MaterialPageRoute(
        builder: (_) => BlogSiteEditorScreen(
          appSettings: settings,
          onSaved: _handleBlogSiteSaved,
        ),
      ),
    );
  }

  /// 处理动态 CMS 站点保存
  Future<void> _handleBlogSiteSaved(BlogSiteConfig config) async {
    final existing = List<BlogSiteConfig>.from(settings.blogSiteConfigs);
    final idx = existing.indexWhere((s) => s.id == config.id);
    if (idx >= 0) {
      existing[idx] = config;
    } else {
      existing.add(config);
    }
    final updated = settings.copyWith(blogSiteConfigs: existing);
    await _updateSettings(updated);
  }

  // ============ AI Profile Management ============

  Future<void> _showAiManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final profiles =
                List<AiProfile>.from(settings.aiProfiles);
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom:
                    MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'AI 中转站配置',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final created =
                                await _editAiProfile(null);
                            if (created != null) {
                              final list = List<AiProfile>.from(
                                  settings.aiProfiles)
                                ..add(created);
                              settings = settings.copyWith(
                                aiProfiles: list,
                                activeAiProfileId: created.id,
                                aiBaseUrl: created.baseUrl,
                                aiApiKey: created.apiKey,
                                aiModel: created.model,
                                aiProvider: created.name,
                              );
                              await _persistSettings();
                              setModal(() {});
                              if (mounted) setState(() {});
                              _showToast('已保存配置');
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('新增'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '填写 Base URL + API Key，点「获取模型」选择模型后保存。可保存多套并任意切换。',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: profiles.isEmpty
                          ? const Center(
                              child: Text('暂无配置，点右上角新增'))
                          : ListView.separated(
                              itemCount: profiles.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final p = profiles[i];
                                final active = settings
                                        .activeAiProfileId ==
                                    p.id;
                                return Card(
                                  child: ListTile(
                                    leading: Icon(
                                      active
                                          ? Icons.check_circle
                                          : Icons
                                              .smart_toy_outlined,
                                      color: active
                                          ? Theme.of(ctx)
                                              .colorScheme
                                              .primary
                                          : null,
                                    ),
                                    title: Text(p.displayLabel),
                                    subtitle: Text(
                                      '${p.baseUrl}\n模型: ${p.model.isEmpty ? "未选" : p.model}',
                                      maxLines: 3,
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                    isThreeLine: true,
                                    trailing: PopupMenuButton<
                                        String>(
                                      onSelected: (v) async {
                                        if (v == 'use') {
                                          settings = settings
                                              .copyWith(
                                            activeAiProfileId:
                                                p.id,
                                            aiBaseUrl: p.baseUrl,
                                            aiApiKey: p.apiKey,
                                            aiModel: p.model,
                                            aiProvider: p.name,
                                          );
                                          await _persistSettings();
                                          setModal(() {});
                                          if (mounted)
                                            setState(() {});
                                          _showToast(
                                              '已切换到 ${p.displayLabel}');
                                        } else if (v ==
                                            'edit') {
                                          final edited =
                                              await _editAiProfile(
                                                  p);
                                          if (edited != null) {
                                            final list = List<
                                                    AiProfile>.from(
                                                settings
                                                    .aiProfiles);
                                            final ix = list
                                                .indexWhere((e) =>
                                                    e.id ==
                                                    p.id);
                                            if (ix >= 0)
                                              list[ix] = edited;
                                            final activeId = settings
                                                            .activeAiProfileId ==
                                                        p.id
                                                    ? edited.id
                                                    : settings
                                                        .activeAiProfileId;
                                            settings = settings
                                                .copyWith(
                                              aiProfiles: list,
                                              activeAiProfileId:
                                                  activeId,
                                              aiBaseUrl: activeId ==
                                                      edited.id
                                                  ? edited.baseUrl
                                                  : settings
                                                      .aiBaseUrl,
                                              aiApiKey: activeId ==
                                                      edited.id
                                                  ? edited.apiKey
                                                  : settings
                                                      .aiApiKey,
                                              aiModel: activeId ==
                                                      edited.id
                                                  ? edited.model
                                                  : settings
                                                      .aiModel,
                                              aiProvider: activeId ==
                                                      edited.id
                                                  ? edited.name
                                                  : settings
                                                      .aiProvider,
                                            );
                                            await _persistSettings();
                                            setModal(() {});
                                            if (mounted)
                                              setState(() {});
                                          }
                                        } else if (v ==
                                            'delete') {
                                          final ok = await _confirm(
                                              '删除配置「${p.name}」？');
                                          if (!ok) return;
                                          final list = List<
                                                      AiProfile>
                                                  .from(settings
                                                      .aiProfiles)
                                                ..removeWhere(
                                                    (e) =>
                                                        e.id ==
                                                        p.id);
                                          var activeId = settings
                                              .activeAiProfileId;
                                          if (activeId == p.id) {
                                            activeId = list
                                                    .isNotEmpty
                                                ? list.first.id
                                                : '';
                                          }
                                          AiProfile? activeP;
                                          for (final e in list) {
                                            if (e.id == activeId) {
                                              activeP = e;
                                              break;
                                            }
                                          }
                                          if (activeP == null &&
                                              list.isNotEmpty) {
                                            activeP = list.first;
                                            activeId =
                                                activeP.id;
                                          }
                                          settings = settings
                                              .copyWith(
                                            aiProfiles: list,
                                            activeAiProfileId:
                                                activeId,
                                            aiBaseUrl: activeP
                                                    ?.baseUrl ??
                                                settings
                                                    .aiBaseUrl,
                                            aiApiKey: activeP
                                                    ?.apiKey ??
                                                '',
                                            aiModel: activeP
                                                    ?.model ??
                                                settings
                                                    .aiModel,
                                            aiProvider: activeP
                                                    ?.name ??
                                                settings
                                                    .aiProvider,
                                          );
                                          await _persistSettings();
                                          setModal(() {});
                                          if (mounted)
                                            setState(() {});
                                        }
                                      },
                                      itemBuilder: (_) =>
                                          const [
                                        PopupMenuItem(
                                            value: 'use',
                                            child: Text(
                                                '设为当前')),
                                        PopupMenuItem(
                                            value: 'edit',
                                            child: Text(
                                                '编辑')),
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text(
                                                '删除')),
                                      ],
                                    ),
                                    onTap: () async {
                                      settings = settings.copyWith(
                                        activeAiProfileId: p.id,
                                        aiBaseUrl: p.baseUrl,
                                        aiApiKey: p.apiKey,
                                        aiModel: p.model,
                                        aiProvider: p.name,
                                      );
                                      await _persistSettings();
                                      setModal(() {});
                                      if (mounted)
                                        setState(() {});
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<AiProfile?> _editAiProfile(AiProfile? existing) async {
    final nameCtrl = TextEditingController(
        text: existing?.name ?? '中转站');
    final baseCtrl = TextEditingController(
        text: existing?.baseUrl.isNotEmpty == true
            ? existing!.baseUrl
            : (settings.aiBaseUrl.isNotEmpty
                ? settings.aiBaseUrl
                : 'https://api.openai.com/v1'));
    final keyCtrl = TextEditingController(
        text: existing?.apiKey.isNotEmpty == true
            ? existing!.apiKey
            : settings.aiApiKey);
    final modelCtrl = TextEditingController(
        text: existing?.model ?? settings.aiModel);
    var models = List<String>.from(
        existing?.cachedModels ?? const <String>[]);
    var selectedModel = existing?.model ?? '';
    var fetching = false;
    var useBearer = existing?.useBearer ?? true;
    String? err;

    return showDialog<AiProfile>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            Future<void> fetchModels() async {
              setDlg(() {
                fetching = true;
                err = null;
              });
              try {
                final temp = AiProfile(
                  id: existing?.id ?? 'tmp',
                  name: nameCtrl.text.trim().isEmpty
                      ? '中转站'
                      : nameCtrl.text.trim(),
                  baseUrl: baseCtrl.text.trim(),
                  apiKey: keyCtrl.text.trim(),
                  model: modelCtrl.text.trim(),
                  useBearer: useBearer,
                  cachedModels: models,
                );
                final list = await AiService()
                    .listModels(settings, profile: temp);
                setDlg(() {
                  models = list;
                  if (selectedModel.isEmpty &&
                      list.isNotEmpty) {
                    selectedModel = list.first;
                    modelCtrl.text = selectedModel;
                  } else if (selectedModel.isNotEmpty &&
                      list.contains(selectedModel)) {
                    modelCtrl.text = selectedModel;
                  }
                  fetching = false;
                });
                if (list.isEmpty) {
                  _showToast('未拉到模型，可手动填写模型名');
                } else {
                  _showToast('已获取 ${list.length} 个模型');
                }
              } catch (e) {
                setDlg(() {
                  fetching = false;
                  err = e.toString();
                });
              }
            }

            return AlertDialog(
              title: Text(existing == null
                  ? '新增 AI 配置'
                  : '编辑 AI 配置'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: '名称',
                          hintText:
                              '如 DeepSeek / 硅基流动 / 自建中转',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: baseCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Base URL',
                          hintText: 'https://api.xxx.com/v1',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: keyCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'API Key',
                          hintText: 'sk-...',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Bearer 鉴权'),
                        subtitle: const Text(
                            '关闭则同时发送 api-key / x-api-key'),
                        value: useBearer,
                        onChanged: (v) =>
                            setDlg(() => useBearer = v),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: modelCtrl,
                              decoration: const InputDecoration(
                                labelText: '模型',
                                hintText:
                                    '可手动填写或从列表选择',
                              ),
                              onChanged: (v) =>
                                  selectedModel = v.trim(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: fetching
                                ? null
                                : fetchModels,
                            child: fetching
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(
                                            strokeWidth: 2),
                                  )
                                : const Text('获取模型'),
                          ),
                        ],
                      ),
                      if (err != null) ...[
                        const SizedBox(height: 8),
                        Text(err!,
                            style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12)),
                      ],
                      if (models.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: models
                                  .contains(selectedModel)
                              ? selectedModel
                              : null,
                          decoration: const InputDecoration(
                              labelText: '从列表选择模型'),
                          items: models
                              .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m,
                                      overflow: TextOverflow
                                          .ellipsis)))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setDlg(() {
                              selectedModel = v;
                              modelCtrl.text = v;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                FilledButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim().isEmpty
                        ? '中转站'
                        : nameCtrl.text.trim();
                    final base = baseCtrl.text.trim();
                    final key = keyCtrl.text.trim();
                    final model = modelCtrl.text.trim();
                    if (base.isEmpty) {
                      _showToast('请填写 Base URL');
                      return;
                    }
                    if (key.isEmpty) {
                      _showToast('请填写 API Key');
                      return;
                    }
                    if (model.isEmpty) {
                      _showToast('请选择或填写模型');
                      return;
                    }
                    final id = existing?.id ??
                        'ai_${DateTime.now().millisecondsSinceEpoch}';
                    Navigator.pop(
                      ctx,
                      AiProfile(
                        id: id,
                        name: name,
                        baseUrl: base,
                        apiKey: key,
                        model: model,
                        useBearer: useBearer,
                        cachedModels: models,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============ GitHub Token Management ============

  Future<void> _activateGithubToken(String id) async {
    GithubTokenProfile? profile;
    for (final t in settings.githubTokens) {
      if (t.id == id) {
        profile = t;
        break;
      }
    }
    if (profile == null) return;
    settings = settings.copyWith(
      activeGithubTokenId: profile.id,
      defaultToken: profile.token,
    );
    await _persistSettings();
    final repo = activeRepo;
    if (repo != null && repo.token.isEmpty) {
      final i = repos.indexWhere((e) => e.id == repo.id);
      if (i >= 0) {
        repos[i] = repo.copyWith(token: profile.token);
        await _persistRepos();
      }
    }
    if (mounted) setState(() {});
    _showToast('已切换到 ${profile.displayLabel}');
  }

  Future<void> _upsertGithubToken(
    GithubTokenProfile profile, {
    bool makeActive = false,
  }) async {
    final list =
        List<GithubTokenProfile>.from(settings.githubTokens);
    final byToken =
        list.indexWhere((e) => e.token == profile.token);
    final byId = list.indexWhere((e) => e.id == profile.id);
    if (byId >= 0) {
      list[byId] = profile;
    } else if (byToken >= 0) {
      list[byToken] =
          profile.copyWith(id: list[byToken].id);
    } else {
      list.add(profile);
    }
    final activeId = makeActive ||
            settings.activeGithubTokenId.isEmpty
        ? (byId >= 0
            ? profile.id
            : byToken >= 0
                ? list[byToken].id
                : profile.id)
        : settings.activeGithubTokenId;
    GithubTokenProfile? active;
    for (final t in list) {
      if (t.id == activeId) {
        active = t;
        break;
      }
    }
    active ??= list.isNotEmpty ? list.first : null;
    settings = settings.copyWith(
      githubTokens: list,
      activeGithubTokenId: active?.id ?? '',
      defaultToken: active?.token ?? settings.defaultToken,
    );
    await _persistSettings();
    if (mounted) setState(() {});
  }

  Future<void> _showGithubTokenManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final tokens = List<GithubTokenProfile>.from(
                settings.githubTokens);
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom:
                    MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'GitHub 登录令牌',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final created =
                                await _editGithubToken(null);
                            if (created != null) {
                              await _upsertGithubToken(created,
                                  makeActive: true);
                              setModal(() {});
                              if (mounted) setState(() {});
                              _showToast(
                                  '已保存 ${created.displayLabel}');
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('登录'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Token 仅保存在本机。登录后可在多仓库间复用，也可随时切换当前令牌。',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: tokens.isEmpty
                          ? const Center(
                              child: Text(
                                  '暂无已登录令牌，点右上角登录'))
                          : ListView.separated(
                              itemCount: tokens.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final t = tokens[i];
                                final active = settings
                                        .activeGithubTokenId ==
                                    t.id;
                                return Card(
                                  child: ListTile(
                                    leading: Icon(
                                      active
                                          ? Icons.check_circle
                                          : Icons
                                              .key_outlined,
                                      color: active
                                          ? Theme.of(ctx)
                                              .colorScheme
                                              .primary
                                          : null,
                                    ),
                                    title: Text(t.displayLabel),
                                    subtitle: Text(
                                      [
                                        if (t.login.isNotEmpty)
                                          '@${t.login}',
                                        t.maskedToken,
                                        if (t.lastVerifiedAt !=
                                            null)
                                          '验证于 ${t.lastVerifiedAt!.toLocal().toString().substring(0, 16)}',
                                      ].join(' · '),
                                    ),
                                    isThreeLine: t.lastVerifiedAt !=
                                        null,
                                    trailing: PopupMenuButton<
                                        String>(
                                      onSelected: (v) async {
                                        if (v == 'use') {
                                          await _activateGithubToken(
                                              t.id);
                                          setModal(() {});
                                        } else if (v ==
                                            'edit') {
                                          final edited =
                                              await _editGithubToken(
                                                  t);
                                          if (edited != null) {
                                            await _upsertGithubToken(
                                                edited,
                                                makeActive: settings
                                                        .activeGithubTokenId ==
                                                    t.id);
                                            setModal(() {});
                                          }
                                        } else if (v ==
                                            'verify') {
                                          try {
                                            final user = await github
                                                .getUser(
                                                    t.token);
                                            final login = user[
                                                        'login']
                                                    ?.toString() ??
                                                '';
                                            await _upsertGithubToken(
                                                t.copyWith(
                                              login: login,
                                              avatarUrl: user[
                                                          'avatar_url']
                                                      ?.toString() ??
                                                  '',
                                              htmlUrl: user[
                                                          'html_url']
                                                      ?.toString() ??
                                                  '',
                                              lastVerifiedAt:
                                                  DateTime.now(),
                                              name: t.name
                                                              .isEmpty ||
                                                          t.name ==
                                                              '默认 Token' ||
                                                          t.name ==
                                                              'GitHub Token'
                                                  ? (login.isNotEmpty
                                                      ? login
                                                      : t.name)
                                                  : t.name,
                                            ),
                                                makeActive:
                                                    active);
                                            setModal(() {});
                                            _showToast(login
                                                    .isEmpty
                                                ? 'Token 有效'
                                                : '有效 · @$login');
                                          } catch (e) {
                                            _showToast(
                                                '校验失败: $e');
                                          }
                                        } else if (v ==
                                            'delete') {
                                          final ok = await _confirm(
                                              '删除已保存令牌「${t.displayLabel}」？');
                                          if (!ok) return;
                                          final list = List<
                                                      GithubTokenProfile>
                                                  .from(settings
                                                      .githubTokens)
                                                ..removeWhere(
                                                    (e) =>
                                                        e.id ==
                                                        t.id);
                                          var activeId = settings
                                              .activeGithubTokenId;
                                          if (activeId == t.id) {
                                            activeId = list
                                                    .isNotEmpty
                                                ? list.first.id
                                                : '';
                                          }
                                          final activeToken = list
                                                  .isEmpty
                                              ? ''
                                              : list
                                                  .firstWhere(
                                                    (e) =>
                                                        e.id ==
                                                        activeId,
                                                    orElse: () =>
                                                        list.first,
                                                  )
                                                  .token;
                                          settings = settings
                                              .copyWith(
                                            githubTokens: list,
                                            activeGithubTokenId:
                                                activeId,
                                            defaultToken:
                                                activeToken,
                                          );
                                          await _persistSettings();
                                          setModal(() {});
                                          if (mounted)
                                            setState(() {});
                                        }
                                      },
                                      itemBuilder: (_) =>
                                          const [
                                        PopupMenuItem(
                                            value: 'use',
                                            child: Text(
                                                '设为当前')),
                                        PopupMenuItem(
                                            value: 'verify',
                                            child: Text(
                                                '验证')),
                                        PopupMenuItem(
                                            value: 'edit',
                                            child: Text(
                                                '编辑')),
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text(
                                                '删除')),
                                      ],
                                    ),
                                    onTap: () async {
                                      await _activateGithubToken(
                                          t.id);
                                      setModal(() {});
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<GithubTokenProfile?> _editGithubToken(
      GithubTokenProfile? existing) async {
    final nameCtrl = TextEditingController(
      text: existing?.name.isNotEmpty == true
          ? existing!.name
          : (existing?.login.isNotEmpty == true
              ? existing!.login
              : 'GitHub Token'),
    );
    final tokenCtrl = TextEditingController(
        text: existing?.token ?? '');
    var verifying = false;
    String? err;
    String login = existing?.login ?? '';
    String avatarUrl = existing?.avatarUrl ?? '';
    String htmlUrl = existing?.htmlUrl ?? '';

    return showDialog<GithubTokenProfile>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            Future<void> verifyAndFill() async {
              final token = tokenCtrl.text.trim();
              if (token.isEmpty) {
                setDlg(() => err = '请先填写 Token');
                return;
              }
              setDlg(() {
                verifying = true;
                err = null;
              });
              try {
                final user = await github.getUser(token);
                login = user['login']?.toString() ?? '';
                avatarUrl =
                    user['avatar_url']?.toString() ?? '';
                htmlUrl =
                    user['html_url']?.toString() ?? '';
                if (nameCtrl.text.trim().isEmpty ||
                    nameCtrl.text.trim() == 'GitHub Token' ||
                    nameCtrl.text.trim() == '默认 Token') {
                  if (login.isNotEmpty)
                    nameCtrl.text = login;
                }
                setDlg(() => verifying = false);
                _showToast(login.isEmpty
                    ? 'Token 有效'
                    : '验证成功 · @$login');
              } catch (e) {
                setDlg(() {
                  verifying = false;
                  err = e.toString();
                });
              }
            }

            return AlertDialog(
              title: Text(existing == null
                  ? '登录 GitHub Token'
                  : '编辑 Token'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: '备注名称',
                          hintText: '如 主账号 / 图床专用',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: tokenCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'GitHub Token',
                          hintText:
                              'ghp_... 或 fine-grained token',
                          helperText:
                              '需要 contents:read/write 权限',
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (login.isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                              Icons.account_circle_outlined),
                          title: Text('@$login'),
                          subtitle: Text(htmlUrl.isEmpty
                              ? '已验证'
                              : htmlUrl),
                        ),
                      if (err != null)
                        Text(err!,
                            style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12)),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: verifying
                              ? null
                              : verifyAndFill,
                          icon: verifying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(
                                          strokeWidth: 2),
                                )
                              : const Icon(
                                  Icons.verified_user_outlined),
                          label: Text(verifying
                              ? '验证中…'
                              : '验证并识别账号'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                FilledButton(
                  onPressed: verifying
                      ? null
                      : () async {
                          final token = tokenCtrl.text.trim();
                          if (token.isEmpty) {
                            _showToast('请填写 Token');
                            return;
                          }
                          if (login.isEmpty) {
                            try {
                              final user =
                                  await github.getUser(token);
                              login = user['login']
                                      ?.toString() ??
                                  '';
                              avatarUrl =
                                  user['avatar_url']
                                          ?.toString() ??
                                      '';
                              htmlUrl = user['html_url']
                                      ?.toString() ??
                                  '';
                            } catch (e) {
                              final force = await _confirm(
                                  'Token 校验失败：\n$e\n\n仍要保存吗？');
                              if (!force) return;
                            }
                          }
                          final name = nameCtrl
                                  .text.trim().isEmpty
                              ? (login.isNotEmpty
                                  ? login
                                  : 'GitHub Token')
                              : nameCtrl.text.trim();
                          Navigator.pop(
                            ctx,
                            GithubTokenProfile(
                              id: existing?.id ??
                                  'gh_${DateTime.now().millisecondsSinceEpoch}',
                              name: name,
                              token: token,
                              login: login,
                              avatarUrl: avatarUrl,
                              htmlUrl: htmlUrl,
                              lastVerifiedAt: login.isNotEmpty
                                  ? DateTime.now()
                                  : existing
                                      ?.lastVerifiedAt,
                            ),
                          );
                        },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============ Repo Management ============

  Future<void> _showRepoManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom:
                    MediaQuery.of(ctx).viewInsets.bottom + 16,
                top: 8,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '多仓库管理',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () async {
                            await _editRepo();
                            setModal(() {});
                            setState(() {});
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('添加'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: repos.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = repos[i];
                          final active =
                              activeRepo?.id == r.id;
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                active
                                    ? Icons
                                        .radio_button_checked
                                    : Icons.radio_button_off,
                                color: active
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                    : null,
                              ),
                              title: Text(r.name),
                              subtitle: Text(
                                '${r.fullName} @ ${r.branch}\n'
                                '${BlogFramework.byId(r.frameworkId)?.name ?? r.frameworkId} | '
                                '文章: ${r.postsPath} | 页面: ${r.pagesPath}\n'
                                '${TemplateResolver.describeRepoDefaults(r, templates)}',
                              ),
                              isThreeLine: false,
                              dense: false,
                              onTap: () async {
                                settings = settings.copyWith(
                                    activeRepoId: r.id);
                                await _persistSettings();
                                remotePosts = [];
                                commits = [];
                                setState(() {});
                                setModal(() {});
                                if (ctx.mounted)
                                  Navigator.pop(ctx);
                              },
                              trailing: PopupMenuButton<
                                  String>(
                                onSelected: (v) async {
                                  if (v == 'edit') {
                                    await _editRepo(
                                        existing: r);
                                  } else if (v ==
                                      'delete') {
                                    final ok = await _confirm(
                                        '删除仓库配置「${r.name}」？');
                                    if (ok) {
                                      repos.removeWhere(
                                          (e) => e.id == r.id);
                                      await _persistRepos();
                                      if (settings
                                              .activeRepoId ==
                                          r.id) {
                                        settings = settings
                                            .copyWith(
                                          activeRepoId: repos
                                                  .isEmpty
                                              ? ''
                                              : repos
                                                  .first.id,
                                        );
                                        await _persistSettings();
                                      }
                                    }
                                  }
                                  setModal(() {});
                                  setState(() {});
                                },
                                itemBuilder: (_) =>
                                    const [
                                  PopupMenuItem(
                                      value: 'edit',
                                      child:
                                          Text('编辑')),
                                  PopupMenuItem(
                                      value: 'delete',
                                      child:
                                          Text('删除')),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _editRepo({RepoConfig? existing}) async {
    final name = TextEditingController(
        text: existing?.name ?? '');
    final owner = TextEditingController(
        text: existing?.owner ?? 'caogenfunan123');
    final repo = TextEditingController(
        text: existing?.repo ?? 'xiamend');
    final branch = TextEditingController(
        text: existing?.branch ?? 'main');
    final posts = TextEditingController(
        text: existing?.postsPath ?? 'source/_posts');
    final pages = TextEditingController(
        text: existing?.pagesPath ?? 'source');
    final site = TextEditingController(
        text: existing?.siteUrl.isNotEmpty == true
            ? existing!.siteUrl
            : '');
    final token = TextEditingController(
        text: existing?.token.isNotEmpty == true
            ? existing!.token
            : settings.effectiveGithubToken);
    String frameworkId = existing?.frameworkId ?? 'hexo';
    final String originalFrameworkId = existing?.frameworkId ?? 'hexo';
    int publishTimeZoneOffsetMinutes =
        existing?.publishTimeZoneOffsetMinutes ?? 480;
    bool postDatePrefix = existing?.fileNameRule.postDatePrefix ?? false;
    String? selectedTokenId = settings.activeGithubTokenId;
    if (existing?.token.isNotEmpty == true) {
      for (final t in settings.githubTokens) {
        if (t.token == existing!.token) {
          selectedTokenId = t.id;
          break;
        }
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              title: Text(
                  existing == null ? '添加仓库' : '编辑仓库'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── 博客框架选择 ──
                    DropdownButtonFormField<String>(
                      value: frameworkId,
                      decoration: const InputDecoration(
                        labelText: '博客框架',
                        prefixIcon: Icon(Icons.web, size: 18),
                      ),
                      items: [
                        ...BlogFramework.presets.map((f) =>
                          DropdownMenuItem(value: f.id, child: Text('${f.name} (${f.defaultPostsPath})')),
                        ),
                        const DropdownMenuItem(value: 'custom', child: Text('自定义')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setDlg(() {
                          frameworkId = v;
                          if (v != 'custom') {
                            final fw = BlogFramework.byId(v);
                            if (fw != null) {
                              posts.text = fw.defaultPostsPath;
                              pages.text = fw.defaultPagesPath;
                              postDatePrefix = fw.postDatePrefix;
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    // ── 发布时区选择 ──
                    DropdownButtonFormField<int>(
                      value: publishTimeZoneOffsetMinutes,
                      decoration: const InputDecoration(
                        labelText: '发布时区',
                        helperText: 'Front Matter 日期带该时区偏移，避免 Cloudflare(UTC) 构建日期错位',
                        prefixIcon: Icon(Icons.schedule, size: 18),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('UTC (UTC+0)')),
                        DropdownMenuItem(value: 480, child: Text('北京 (UTC+8)')),
                        DropdownMenuItem(value: 540, child: Text('东京 (UTC+9)')),
                        DropdownMenuItem(value: 600, child: Text('悉尼 (UTC+10)')),
                        DropdownMenuItem(value: -300, child: Text('纽约 (UTC-5)')),
                        DropdownMenuItem(value: -480, child: Text('洛杉矶 (UTC-8)')),
                        DropdownMenuItem(value: 330, child: Text('孟买 (UTC+5:30)')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDlg(() => publishTimeZoneOffsetMinutes = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                        controller: name,
                        decoration: const InputDecoration(
                            labelText: '显示名称')),
                    TextField(
                        controller: owner,
                        decoration: const InputDecoration(
                            labelText: 'Owner')),
                    TextField(
                        controller: repo,
                        decoration: const InputDecoration(
                            labelText: 'Repo')),
                    TextField(
                        controller: branch,
                        decoration: const InputDecoration(
                            labelText: 'Branch')),
                    // ── 双目录配置 ──
                    TextField(
                        controller: posts,
                        decoration: const InputDecoration(
                            labelText: '博文目录 (posts)',
                            helperText: '例如: source/_posts, content/posts')),
                    TextField(
                        controller: pages,
                        decoration: const InputDecoration(
                            labelText: '页面目录 (pages)',
                            helperText: '例如: source, content')),
                    // ── 文件名规则 ──
                    CheckboxListTile(
                      title: const Text('博文自动日期前缀'),
                      subtitle: const Text('2026-08-02-title.md (Jekyll/Hugo)'),
                      value: postDatePrefix,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setDlg(() => postDatePrefix = v ?? false),
                    ),
                    TextField(
                        controller: site,
                        decoration: const InputDecoration(
                            labelText: '站点 URL')),
                    if (settings
                        .githubTokens.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: settings.githubTokens
                                .any((e) =>
                                    e.id == selectedTokenId)
                            ? selectedTokenId
                            : null,
                        decoration: const InputDecoration(
                          labelText: '选用已登录 Token',
                          helperText:
                              '可选择已保存令牌，或下方手动填写',
                        ),
                        items: [
                          ...settings.githubTokens.map(
                            (t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(t.displayLabel,
                                  overflow: TextOverflow
                                      .ellipsis),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          final t = settings.githubTokens
                              .firstWhere(
                                  (e) => e.id == v);
                          setDlg(() {
                            selectedTokenId = t.id;
                            token.text = t.token;
                          });
                        },
                      ),
                    ],
                    TextField(
                      controller: token,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'GitHub Token'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () =>
                        Navigator.pop(ctx, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, true),
                    child: const Text('保存')),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;

    final tokenValue = token.text.trim();

    // ── 框架变更弹窗询问 ──
    bool updateTemplates = true;
    if (existing != null && frameworkId != originalFrameworkId) {
      updateTemplates = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('框架已变更'),
              content: Text(
                '当前仓库框架从 $originalFrameworkId 变更为 $frameworkId，\n是否更新仓库默认文章/页面模板？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('保持现有模板不变'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('更新默认模板'),
                ),
              ],
            ),
          ) ??
          true;
    }

    // 自动绑定框架默认模板
    String? defaultPostId = existing?.defaultPostTemplateId;
    String? defaultPageId = existing?.defaultPageTemplateId;
    if (existing == null || updateTemplates) {
      defaultPostId = RepoConfig.defaultPostTemplateForFramework(frameworkId);
      defaultPageId = RepoConfig.defaultPageTemplateForFramework(frameworkId);
    }

    final cfg = RepoConfig(
      id: existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.text.trim().isEmpty
          ? repo.text.trim()
          : name.text.trim(),
      owner: owner.text.trim(),
      repo: repo.text.trim(),
      branch: branch.text.trim().isEmpty
          ? 'main'
          : branch.text.trim(),
      postsPath: posts.text.trim().isEmpty
          ? 'source/_posts'
          : posts.text.trim(),
      pagesPath: pages.text.trim().isEmpty
          ? 'source'
          : pages.text.trim(),
      frameworkId: frameworkId,
      postDatePrefix: postDatePrefix,
      fileNameRule: FileNameRule(
        postDatePrefix: postDatePrefix,
        dateFormat: existing?.fileNameRule.dateFormat ?? 'yyyy-MM-dd',
      ),
      siteUrl: site.text.trim(),
      token: tokenValue,
      isDefault: existing?.isDefault ?? repos.isEmpty,
      defaultPostTemplateId: defaultPostId,
      defaultPageTemplateId: defaultPageId,
      publishTimeZoneOffsetMinutes: publishTimeZoneOffsetMinutes,
    );
    if (existing == null) {
      repos.add(cfg);
      if (settings.activeRepoId.isEmpty) {
        settings = settings.copyWith(activeRepoId: cfg.id);
        await _persistSettings();
      }
    } else {
      final i = repos.indexWhere((e) => e.id == existing.id);
      if (i >= 0) repos[i] = cfg;
    }
    await _persistRepos();

    if (tokenValue.isNotEmpty) {
      final exists = settings.githubTokens
          .any((e) => e.token == tokenValue);
      if (!exists) {
        await _upsertGithubToken(
          GithubTokenProfile(
            id: 'gh_${DateTime.now().millisecondsSinceEpoch}',
            name: '仓库 ${cfg.name}',
            token: tokenValue,
          ),
          makeActive: settings.githubTokens.isEmpty,
        );
      } else {
        final pickedTokenId = selectedTokenId;
        if (pickedTokenId != null &&
            pickedTokenId.isNotEmpty) {
          await _activateGithubToken(pickedTokenId);
        }
      }
    }

    if (mounted) setState(() {});
  }

  // ============ Commit Rollback ============

  Future<void> _showCommitActions(GitCommitItem c) async {
    final pathController = TextEditingController(
      text: activeRepo == null
          ? 'source/_posts/'
          : '${activeRepo!.postsPath}/',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提交详情 / 回滚'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.message),
            const SizedBox(height: 8),
            Text(
              '${c.sha}\n${c.author} · ${_fmt(c.date)}',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                labelText: '要回滚的文件路径',
                hintText: 'source/_posts/hello-world.md',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _doRollback(
                  pathController.text.trim(), c.sha);
            },
            child: const Text('回滚该文件'),
          ),
        ],
      ),
    );
  }

  Future<void> _rollbackFile(String path) async {
    if (commits.isEmpty) await _refreshCommits();
    if (commits.isEmpty) {
      _showToast('无提交历史');
      return;
    }
    final sha = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView.builder(
        itemCount: commits.length,
        itemBuilder: (_, i) {
          final c = commits[i];
          return ListTile(
            title: Text(c.message.split('\n').first,
                maxLines: 1),
            subtitle: Text(
                '${c.sha.substring(0, 7)} · ${_fmt(c.date)}'),
            onTap: () => Navigator.pop(ctx, c.sha),
          );
        },
      ),
    );
    if (sha != null) await _doRollback(path, sha);
  }

  Future<void> _doRollback(String path, String sha) async {
    final repo = effectiveRepo;
    if (repo == null) return;
    if (path.isEmpty) {
      _showToast('路径不能为空');
      return;
    }
    final ok = await _confirm(
        '将 $path 恢复为 $sha 的内容并新建提交？');
    if (!ok) return;
    setState(() => busy = true);
    try {
      final article =
          await github.rollbackFile(repo, path, sha);
      _showToast('回滚成功: ${article.remotePath}');
      await _refreshRemote();
      await _refreshCommits();
    } catch (e) {
      _showToast('回滚失败: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ============ CMS Remote Post Operations ============

  /// 打开 CMS 远程文章到编辑器（多站点：先切换到文章所属站点）
  void _openRemotePostInEditor(BlogPost post) {
    // 静态站点文章：走 GitHub 文件加载链路
    if (post.siteId != null) {
      final identity = siteManager.getSiteIdentity(post.siteId!);
      if (identity != null && identity.isStatic) {
        _openStaticBlogPostInEditor(post);
        return;
      }
    }
    // 关闭抽屉
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
    // 多站点模式下，切换到文章所属站点，确保后续发布到正确站点
    if (post.siteId != null && siteManager.activeSiteId != post.siteId) {
      final identity = siteManager.getSiteIdentity(post.siteId!);
      if (identity != null && identity.isDynamic) {
        siteManager.setActiveSite(post.siteId!);
      }
    }
    // 将 BlogPost 转为 Article 加载到编辑器
    final article = Article(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: post.title,
      content: post.contentMd,
      tags: post.tags,
      categories: post.categories,
      createdAt: post.date,
      updatedAt: post.modifiedDate,
      isDraft: false,
      published: true,
      articleType: ArticleType.post,
      remotePath: post.link,
      remoteSha: post.id?.toString(),
    );
    _doc.setCurrentArticle(article);
    _editorRepo = null; // CMS 文章不使用 Git 仓库
    _doc.setEditorRepoId(null);
    _startAutoSave();
    _saveSession(SessionPageType.editor);
    setState(() => _currentPage = 0);
    logService.add('加载远程文章', '标题: ${post.title}');
    if (mounted) _showToast('已加载远程文章: ${post.title}');
  }

  /// 删除 CMS 远程文章（多站点：按文章所属站点解析适配器）
  Future<void> _deleteRemoteCmsPost(BlogPost post) async {
    // 静态站点文章无数字 id，需走 GitHub 文件删除链路
    if (post.siteId != null) {
      final identity = siteManager.getSiteIdentity(post.siteId!);
      if (identity != null && identity.isStatic) {
        await _deleteStaticBlogPost(post);
        return;
      }
    }
    if (post.id == null) {
      throw Exception('该文章缺少远程 ID，无法删除');
    }
    BlogRepository? adapter;
    if (post.siteId != null) {
      adapter = siteManager.getAdapter(post.siteId!);
    }
    adapter ??= siteManager.currentAdapter;
    if (adapter == null) return;
    try {
      await adapter.deletePost(post.id!);
      logService.add('删除远程文章', '已从 ${adapter.config.type.name} 删除: ${post.title}');
      if (mounted) _showToast('已删除: ${post.title}');
    } catch (e) {
      logService.add('删除远程文章失败', '$e', success: false);
      rethrow;
    }
  }

  // ============ Remote Delete ============

  Future<void> _deleteRemotePost(GitHubFileItem item) async {
    final repo = effectiveRepo;
    if (repo == null) return;
    final ok = await _confirm(
        '确认删除远程文章 ${item.path}？此操作会提交到 GitHub，不可撤销。');
    if (!ok) return;
    setState(() => busy = true);
    try {
      final article = await github.getArticle(repo, item);
      await github.deleteArticle(repo, article);
      final idx = drafts.indexWhere(
        (d) =>
            d.remotePath == item.path ||
            d.fileName == item.name,
      );
      if (idx >= 0) {
        drafts[idx] = drafts[idx].copyWith(
          isDraft: true,
          published: false,
          remotePath: null,
          remoteSha: null,
        );
        await storage.saveDrafts(drafts);
      }
      _showToast('已删除远程文章');
      await _refreshRemote();
      await _refreshCommits();
    } catch (e) {
      _showToast('删除失败: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _batchDeleteRemote(List<GitHubFileItem> items) async {
    final ok = await _confirm(
        '确认批量删除 ${items.length} 篇远程文章？此操作不可撤销。');
    if (!ok) return;
    setState(() => busy = true);
    int success = 0;
    int fail = 0;
    for (final item in items) {
      try {
        final repo = effectiveRepo;
        if (repo == null) continue;
        final article =
            await github.getArticle(repo, item);
        await github.deleteArticle(repo, article);
        success++;
      } catch (e) { debugPrint('App: site data load failed: $e');
        fail++;
      }
    }
    await _refreshRemote();
    await _refreshCommits();
    if (mounted) {
      setState(() => busy = false);
      _showToast('删除完成: $success 成功, $fail 失败');
    }
  }

  // ============ Import & PWA ============

  Future<void> _showPwaGuide() async {
    final site = activeRepo?.siteUrl.isNotEmpty == true
        ? activeRepo!.siteUrl
        : (settings.sitePreviewUrl.isNotEmpty ? settings.sitePreviewUrl : '');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PWA / 主屏幕快捷方式'),
        content: Text(
          '本 App 负责写作与 Git 发布。\n\n'
          '站点 $site 由 Cloudflare Pages 部署，可在 Chrome/Edge/Safari：\n'
          '1. 打开站点\n'
          '2. 菜单 → 添加到主屏幕 / 安装应用\n'
          '3. 获得 PWA 阅读入口\n\n'
          '写作请继续用本安卓 App（支持离线草稿与 Token 发布）。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: site));
              Navigator.pop(ctx);
              _showToast('站点地址已复制');
            },
            child: const Text('复制站点'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ============ UI BUILD ============

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));

    // ── 专注模式：全屏沉浸式写作 ──
    if (_focusModeEnabled && _currentPage == 0) {
      return _buildFocusMode();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentPage == 0) {
          await _onCloseEditor();
        } else if (_currentPage == 9) {
          _onCloseReader();
        }
        // 其他页面：canPop=false 已阻止退出，不做额外处理
      },
      child: Scaffold(
        key: _scaffoldKey,
        // 编辑页为纯白无缝画布，其余页面保持主题背景
        backgroundColor: _currentPage == 0 ? Colors.white : AppTheme.bg,
        appBar: _buildAppBar(),
        drawer: _buildDrawer(),
        body: _buildPage(),
      ),
    );
  }

  /// 全屏专注模式：隐藏所有 UI 元素，只保留编辑器
  Widget _buildFocusMode() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8F6F0),
      body: SafeArea(
        child: Stack(
          children: [
            // 主编辑区 — 居中、干净
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
              child: TextField(
                controller: _doc.contentCtrl,
                focusNode: _doc.contentFocus,
                minLines: null,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (_) {
                  _onContentChanged();
                  final text = _doc.contentCtrl.text;
                  final cursorPos = _doc.contentCtrl.selection.baseOffset;
                  final textBefore = text.substring(0, cursorPos.clamp(0, text.length));
                  final currentLine = '\n'.allMatches(textBefore).length;
                  final totalLines = '\n'.allMatches(text).length + 1;
                  _typewriterCtrl.updateCursorPosition(currentLine, totalLines);
                },
                decoration: InputDecoration(
                  hintText: '专注写作...',
                  hintStyle: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white24 : Colors.black26,
                    fontWeight: FontWeight.w300,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                style: TextStyle(
                  fontSize: 17,
                  height: 1.8,
                  fontFamily: 'monospace',
                  color: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1A1A2E),
                  fontWeight: FontWeight.w400,
                ),
                cursorColor: isDark ? const Color(0xFF58A6FF) : const Color(0xFF1A6DB5),
                cursorWidth: 2.5,
              ),
            ),

            // 底部状态栏：字数
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '${_editor.wordCount} 字',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white24 : Colors.black26,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ),

            // 顶部退出按钮
            Positioned(
              top: 4,
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: Icon(
                    Icons.fullscreen_exit,
                    color: isDark ? Colors.white38 : Colors.black38,
                    size: 22,
                  ),
                  tooltip: '退出专注模式',
                  onPressed: () => setState(() => _focusModeEnabled = false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.black.withOpacity(0.04),
      leading: IconButton(
        icon: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.menu_rounded, color: cs.primary, size: 20),
        ),
        onPressed: _openDrawer,
      ),
      title: _currentPage == 0
          ? _buildEditorAppBarTitle(cs)
          : Text(_pageTitle,
              style: const TextStyle(
                  color: AppTheme.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
      actions: _currentPage == 0
          ? [
              _WordCountBadge(
                titleCtrl: _doc.titleCtrl,
                contentCtrl: _doc.contentCtrl,
              ),
              _appBarAction(
                  icon: Icons.visibility_outlined,
                  tooltip: '预览',
                  color: cs.primary,
                  onTap: _openArticlePreview),
              _appBarAction(
                  icon: Icons.widgets_outlined,
                  tooltip: '工具箱',
                  color: cs.primary,
                  onTap: () => _showEditorToolbox()),
              _appBarAction(
                  icon: Icons.more_vert,
                  tooltip: '更多',
                  onTap: () => _showEditorMoreMenu()),
            ]
          : null,
    );
  }

  Widget _appBarAction({
    required IconData icon,
    required String tooltip,
    Color? color,
    VoidCallback? onTap,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: color ?? AppTheme.muted, size: 21),
      onPressed: onTap,
      style: IconButton.styleFrom(
        foregroundColor: color ?? AppTheme.muted,
      ),
    );
  }

  /// 极简顶部标识：当前站点名 + 小圆点，取代大标题「写文章」
  Widget _buildEditorAppBarTitle(ColorScheme cs) {
    final siteName = settings.siteName.isNotEmpty ? settings.siteName : '写文章';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: cs.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          siteName,
          style: const TextStyle(
            color: AppTheme.text,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// 工具箱抽屉：静态博客类型 / 目标仓库 / 博文页面设置 / 模板配置 / 标签分类 / 封面 URL
  void _showEditorToolbox() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDynamic = siteManager.isDynamicSite;
          final siteName = settings.siteName.isNotEmpty ? settings.siteName : '未命名站点';
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 头部 ──
                  Row(
                    children: [
                      Icon(Icons.handyman_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      const Text('工具箱',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('当前站点: $siteName',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF64748B))),
                  if (_failedImageBytes != null) ...[
                    const SizedBox(height: 10),
                    Material(
                      color: Colors.orange.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          Navigator.pop(ctx);
                          _retryUploadImage();
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.refresh,
                                  size: 18, color: Colors.orange),
                              SizedBox(width: 8),
                              Text('重试上传失败的图片',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.orange)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ── 1. 静态博客类型切换 ──
                  _toolboxSectionTitle('静态博客类型'),
                  _toolboxSectionBody(
                    child: Row(
                      children: [
                        Expanded(
                          child: _toolboxTypeChip(
                            icon: Icons.article_outlined,
                            label: '博文',
                            active: !isDynamic && _doc.articleType == ArticleType.post,
                            onTap: () => setSheetState(() {
                              _doc.setArticleType(ArticleType.post);
                              _autoSelectTemplate();
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _toolboxTypeChip(
                            icon: Icons.web_outlined,
                            label: '页面',
                            active: !isDynamic && _doc.articleType == ArticleType.page,
                            onTap: () => setSheetState(() {
                              _doc.setArticleType(ArticleType.page);
                              _autoSelectTemplate();
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 2. 目标仓库配置 ──
                  _toolboxSectionTitle('目标仓库配置'),
                  _toolboxSectionBody(
                    child: DropdownButtonFormField<String>(
                      value: _editorRepo?.id,
                      decoration: const InputDecoration(
                        labelText: '目标仓库',
                        prefixIcon:
                            Icon(Icons.storage_outlined, size: 18),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      items: repos
                          .map((r) => DropdownMenuItem(
                                value: r.id,
                                child: Text('${r.name} (${r.fullName})',
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _editorRepo = repos.firstWhere((e) => e.id == v);
                        _doc.setEditorRepoId(v);
                      }),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 3. 博文页面设置（站点切换） ──
                  _toolboxSectionTitle('博文页面设置'),
                  _toolboxSectionBody(
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: siteManager.activeSiteId,
                            decoration: InputDecoration(
                              labelText: '当前站点',
                              prefixIcon: Icon(isDynamic
                                  ? Icons.dns_outlined
                                  : Icons.storage_outlined, size: 18),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            isExpanded: true,
                            style: TextStyle(fontSize: 13, color: cs.onSurface),
                            items: siteManager.allSites.map((site) {
                              final typeLabel = site.isDynamic ? 'CMS' : '静态';
                              return DropdownMenuItem<String>(
                                value: site.id,
                                child: Text('${site.name}  [$typeLabel]',
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: _editorBusy ? null : _onSiteChanged,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.settings_outlined,
                              size: 20, color: cs.outline),
                          onPressed: _editorBusy
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  _openSiteManagement();
                                },
                          tooltip: '管理站点',
                          constraints:
                              const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 4. 模板博文配置 ──
                  _toolboxSectionTitle('模板博文配置'),
                  _toolboxSectionBody(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _doc.selectedTemplateId,
                                decoration: InputDecoration(
                                  labelText:
                                      '模板 (${_doc.articleType == ArticleType.post ? '博文' : '页面'})',
                                  prefixIcon: const Icon(
                                      Icons.view_quilt_outlined, size: 18),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: Text('无模板',
                                        style: TextStyle(fontSize: 13)),
                                  ),
                                  ...templates
                                      .where((t) => t.isPost ==
                                          (_doc.articleType ==
                                              ArticleType.post))
                                      .map((t) => DropdownMenuItem<String>(
                                            value: t.id,
                                            child: Text(
                                              '${t.isBuiltin ? "[内置] " : ""}${t.name}',
                                              style: const TextStyle(
                                                  fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          )),
                                ],
                                onChanged: (v) => setState(
                                    () => _doc.setSelectedTemplateId(v)),
                              ),
                            ),
                            IconButton(
                              tooltip: '设为本仓库默认模板',
                              onPressed: _editorRepo != null &&
                                      _doc.selectedTemplateId != null
                                  ? () => _setAsRepoDefault(
                                      _doc.selectedTemplateId!)
                                  : null,
                              icon: const Icon(Icons.bookmark_add_outlined,
                                  size: 18),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                            ),
                            IconButton(
                              tooltip: '管理模板',
                              onPressed: () => _showTemplateManager(),
                              icon: const Icon(Icons.settings_outlined,
                                  size: 18),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '小字提示：默认模板可在「博文」或「页面」下分别设置，发布时自动套用所选模板生成 front-matter。',
                          style: TextStyle(
                              fontSize: 10, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 5. 标签、分类管理 ──
                  _toolboxSectionTitle('标签、分类管理'),
                  _toolboxSectionBody(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _doc.tagsCtrl,
                            decoration: const InputDecoration(
                              labelText: '标签',
                              prefixIcon: Icon(Icons.tag, size: 18),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _doc.categoriesCtrl,
                            decoration: const InputDecoration(
                              labelText: '分类',
                              prefixIcon: Icon(Icons.folder_outlined,
                                  size: 18),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 6. 封面 URL ──
                  _toolboxSectionTitle('封面图 URL'),
                  _toolboxSectionBody(
                    child: TextField(
                      controller: _doc.coverCtrl,
                      decoration: const InputDecoration(
                        labelText: '封面图 URL（可选）',
                        prefixIcon:
                            Icon(Icons.image_outlined, size: 19),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _toolboxSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B))),
    );
  }

  Widget _toolboxSectionBody({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _toolboxTypeChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? cs.primary.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? cs.primary : const Color(0xFFE2E8F0),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 17,
                color: active ? cs.primary : const Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: active ? cs.primary : const Color(0xFF475569),
                )),
          ],
        ),
      ),
    );
  }

  /// 三点菜单：分层承载文档操作 / 发布渠道 / AI 全功能 / 分享 / 页面操作
  void _showEditorMoreMenu() {
    final cs = Theme.of(context).colorScheme;
    final isDynamic = siteManager.isDynamicSite;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 文档操作 ──
              _menuGroupTitle('文档操作'),
              _menuRow(
                icon: Icons.save_alt,
                label: '保存为 .md 文件',
                color: cs.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  _saveMdBackup();
                },
              ),
              _menuRow(
                icon: Icons.image_outlined,
                label: '导出 PNG 长图',
                color: const Color(0xFF0EA5E9),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportPngLongImage();
                },
              ),
              _menuRow(
                icon: Icons.folder_open_outlined,
                label: '打开存储文件夹',
                color: const Color(0xFF6366F1),
                onTap: () {
                  Navigator.pop(ctx);
                  _openStorageFolder();
                },
              ),
              const Divider(height: 18),
              // ── 发布渠道 ──
              _menuGroupTitle('发布渠道'),
              _menuRow(
                icon: isDynamic
                    ? Icons.cloud_outlined
                    : Icons.cloud_queue_outlined,
                label: isDynamic
                    ? '发布到站点 (${siteManager.currentBlogType.displayName})'
                    : '发布到站点',
                color: const Color(0xFF10B981),
                onTap: () {
                  Navigator.pop(ctx);
                  _publish();
                },
              ),
              _menuRow(
                icon: Icons.upload_file_outlined,
                label: '发布 Git 仓库',
                color: const Color(0xFF6366F1),
                onTap: () {
                  Navigator.pop(ctx);
                  if (siteManager.isDynamicSite) {
                    _showToast('当前为动态站点，发布走「发布到站点」');
                  } else {
                    _publish();
                  }
                },
              ),
              const Divider(height: 18),
              // ── AI 全功能 ──
              _menuGroupTitle('AI 全功能'),
              _menuRow(
                icon: Icons.auto_awesome,
                label: 'AI 全功能入口',
                color: const Color(0xFF8B5CF6),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAiFullMenu();
                },
              ),
              const Divider(height: 18),
              // ── 分享 ──
              _menuGroupTitle('分享'),
              _menuRow(
                icon: Icons.description_outlined,
                label: '分享 MD 文件',
                color: const Color(0xFF0EA5E9),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareMdFile();
                },
              ),
              _menuRow(
                icon: Icons.share_outlined,
                label: '分享本文（纯文本）',
                color: const Color(0xFFF59E0B),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareArticle();
                },
              ),
              const Divider(height: 18),
              // ── 页面操作 ──
              _menuGroupTitle('页面操作'),
              _menuRow(
                icon: Icons.visibility_outlined,
                label: '预览文章',
                color: cs.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  _openArticlePreview();
                },
              ),
              _menuRow(
                icon: Icons.exit_to_app,
                label: '退出编辑',
                color: const Color(0xFFEF4444),
                onTap: () {
                  Navigator.pop(ctx);
                  _onCloseEditor();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuGroupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(title,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: Color(0xFF94A3B8))),
    );
  }

  Widget _menuRow({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF1E293B))),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }

  /// 预览文章（复用原 AppBar 预览逻辑）
  void _openArticlePreview() {
    if (_editorBusy) return;
    final mdStyle = createMobileMarkdownStyle(context: context);
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
              backgroundColor: AppTheme.bg,
              appBar: AppBar(
                  title: Text(_doc.titleCtrl.text.isEmpty
                      ? '预览'
                      : _doc.titleCtrl.text)),
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Markdown(
                    data: _doc.contentCtrl.text.isEmpty
                        ? '*暂无内容*'
                        : _doc.contentCtrl.text,
                    selectable: true,
                    styleSheet: mdStyle),
              ),
            )));
  }

  /// AI 全功能入口：列出全部 AI 功能
  void _showAiFullMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome,
                      color: const Color(0xFF8B5CF6), size: 20),
                  const SizedBox(width: 8),
                  const Text('AI 全功能',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _aiMenuChip('润色', Icons.edit_note, () {
                    Navigator.pop(ctx);
                    _aiAction('polish');
                  }),
                  _aiMenuChip('续写', Icons.auto_awesome, () {
                    Navigator.pop(ctx);
                    _aiAction('continue');
                  }),
                  _aiMenuChip('摘要', Icons.summarize_outlined, () {
                    Navigator.pop(ctx);
                    _aiAction('summary');
                  }),
                  _aiMenuChip('代码', Icons.developer_mode, () {
                    Navigator.pop(ctx);
                    _aiAction('code');
                  }),
                  _aiMenuChip('改写', Icons.sync_alt, () {
                    Navigator.pop(ctx);
                    _aiAction('rewrite');
                  }),
                  _aiMenuChip('排版', Icons.auto_fix_high, () {
                    Navigator.pop(ctx);
                    _aiAction('format');
                  }),
                  _aiMenuChip('对话', Icons.chat, () {
                    Navigator.pop(ctx);
                    _showAiArticleChat();
                  }),
                  _aiMenuChip('选区', Icons.touch_app, () {
                    Navigator.pop(ctx);
                    _showAiSelectionEdit();
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aiMenuChip(String label, IconData icon, VoidCallback onTap) {
    final color = const Color(0xFF8B5CF6);
    return Material(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }

  /// 系统分享当前文章
  Future<void> _shareArticle() async {
    try {
      final a = _collect(draft: true);
      final text = a.content.isNotEmpty
          ? '${a.title.isNotEmpty ? '${a.title}\n\n' : ''}${a.content}'
          : a.title;
      await Share.share(text, subject: a.title);
    } catch (e) {
      if (mounted) _showToast('分享失败: $e');
    }
  }

  /// 生成标准 .md 文件并唤起系统分享（写入 临时分享文件/ 分类目录）
  Future<void> _shareMdFile() async {
    try {
      final a = _collect(draft: true);
      final dir = await storage.shareTempDir();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final safeTitle = a.title.isNotEmpty
          ? a.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          : 'untitled';
      final fileName = '${timestamp}_$safeTitle.md';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(
        a.title.isNotEmpty ? '# ${a.title}\n\n${a.content}' : a.content,
      );
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/markdown')],
        subject: a.title,
        text: a.content.isNotEmpty
            ? '${a.title.isNotEmpty ? '${a.title}\n\n' : ''}${a.content}'
            : a.title,
      );
      if (mounted) _showToast('MD 文件已生成: ${dir.path}/$fileName');
    } catch (e) {
      if (mounted) _showToast('MD 分享失败: $e');
    }
  }

  /// 打开全局存储根目录（原生文件管理器）
  Future<void> _openStorageFolder() async {
    try {
      final dir = await storage.root;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      const channel = MethodChannel('hexo/native');
      final ok = await channel
          .invokeMethod<bool>('openFolder', {'path': dir.path});
      if (ok != true) {
        if (mounted) _showToast('无法打开文件夹: ${dir.path}');
      }
    } catch (e) {
      if (mounted) _showToast('打开文件夹失败: $e');
    }
  }

  /// 导出正文为 PNG 长图（Markdown 渲染后截图保存到 文章长图/）
  Future<void> _exportPngLongImage() async {
    try {
      final a = _collect(draft: false);
      final dir = await storage.longImagesDir();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final safeTitle = a.title.isNotEmpty
          ? a.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          : 'untitled';
      final filePath = '${dir.path}/${timestamp}_$safeTitle.png';

      // 渲染长图：标题 + Markdown 正文
      final mdStyle = createMobileMarkdownStyle(context: context);
      final width = MediaQuery.of(context).size.width;
      final boundaryKey = GlobalKey();

      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => Positioned(
          left: -100000,
          top: 0,
          child: RepaintBoundary(
            key: boundaryKey,
            child: Container(
              width: width,
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (a.title.isNotEmpty)
                    Text(a.title,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.black)),
                  const SizedBox(height: 12),
                  MarkdownBody(
                    data: a.content.isEmpty ? '*（无内容）*' : a.content,
                    styleSheet: mdStyle,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      overlay.insert(entry);
      await Future.delayed(const Duration(milliseconds: 300));
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final file = File(filePath);
          await file.writeAsBytes(byteData.buffer.asUint8List());
          if (mounted) {
            _showToast('PNG 长图已保存到 ${storage.dirLongImages}/$fileName\n${dir.path}');
          }
        }
      }
      entry.remove();
    } catch (e) {
      if (mounted) _showToast('导出失败: $e');
    }
  }

  // ============ DRAWER ============

  Widget _buildDrawer() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.ofContext(context);
    final repoName = activeRepo?.name ?? '未配置';
    final repoFullName = activeRepo?.fullName ?? '';
    final siteName = settings.siteName.isNotEmpty ? settings.siteName : 'Hexo 写作';

    return Drawer(
      backgroundColor: Colors.white,
      width: 280,
      child: SafeArea(
        child: Column(
          children: [
            // ── 渐变色头部 ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, Color.lerp(cs.primary, Colors.indigo, 0.4)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.auto_stories,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 14),
                  Text(siteName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          letterSpacing: -0.2)),
                  const SizedBox(height: 4),
                  Text(repoFullName,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12)),
                ],
              ),
            ),

            // ── 菜单项 ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  _drawerSection(l10n.translate('drawer_section_create')),
                  _drawerItem(0, Icons.edit_square, l10n.translate('nav_write'),
                      isPrimary: true),
                  _drawerItem(1, Icons.drafts_outlined, l10n.translate('nav_drafts'),
                      badge: drafts.where((d) => !d.published).length),
                  const SizedBox(height: 8),
                  _drawerSection(l10n.translate('drawer_section_manage')),
                  _drawerItem(2, Icons.cloud_outlined, l10n.translate('nav_remote')),
                  _drawerAction(Icons.article_outlined, l10n.translate('static_blog_posts'), _showStaticBlogPosts),
                  _drawerAction(Icons.library_books_outlined, l10n.translate('all_blog_manage'), _showAllStaticBlogs),
                  _drawerItem(12, Icons.sync, l10n.translate('nav_sync_status')),
                  _drawerAction(Icons.wifi, l10n.translate('p2p_sync'), _openP2PSync),
                  _drawerItem(3, Icons.dashboard_outlined, l10n.translate('nav_dashboard')),
                  _drawerItem(5, Icons.history_outlined, l10n.translate('nav_history')),
                  const SizedBox(height: 8),
                  _drawerSection(l10n.translate('drawer_section_tools')),
                  _drawerItem(6, Icons.drive_folder_upload, l10n.translate('nav_upload')),
                  _drawerItem(7, Icons.language, l10n.translate('nav_preview')),
                  _drawerItem(4, Icons.rss_feed_outlined, l10n.translate('nav_rss')),
                  _drawerAction(Icons.view_quilt_outlined, l10n.translate('template_manager'), _showTemplateManager),
                  _drawerAction(Icons.content_paste, l10n.translate('snippet_library'), _showSnippetManager),
                  _drawerAction(Icons.settings_applications, l10n.translate('config_editor'), _showSiteConfigEditor),
                  _drawerAction(Icons.swap_horiz, l10n.translate('ai_batch_migrate'), _showMigrationTool),
                  const SizedBox(height: 8),
                  _drawerSection(l10n.translate('drawer_section_ai')),
                  _drawerAction(Icons.assignment_outlined, l10n.translate('agent_workbench'), _showAgentWorkbench),
                  _drawerAction(Icons.article_outlined, l10n.translate('ai_post_create'), _showAiArticleChat),
                  _drawerAction(Icons.web_outlined, l10n.translate('ai_page_create'), _showAiPageChat),
                  _drawerAction(Icons.palette_outlined, l10n.translate('ai_theme_dev'), _showAiThemeChat),
                  _drawerItem(10, Icons.auto_fix_high, l10n.translate('nav_ai_theme_migrate')),
                  _drawerAction(Icons.fact_check_outlined, l10n.translate('ai_site_audit'), _showAiAudit),
                  _drawerAction(Icons.view_quilt_outlined, l10n.translate('ai_templates'), _showAiTemplateChat),
                  _drawerAction(Icons.psychology_outlined, l10n.translate('ai_models'), _showAiModelManager),
                  _drawerAction(Icons.build_outlined, l10n.translate('tool_library'), _showToolLibrary),
                  const SizedBox(height: 8),
                  _drawerSection(l10n.translate('drawer_section_system')),
                  _drawerItem(13, Icons.cloud_sync, l10n.translate('nav_cloud_sync')),
                  _drawerItem(8, Icons.settings_outlined, l10n.translate('nav_settings')),
                  _drawerItem(11, Icons.history, l10n.translate('nav_log')),
                ],
              ),
            ),

            // ── 底部信息 ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: Colors.grey.shade100, width: 1)),
              ),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.storage_outlined,
                      size: 18, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(repoName,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      Text(repoFullName,
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400)),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerSection(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
              letterSpacing: 0.8)),
    );
  }

  Widget _drawerItem(int page, IconData icon, String label,
      {int badge = 0, bool isPrimary = false}) {
    final cs = Theme.of(context).colorScheme;
    final sel = _currentPage == page;
    final bgColor = sel ? cs.primary.withOpacity(0.07) : Colors.transparent;
    final fgColor = sel ? cs.primary : AppTheme.text;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _navigateTo(page),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Icon(icon, size: 20, color: fgColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            sel ? FontWeight.w600 : FontWeight.w400,
                        color: fgColor)),
              ),
              if (badge > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: sel
                        ? cs.primary
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text('$badge',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: sel
                              ? Colors.white
                              : AppTheme.muted)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _drawerAction(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Icon(icon, size: 20, color: AppTheme.text),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppTheme.text)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ============ PAGES ============

  Widget _buildPage() {
    switch (_currentPage) {
      case 0:
        return _buildEditorPage();
      case 1:
        return DraftsScreen(
            drafts: drafts,
            repos: repos,
            blogSiteConfigs: settings.blogSiteConfigs,
            onOpen: (a) {
              _openExistingArticle(a);
            },
            onDelete: _deleteDraft);
      case 2:
        // 远程文章：支持多站点统一聚合（静态博客 + 动态 CMS）
        final allSiteAdapters = _allSiteAdapters;
        final currentAdapter = siteManager.currentAdapter;
        final activeSiteId = siteManager.activeSiteId;
        if (allSiteAdapters.length > 1) {
          // 多站点聚合模式：静态 + 动态统一浏览
          final primary = allSiteAdapters
                  .where((a) => a.config.id == activeSiteId)
                  .firstOrNull ??
              currentAdapter ??
              allSiteAdapters.first;
          if (primary == null) {
            return const Center(child: Text('未配置站点'));
          }
          return RemotePostsScreen(
            adapter: primary,
            allAdapters: allSiteAdapters,
            siteManager: siteManager,
            logService: logService,
            onOpenInEditor: (post) => _openRemotePostInEditor(post),
            onDeletePost: (post) => _deleteRemoteCmsPost(post),
          );
        }
        if (siteManager.isDynamicSite) {
          final adapter = siteManager.currentAdapter;
          if (adapter == null) {
            return const Center(child: Text('未配置 CMS 站点'));
          }
          return RemotePostsScreen(
            adapter: adapter,
            allAdapters: _allCmsAdapters,
            siteManager: siteManager,
            logService: logService,
            onOpenInEditor: (post) => _openRemotePostInEditor(post),
            onDeletePost: (post) => _deleteRemoteCmsPost(post),
          );
        }
        return RemoteScreen(
            posts: remotePosts,
            activeRepo: activeRepo,
            effectiveRepo: effectiveRepo,
            github: github,
            onRefresh: _refreshRemote,
            onOpen: (item) async {
              final repo = effectiveRepo;
              if (repo == null) return;
              try {
                final a = await github.getArticle(repo, item);
                _openExistingArticle(a);
              } catch (e) {
                _showToast('打开失败: $e');
              }
            },
            onDelete: _deleteRemotePost,
            onBatchDelete: _batchDeleteRemote,
            onRollback: _rollbackFile);
      case 3:
        return DashboardScreen(
            drafts: drafts,
            remotePosts: remotePosts,
            commits: commits,
            settings: settings,
            activeRepo: activeRepo,
            onNewPost: () => _navigateTo(0),
            onNavigateToRemote: () => _navigateTo(2),
            onNavigateToHistory: () => _navigateTo(5),
            onNavigateToSettings: () => _navigateTo(8),
            onNavigateToPreview: () => _navigateTo(7),
            onNavigateToDrafts: () => _navigateTo(1));
      case 4:
        return RssScreen(
            items: rssItems,
            activeRepo: activeRepo,
            onRefresh: _refreshRss);
      case 5:
        return HistoryScreen(
            commits: commits,
            github: github,
            effectiveRepo: effectiveRepo,
            onRefresh: _refreshCommits,
            onCommitTap: _showCommitActions);
      case 6:
        return FolderUploadScreen(
            repos: repos,
            github: github,
            activeRepo: effectiveRepo);
      case 7:
        return PreviewScreen(
            activeRepo: activeRepo,
            sitePreviewUrl: settings.sitePreviewUrl);
      case 8:
        return SettingsScreen(
            settings: settings,
            repos: repos,
            github: github,
            storage: storage,
            webdavService: webdavService,
            onSettingsChanged: _updateSettings,
            onReposChanged: _updateRepos,
            onShowWebDavDialog: _showWebDavDialog,
            onSyncWebDavToLocal: _syncWebDavToLocal,
            onSyncDraftsToWebDav: _syncDraftsToWebDav,
            onShowAiManager: _showAiManager,
            onShowLocalModelManager: _showAiModelManager,
            onShowGithubTokenManager: _showGithubTokenManager,
            onShowRepoManager: _showRepoManager,
            onShowSiteEditor: _showSiteEditor,
            onShowThemeColorPicker: _showThemeColorPicker,
            onShowPwaGuide: _showPwaGuide,
            onPersistSettings: _persistSettings,
            onShowToast: _showToast,
            onShowBlogSiteManager: _showBlogSiteManager);
      case 9:
        return ArticleReaderScreen(
          article: _doc.currentArticle,
          onEnterEdit: () => _enterEditorFromReader(_doc.currentArticle),
          onClose: () => _onCloseReader(),
        );
      case 10:
        return ThemeMigrationScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          repos: repos,
          aiService: aiService,
          githubService: github,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          migrationService: themeMigrationService,
          selfChecker: aiSelfChecker,
          onSettingsChanged: _updateSettings,
          storageService: storage,
        );
      case 11:
        return LogScreen(logService: logService);
      case 12:
        if (siteManager.isDynamicSite) {
          final adapter = siteManager.currentAdapter;
          final config = siteManager.currentDynamicConfig;
          if (adapter == null || config == null) {
            return const Center(child: Text('未配置 CMS 站点'));
          }
          return SyncScreen(
            adapter: adapter,
            siteConfig: config,
            syncService: syncService,
            logService: logService,
            localArticles: drafts,
            onOpenArticle: _openExistingArticle,
            onOpenRemotePost: _openRemotePostInEditor,
          );
        }
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sync_disabled, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text('双向同步仅支持动态 CMS 站点',
                  style: TextStyle(color: Colors.grey, fontSize: 14)),
              SizedBox(height: 4),
              Text('请先在设置中添加 WordPress / Ghost / Typecho 站点',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        );
      case 13:
        return SyncSettingsScreen(
          cloudSyncService: cloudSyncService,
          logService: logService,
          settings: settings,
          repos: repos,
          onSettingsChanged: _updateSettings,
          onPushAll: _pushAllToCloud,
          onPullAll: _pullAllFromCloud,
        );
      default:
        return const SizedBox();
    }
  }

  void _openExistingArticle(Article a) {
    // 先关闭抽屉，再切换页面——确保每个页面点击进入时侧边栏完全收回
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
    // 打开阅读页，而不是直接进入编辑器
    _openReader(a);
  }

  // ============ EDITOR PAGE ============

  Widget _buildEditorPage() {
    final cs = Theme.of(context).colorScheme;
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return Column(
      children: [
        if (_editorBusy) const LinearProgressIndicator(minHeight: 2),
        if (_editorBusy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(_editorStatus ?? '处理中...',
                    style: TextStyle(fontSize: 12, color: cs.primary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    _publishCancelToken.cancel();
                    setState(() {
                      _editorBusy = false;
                      _editorStatus = '已取消';
                    });
                  },
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('取消', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            controller: _editorScrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
            children: [
              // ── 标题：无边框、无常驻 label、淡提示 ──
              TextField(
                controller: _doc.titleCtrl,
                decoration: InputDecoration(
                  hintText: '输入标题',
                  hintStyle: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: cs.outlineVariant),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, height: 1.3),
              ),
              const SizedBox(height: 12),
              // ── 正文：无边框、无常驻 label，首次进入显示淡提示，输入后永久隐藏 ──
              OrientationGuard(
                enabled: true,
                child: TextField(
                  controller: _doc.contentCtrl,
                  focusNode: _doc.contentFocus,
                  minLines: 20,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  enabled: !_editorBusy,
                  onChanged: (_) {
                    _onContentChanged();
                    if (!_contentHintDismissed &&
                        _doc.contentCtrl.text.isNotEmpty) {
                      setState(() => _contentHintDismissed = true);
                    }
                    // 更新打字机光标位置
                    final text = _doc.contentCtrl.text;
                    final cursorPos = _doc.contentCtrl.selection.baseOffset;
                    final textBefore =
                        text.substring(0, cursorPos.clamp(0, text.length));
                    final currentLine = '\n'.allMatches(textBefore).length;
                    final totalLines = '\n'.allMatches(text).length + 1;
                    _typewriterCtrl.updateCursorPosition(currentLine, totalLines);
                  },
                  decoration: InputDecoration(
                    hintText:
                        _contentHintDismissed ? null : '开始写作，支持 Markdown 语法...',
                    hintStyle: TextStyle(fontSize: 15, color: cs.outlineVariant),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  style: createUnifiedMarkdownStyle(
                    context: context,
                    config: const UnifiedMarkdownStyleConfig(
                      baseFontSize: 15,
                      lineHeight: 1.7,
                      fontFamily: 'monospace',
                    ),
                  ).p,
                ),
              ),
              if (_editorStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_editorStatus!,
                      style: TextStyle(
                        color: _editorBusy ? cs.primary : cs.outline,
                        fontSize: 12,
                      )),
                ),
            ],
          ),
        ),
        // ── 底部 MD 语法工具栏：键盘弹出时紧贴输入法，平时不占编辑区 ──
        if (keyboardVisible && !_editorBusy) _buildMdToolbar(cs),
      ],
    );
  }

  /// 底部 MD 语法工具栏：紧贴输入法顶部的横向滚动工具条
  Widget _buildMdToolbar(ColorScheme cs) {
    return Container(
      height: 46,
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _toolChip(Icons.format_bold, '粗体', () => _wrap('**', '**', p: '粗体')),
          _toolChip(Icons.format_italic, '斜体', () => _wrap('*', '*', p: '斜体')),
          _toolChip(Icons.code, '行内码', () => _wrap('`', '`', p: 'code')),
          _toolChip(Icons.code_off, '代码块', _insertCodeBlock),
          _toolChip(Icons.title, 'H1', () => _insertHeading(1)),
          _toolChip(Icons.title, 'H2', () => _insertHeading(2)),
          _toolChip(Icons.format_list_bulleted, '列表', () => _insertList('- ')),
          _toolChip(Icons.format_quote, '引用', () => _insertList('> ')),
          _toolChip(Icons.link, '链接', () => _wrap('[', '](https://)', p: '链接文字')),
          _toolChip(Icons.grid_on, '表格', () => _insertText('\n| 列1 | 列2 |\n| --- | --- |\n| 值1 | 值2 |\n')),
          _toolChip(Icons.horizontal_rule, '分割线', () => _insertText('\n---\n')),
          _toolChip(Icons.format_strikethrough, '删除线', () => _wrap('~~', '~~', p: '删除文字')),
          _toolChip(Icons.checklist, '任务', () => _insertList('- [ ] ')),
          _toolChip(Icons.more_horiz, 'more', () => _insertText('\n<!--more-->\n')),
          _toolChip(Icons.image_outlined, '图床', _editorBusy ? null : _insertImage),
          _toolChip(Icons.collections_outlined, '批量图床', _editorBusy ? null : _batchInsertImages),
          _toolChip(Icons.auto_awesome, 'AI润色', _editorBusy ? null : () => _aiAction('polish'), color: Colors.purple),
          _toolChip(Icons.edit_note, 'AI续写', _editorBusy ? null : () => _aiAction('continue'), color: Colors.purple),
          _toolChip(Icons.summarize_outlined, 'AI摘要', _editorBusy ? null : () => _aiAction('summary'), color: Colors.purple),
          _toolChip(Icons.developer_mode, 'AI代码', _editorBusy ? null : () => _aiAction('code'), color: Colors.purple),
          _toolChip(Icons.sync_alt, 'AI改写', _editorBusy ? null : () => _aiAction('rewrite'), color: Colors.purple),
          _toolChip(Icons.auto_fix_high, 'AI排版', _editorBusy ? null : () => _aiAction('format'), color: Colors.deepPurple),
          _toolChip(Icons.chat, 'AI对话', () => _showAiArticleChat(), color: Colors.deepPurple),
          _toolChip(Icons.touch_app, 'AI选区', _editorBusy ? null : _showAiSelectionEdit, color: Colors.deepPurple),
        ],
      ),
    );
  }


  /// 切换站点
  void _onSiteChanged(String? siteId) {
    if (siteId == null || siteId == siteManager.activeSiteId) return;
    siteManager.setActiveSite(siteId);
    final identity = siteManager.currentSiteIdentity;
    if (identity == null) return;

    setState(() {
      // 如果是静态站点，自动设置对应的仓库
      if (identity.isStatic) {
        final repo = repos.firstWhere(
          (r) => r.id == siteId,
          orElse: () => repos.first,
        );
        _editorRepo = repo;
        _doc.setEditorRepoId(repo.id);
      }
      _editorStatus = '已切换到: ${identity.name}';
    });
  }

  /// 打开站点管理面板
  void _openSiteManagement() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SiteManagementScreen(
        siteManager: siteManager,
        repos: repos,
        onChanged: () {
          _persistRepos();
          setState(() {});
        },
      ),
    ));
  }

  Widget _toolChip(IconData icon, String label, VoidCallback? onTap,
      {Color? color}) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Material(
      color: c.withOpacity(0.05),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: c)),
          ]),
        ),
      ),
    );
  }

  // ── 新功能导航 ──

  /// 打开静态博客文章管理界面（一键批量发布已保存的文章）
  Future<void> _showStaticBlogPosts() async {
    if (repos.isEmpty) {
      _showToast('请先在设置中添加仓库');
      return;
    }
    RepoConfig repo;
    if (repos.length == 1) {
      repo = repos.first;
    } else {
      final selected = await showDialog<RepoConfig>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择静态博客仓库'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _showAllStaticBlogs();
              },
              child: const Row(
                children: [
                  Icon(Icons.library_books_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('全部博客管理（聚合所有仓库）'),
                ],
              ),
            ),
            const Divider(height: 1),
            ...repos
                .map((r) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, r),
                      child: Text('${r.name} (${r.fullName})'),
                    ))
                .toList(),
          ],
        ),
      );
      if (selected == null) return;
      repo = selected;
    }
    final resolved = _resolvedRepoFor(repo);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StaticBlogPostsScreen(
          repoConfig: resolved,
          siteManager: siteManager,
          settings: settings,
          githubService: github,
          logService: logService,
          onOpenInEditor: _openStaticBlogPostInEditor,
          onDeletePost: _deleteStaticBlogPost,
        ),
      ),
    );
  }

  /// 打开全部静态博客聚合管理界面（跨仓库批量选择、批量删除）
  Future<void> _showAllStaticBlogs() async {
    if (repos.isEmpty) {
      _showToast('请先在设置中添加仓库');
      return;
    }
    final resolved = repos
        .map(_resolvedRepoFor)
        .toList();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AllStaticBlogsScreen(
          repos: resolved,
          settings: settings,
          githubService: github,
          logService: logService,
          onOpenInEditor: _openStaticBlogPostInEditor,
          onDeletePost: _deleteStaticBlogPost,
        ),
      ),
    );
  }

  /// 在仓库中查找与文章对应的 GitHub 文件项
  Future<GitHubFileItem?> _findStaticFileItem(BlogPost post) async {
    final repo =
        repos.where((r) => r.id == post.siteId).firstOrNull ?? activeRepo;
    if (repo == null) return null;
    final resolved = _resolvedRepoFor(repo);
    final items = await github.listPosts(resolved, recursive: true);
    if (items.isEmpty) return null;
    final slug = post.slug?.toLowerCase().replaceAll(RegExp(r'\.md$'), '');
    final title = post.title.trim();
    return items.where((i) {
      final name = i.name.toLowerCase();
      if (slug != null && name == '$slug.md') return true;
      if (title.isNotEmpty && name == '$title.md') return true;
      return i.path.contains(post.slug ?? post.title);
    }).firstOrNull;
  }

  /// 打开静态博客远程文章到编辑器
  void _openStaticBlogPostInEditor(BlogPost post) {
    _openStaticBlogPostAsync(post);
  }

  Future<void> _openStaticBlogPostAsync(BlogPost post) async {
    try {
      final item = await _findStaticFileItem(post);
      final repo = repos.where((r) => r.id == post.siteId).firstOrNull ?? activeRepo;
      if (item == null || repo == null) {
        _showToast('未在仓库中找到该文章');
        return;
      }
      final article = await github.getArticle(_resolvedRepoFor(repo), item);
      _openExistingArticle(article);
    } catch (e) {
      logService.add('打开静态博客文章失败', '$e', success: false);
      if (mounted) _showToast('打开失败: $e');
    }
  }

  /// 删除静态博客远程文章
  Future<void> _deleteStaticBlogPost(BlogPost post) async {
    final item = await _findStaticFileItem(post);
    final repo = repos.where((r) => r.id == post.siteId).firstOrNull ?? activeRepo;
    if (item == null || repo == null) {
      throw Exception('未在仓库中找到该文章');
    }
    final article = await github.getArticle(_resolvedRepoFor(repo), item);
    await github.deleteArticle(_resolvedRepoFor(repo), article);
  }

  void _showTemplateManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TemplateManagerScreen(
          storage: storage,
          aiService: aiService,
          settings: settings,
          repos: repos,
          githubService: github,
        ),
      ),
    );
    // 刷新模板列表
    final t = await storage.loadAllTemplates();
    if (mounted) {
      // 模板变更后检查降级
      var reposChanged = false;
      for (int i = 0; i < repos.length; i++) {
        final updated = TemplateResolver.ensureTemplateFallback(repos[i], t);
        if (updated != repos[i]) {
          repos[i] = updated;
          reposChanged = true;
        }
      }
      if (reposChanged) await _persistRepos();
      setState(() => templates = t);
    }
  }

  /// 将当前选中的模板设为仓库默认模板
  Future<void> _setAsRepoDefault(String templateId) async {
    final repo = _editorRepo;
    if (repo == null) return;
    final template = templates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => templates.first,
    );
    final isPost = template.isPost;
    final updated = isPost
        ? repo.copyWith(defaultPostTemplateId: templateId)
        : repo.copyWith(defaultPageTemplateId: templateId);

    final idx = repos.indexWhere((r) => r.id == repo.id);
    if (idx >= 0) {
      repos[idx] = updated;
      _editorRepo = updated;
      _doc.setEditorRepoId(updated.id);
      await _persistRepos();
      if (mounted) {
        _showToast('已将「${template.name}」设为仓库默认${isPost ? "文章" : "页面"}模板');
        setState(() {});
      }
    }
  }

  void _showSnippetManager() async {
    // 片段管理器 - 跳转到片段管理对话框
    _showSnippetDialog();
  }

  void _showSnippetDialog() {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String category = '自定义';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('片段素材库'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 已有片段列表
                  if (snippets.isNotEmpty) ...[
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: snippets.length,
                        itemBuilder: (_, i) {
                          final sn = snippets[i];
                          return ListTile(
                            dense: true,
                            title: Text(sn.name, style: const TextStyle(fontSize: 13)),
                            subtitle: Text(sn.category, style: const TextStyle(fontSize: 11)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.content_copy, size: 16),
                                  onPressed: () {
                                    _insertText(sn.content);
                                    Navigator.pop(ctx);
                                  },
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                  onPressed: () async {
                                    snippets.removeAt(i);
                                    await storage.saveSnippets(snippets);
                                    setDialogState(() {});
                                    if (mounted) {
                                      setState(() => this.snippets = List.from(snippets));
                                    }
                                  },
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                            onTap: () {
                              _insertText(sn.content);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                    const Divider(),
                  ],
                  // 新增片段
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '片段名称', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(labelText: '分类', isDense: true),
                    items: const [
                      DropdownMenuItem(value: '友链模板', child: Text('友链模板')),
                      DropdownMenuItem(value: '公告片段', child: Text('公告片段')),
                      DropdownMenuItem(value: '版权声明', child: Text('版权声明')),
                      DropdownMenuItem(value: '代码块', child: Text('代码块')),
                      DropdownMenuItem(value: '自定义提示块', child: Text('自定义提示块')),
                      DropdownMenuItem(value: '自定义', child: Text('自定义')),
                    ],
                    onChanged: (v) {
                      if (v != null) category = v;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: contentCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '片段内容',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final now = DateTime.now();
                  snippets.add(SnippetItem(
                    id: now.millisecondsSinceEpoch.toString(),
                    name: nameCtrl.text.trim(),
                    content: contentCtrl.text,
                    category: category,
                    createdAt: now,
                  ));
                  await storage.saveSnippets(snippets);
                  if (mounted) setState(() => this.snippets = List.from(snippets));
                  Navigator.pop(ctx);
                },
                child: const Text('保存片段'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showConfigEditor() async {
    final repo = effectiveRepo;
    if (repo == null) {
      _showToast('请先配置仓库');
      return;
    }
    try {
      // 尝试读取 _config.yml
      final configPath = repo.frameworkId == 'hugo' ? 'config.toml' : '_config.yml';
      final result = await github.getRawFile(repo, configPath);
      String content = result?['content'] ?? '';
      String sha = result?['sha'] ?? '';

      if (!mounted) return;
      final ctrl = TextEditingController(text: content);
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${repo.frameworkId} 配置编辑'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: TextField(
              controller: ctrl,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '# 站点配置文件',
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                try {
                  await github.putRawFile(
                    repo,
                    configPath,
                    ctrl.text,
                    sha: sha,
                    commitMessage: 'chore: update $configPath',
                  );
                  _showToast('配置已保存');
                  Navigator.pop(ctx, true);
                } catch (e) {
                  _showToast('保存失败: $e');
                }
              },
              child: const Text('保存到GitHub'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showToast('读取配置失败: $e');
    }
  }

  void _showMigrationTool() {
    _navigateTo(10);
  }

  void _showAgentWorkbench() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentWorkbenchScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
        ),
      ),
    );
  }

  void _showAiArticleChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiArticleChatScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          isPage: false,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
        ),
      ),
    );
  }

  void _showAiPageChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiArticleChatScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          isPage: true,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
        ),
      ),
    );
  }

  void _showAiThemeChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiThemeChatScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
        ),
      ),
    );
  }

  void _showAiAudit() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiAuditScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
        ),
      ),
    );
  }

  void _showAiTemplateChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiTemplateChatScreen(
          settings: settings,
          activeRepo: effectiveRepo,
          aiService: aiService,
          modelManager: aiModelManager,
          dispatcher: aiDispatcher,
          selfChecker: aiSelfChecker,
          onSettingsChanged: _updateSettings,
          gitHubService: github,
          storageService: storage,
          onTemplatesChanged: (_) async {
            if (!mounted) return;
            final t = await storage.loadAllTemplates();
            setState(() => templates = t);
          },
        ),
      ),
    );
  }

  void _showAiModelManager() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiModelManagerScreen(
          modelManager: aiModelManager,
          aiService: aiService,
          settings: settings,
          onSettingsChanged: _updateSettings,
          storageService: storage,
        ),
      ),
    );
  }

  void _showToolLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ToolLibraryScreen(skillManager: skillManager),
      ),
    );
  }

  void _showSiteConfigEditor() {
    _showConfigEditor();
  }
}

/// 防抖自动保存条目：捕获定时器触发时应保存的内容，避免串草稿
class _DebounceEntry {
  final String content;
  final String title;
  final Timer timer;

  _DebounceEntry({
    required this.content,
    required this.title,
    required this.timer,
  });

  void cancel() => timer.cancel();
}

/// 顶部栏实时精准字数统计徽标
///
/// - 空白无文字时自动隐藏
/// - 双统计规则：含标点总字符 / 过滤 MD 符号、标点的纯写作文字
/// - 点击数字弹窗，分别查看标题、正文单独字数
class _WordCountBadge extends StatefulWidget {
  final TextEditingController titleCtrl;
  final TextEditingController contentCtrl;

  const _WordCountBadge({
    required this.titleCtrl,
    required this.contentCtrl,
  });

  @override
  State<_WordCountBadge> createState() => _WordCountBadgeState();
}

class _WordCountBadgeState extends State<_WordCountBadge> {
  int _totalChars = 0;
  int _pureChars = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    widget.titleCtrl.addListener(_refresh);
    widget.contentCtrl.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.titleCtrl.removeListener(_refresh);
    widget.contentCtrl.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    final title = widget.titleCtrl.text;
    final content = widget.contentCtrl.text;
    final combined = '$title\n$content';
    final stats = countWords(combined);
    if (stats.totalChars == _totalChars && stats.pureChars == _pureChars) return;
    setState(() {
      _totalChars = stats.totalChars;
      _pureChars = stats.pureChars;
    });
  }

  void _showDetail() {
    final titleStats = countWords(widget.titleCtrl.text);
    final contentStats = countWords(widget.contentCtrl.text);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('字数统计'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statRow('标题', titleStats),
            const Divider(height: 20),
            _statRow('正文', contentStats),
            const Divider(height: 20),
            _statRow('总计', countWords('${widget.titleCtrl.text}\n${widget.contentCtrl.text}')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, WordCountResult stats) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(
              '总字符 ${stats.totalChars}  ·  纯写作 ${stats.pureChars}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_totalChars == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _showDetail,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_totalChars',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    height: 1.1),
              ),
              const SizedBox(height: 1),
              Text(
                '纯$_pureChars',
                style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                    height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
