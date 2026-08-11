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
import 'models/editor_theme.dart';
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

part 'mixins/editor_publish_ext.dart';
part 'mixins/editor_sync_ext.dart';
part 'mixins/settings_dialogs_ext.dart';
part 'mixins/editor_ui_ext.dart';
part 'mixins/editor_text_ext.dart';

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
          initialSettings: _settings,
        ),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  final void Function(Color) onThemeChanged;
  final void Function(AppSettings)? onSettingsChanged;
  final AppSettings initialSettings;
  const RootShell({
    super.key,
    required this.onThemeChanged,
    this.onSettingsChanged,
    required this.initialSettings,
  });

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  /// 供 extension 内部调用的 setState 包装（避开 protected 限制）
  void _applyState(VoidCallback fn) => setState(fn);

  final storage = StorageService();
  final github = GitHubService();
  late final imageService = ImageService(github);
  final aiService = AiService();
  late final aiModelManager = AiModelManager(storage);
  late final siteDispatcherManager = SiteDispatcherManager(
    aiService,
    aiModelManager,
  );
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
      result.add(
        StaticBlogRepository(
          repoConfig: _resolvedRepoFor(repo),
          appSettings: settings,
          githubService: github,
          logService: logService,
        ),
      );
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
    _p2pSyncService = P2PSyncService(
      deviceName: 'Mobile-${DateTime.now().millisecondsSinceEpoch}',
    );
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
    _updateSystemBarStyle();
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
          ),
        ];
        await storage.saveRepos(r);
        s = s.copyWith(
          activeRepoId: r.first.id,
          imageBedOwner: 'caogenfunan123',
          imageBedRepo: 'xiamend',
        );
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
        autoTemplateId = TemplateResolver.resolvePostTemplateId(
          _editorRepo!,
          t,
        );
        _doc.setSelectedTemplateId(autoTemplateId);
      }

      // 同步到站点控制器
      final staticSites = r
          .map(
            (repo) => SiteConfig(
              id: repo.id,
              name: repo.name,
              repoUrl: 'https://github.com/${repo.owner}/${repo.repo}',
              branch: repo.branch,
              isDefault: repo.isDefault,
              isStatic: true,
              tokenId: repo.token.isNotEmpty ? repo.id : null,
            ),
          )
          .toList();
      final dynamicSites = s.blogSiteConfigs
          .map(
            (cfg) => SiteConfig(
              id: cfg.id,
              name: cfg.name,
              repoUrl: cfg.siteUrl,
              isStatic: false,
            ),
          )
          .toList();
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
      if (mounted)
        setState(() {
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




  AppSettings _ensureGithubTokensFromLegacy(
    AppSettings s,
    List<RepoConfig> repos,
  ) {
    return ensureGithubTokensFromLegacy(s, repos);
  }

  void _navigateTo(int page) {
    // 离开编辑器时停止自动保存
    if (_currentPage == 0 && page != 0) {
      _stopAutoSave();
    }
    setState(() => _currentPage = page);
    _updateSystemBarStyle();
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


  /// 点击 × 关闭按钮 → 退出弹窗 → 回到写文章首页
  Future<void> _onCloseEditor() async {
    final ok = await _showExitDialog();
    if (!ok) return;
    _stopAutoSave();
    await _clearSession();
    _resetEditor();
    setState(() => _currentPage = 0);
    _updateSystemBarStyle();
  }

  Future<void> _onCloseReader() async {
    await _clearSession();
    setState(() => _currentPage = 0);
    _updateSystemBarStyle();
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



  // ============ 自动保存 ============






  // ============ 阅读页 / 编辑器切换 ============




  RepoConfig? get _resolvedRepo {
    final r = _editorRepo;
    if (r == null) return null;
    if (r.token.isNotEmpty) return r;
    final t = settings.effectiveGithubToken;
    if (t.isEmpty) return r;
    return r.copyWith(token: t);
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
                      Clipboard.setData(ClipboardData(text: result));
                      Navigator.pop(context);
                    },
                    child: const Text('复制'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            );
          break;
        case 'outline':
          result = await aiService.generateOutline(
            settings,
            _doc.titleCtrl.text.isEmpty ? text : _doc.titleCtrl.text,
          );
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
                decoration: const InputDecoration(hintText: '描述需要的代码'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('生成'),
                ),
              ],
            ),
          );
          if (ok != true) {
            ctrl.dispose();
            break;
          }
          result = await aiService.generateCode(
            settings,
            ctrl.text.trim().isEmpty ? '写一段示例代码' : ctrl.text.trim(),
          );
          ctrl.dispose();
          _insertText('\n\n$result\n');
          break;
        case 'rewrite':
          final sel = _doc.contentCtrl.selection;
          if (!sel.isValid || sel.start == sel.end) {
            throw Exception('请先选中要改写的文字');
          }
          final selected = text.substring(sel.start, sel.end);
          final instrCtrl = TextEditingController(text: '更简洁专业');
          final ok2 = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('AI 改写'),
              content: TextField(controller: instrCtrl),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('改写'),
                ),
              ],
            ),
          );
          if (ok2 != true) {
            instrCtrl.dispose();
            break;
          }
          result = await aiService.rewriteSelection(
            settings,
            selected,
            instrCtrl.text.trim(),
          );
          instrCtrl.dispose();
          final txt = _doc.contentCtrl.text;
          _doc.contentCtrl.value = TextEditingValue(
            text: txt.replaceRange(sel.start, sel.end, result),
            selection: TextSelection.collapsed(
              offset: sel.start + result.length,
            ),
          );
          _doc.contentFocus.requestFocus();
          _onContentChanged();
          break;
        case 'format':
          result = await aiService.polish(
            settings,
            '请对以下 Markdown 内容进行排版优化：统一标题层级、规范空行、修正列表缩进、对齐表格格式。\n\n$text',
          );
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
              offset: sel.start + acceptedText.length,
            ),
          );
          _doc.contentFocus.requestFocus();
          _onContentChanged();
        },
      ),
    );
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


  Future<void> _updateRepos(List<RepoConfig> r) async {
    setState(() => repos = r);
    _updateSiteManager();
    await storage.saveRepos(r);
  }

  Future<void> _persistSettings() => storage.saveSettings(settings);
  Future<void> _persistRepos() => storage.saveRepos(repos);


  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
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
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
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




  // ============ 云同步 ============



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
      '天蓝',
      '靛蓝',
      '紫色',
      '粉色',
      '玫瑰红',
      '翡翠绿',
      '青绿',
      '琥珀',
      '石板灰',
      '深灰',
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
                  settings = settings.copyWith(themeColor: colors[i].value);
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
                            ? Border.all(color: Colors.black, width: 2.5)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(names[i], style: const TextStyle(fontSize: 11)),
                  ],
                ),
              );
            }),
          ),
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

  // ============ Site Editor ============



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


  Future<AiProfile?> _editAiProfile(AiProfile? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '中转站');
    final baseCtrl = TextEditingController(
      text: existing?.baseUrl.isNotEmpty == true
          ? existing!.baseUrl
          : (settings.aiBaseUrl.isNotEmpty
                ? settings.aiBaseUrl
                : 'https://api.openai.com/v1'),
    );
    final keyCtrl = TextEditingController(
      text: existing?.apiKey.isNotEmpty == true
          ? existing!.apiKey
          : settings.aiApiKey,
    );
    final modelCtrl = TextEditingController(
      text: existing?.model ?? settings.aiModel,
    );
    var models = List<String>.from(existing?.cachedModels ?? const <String>[]);
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
                final list = await AiService().listModels(
                  settings,
                  profile: temp,
                );
                setDlg(() {
                  models = list;
                  if (selectedModel.isEmpty && list.isNotEmpty) {
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
              title: Text(existing == null ? '新增 AI 配置' : '编辑 AI 配置'),
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
                          hintText: '如 DeepSeek / 硅基流动 / 自建中转',
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
                        subtitle: const Text('关闭则同时发送 api-key / x-api-key'),
                        value: useBearer,
                        onChanged: (v) => setDlg(() => useBearer = v),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: modelCtrl,
                              decoration: const InputDecoration(
                                labelText: '模型',
                                hintText: '可手动填写或从列表选择',
                              ),
                              onChanged: (v) => selectedModel = v.trim(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: fetching ? null : fetchModels,
                            child: fetching
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('获取模型'),
                          ),
                        ],
                      ),
                      if (err != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          err!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (models.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: models.contains(selectedModel)
                              ? selectedModel
                              : null,
                          decoration: const InputDecoration(
                            labelText: '从列表选择模型',
                          ),
                          items: models
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(
                                    m,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
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
                  child: const Text('取消'),
                ),
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
                    final id =
                        existing?.id ??
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
    final list = List<GithubTokenProfile>.from(settings.githubTokens);
    final byToken = list.indexWhere((e) => e.token == profile.token);
    final byId = list.indexWhere((e) => e.id == profile.id);
    if (byId >= 0) {
      list[byId] = profile;
    } else if (byToken >= 0) {
      list[byToken] = profile.copyWith(id: list[byToken].id);
    } else {
      list.add(profile);
    }
    final activeId = makeActive || settings.activeGithubTokenId.isEmpty
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


  Future<GithubTokenProfile?> _editGithubToken(
    GithubTokenProfile? existing,
  ) async {
    final nameCtrl = TextEditingController(
      text: existing?.name.isNotEmpty == true
          ? existing!.name
          : (existing?.login.isNotEmpty == true
                ? existing!.login
                : 'GitHub Token'),
    );
    final tokenCtrl = TextEditingController(text: existing?.token ?? '');
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
                avatarUrl = user['avatar_url']?.toString() ?? '';
                htmlUrl = user['html_url']?.toString() ?? '';
                if (nameCtrl.text.trim().isEmpty ||
                    nameCtrl.text.trim() == 'GitHub Token' ||
                    nameCtrl.text.trim() == '默认 Token') {
                  if (login.isNotEmpty) nameCtrl.text = login;
                }
                setDlg(() => verifying = false);
                _showToast(login.isEmpty ? 'Token 有效' : '验证成功 · @$login');
              } catch (e) {
                setDlg(() {
                  verifying = false;
                  err = e.toString();
                });
              }
            }

            return AlertDialog(
              title: Text(existing == null ? '登录 GitHub Token' : '编辑 Token'),
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
                          hintText: 'ghp_... 或 fine-grained token',
                          helperText: '需要 contents:read/write 权限',
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (login.isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.account_circle_outlined),
                          title: Text('@$login'),
                          subtitle: Text(htmlUrl.isEmpty ? '已验证' : htmlUrl),
                        ),
                      if (err != null)
                        Text(
                          err!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: verifying ? null : verifyAndFill,
                          icon: verifying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.verified_user_outlined),
                          label: Text(verifying ? '验证中…' : '验证并识别账号'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
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
                              final user = await github.getUser(token);
                              login = user['login']?.toString() ?? '';
                              avatarUrl = user['avatar_url']?.toString() ?? '';
                              htmlUrl = user['html_url']?.toString() ?? '';
                            } catch (e) {
                              final force = await _confirm(
                                'Token 校验失败：\n$e\n\n仍要保存吗？',
                              );
                              if (!force) return;
                            }
                          }
                          final name = nameCtrl.text.trim().isEmpty
                              ? (login.isNotEmpty ? login : 'GitHub Token')
                              : nameCtrl.text.trim();
                          Navigator.pop(
                            ctx,
                            GithubTokenProfile(
                              id:
                                  existing?.id ??
                                  'gh_${DateTime.now().millisecondsSinceEpoch}',
                              name: name,
                              token: token,
                              login: login,
                              avatarUrl: avatarUrl,
                              htmlUrl: htmlUrl,
                              lastVerifiedAt: login.isNotEmpty
                                  ? DateTime.now()
                                  : existing?.lastVerifiedAt,
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


  Future<void> _editRepo({RepoConfig? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final owner = TextEditingController(
      text: existing?.owner ?? 'caogenfunan123',
    );
    final repo = TextEditingController(text: existing?.repo ?? 'xiamend');
    final branch = TextEditingController(text: existing?.branch ?? 'main');
    final posts = TextEditingController(
      text: existing?.postsPath ?? 'source/_posts',
    );
    final pages = TextEditingController(text: existing?.pagesPath ?? 'source');
    final site = TextEditingController(
      text: existing?.siteUrl.isNotEmpty == true ? existing!.siteUrl : '',
    );
    final token = TextEditingController(
      text: existing?.token.isNotEmpty == true
          ? existing!.token
          : settings.effectiveGithubToken,
    );
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
              title: Text(existing == null ? '添加仓库' : '编辑仓库'),
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
                        ...BlogFramework.presets.map(
                          (f) => DropdownMenuItem(
                            value: f.id,
                            child: Text('${f.name} (${f.defaultPostsPath})'),
                          ),
                        ),
                        const DropdownMenuItem(
                          value: 'custom',
                          child: Text('自定义'),
                        ),
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
                        helperText:
                            'Front Matter 日期带该时区偏移，避免 Cloudflare(UTC) 构建日期错位',
                        prefixIcon: Icon(Icons.schedule, size: 18),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('UTC (UTC+0)')),
                        DropdownMenuItem(value: 480, child: Text('北京 (UTC+8)')),
                        DropdownMenuItem(value: 540, child: Text('东京 (UTC+9)')),
                        DropdownMenuItem(
                          value: 600,
                          child: Text('悉尼 (UTC+10)'),
                        ),
                        DropdownMenuItem(
                          value: -300,
                          child: Text('纽约 (UTC-5)'),
                        ),
                        DropdownMenuItem(
                          value: -480,
                          child: Text('洛杉矶 (UTC-8)'),
                        ),
                        DropdownMenuItem(
                          value: 330,
                          child: Text('孟买 (UTC+5:30)'),
                        ),
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
                      decoration: const InputDecoration(labelText: '显示名称'),
                    ),
                    TextField(
                      controller: owner,
                      decoration: const InputDecoration(labelText: 'Owner'),
                    ),
                    TextField(
                      controller: repo,
                      decoration: const InputDecoration(labelText: 'Repo'),
                    ),
                    TextField(
                      controller: branch,
                      decoration: const InputDecoration(labelText: 'Branch'),
                    ),
                    // ── 双目录配置 ──
                    TextField(
                      controller: posts,
                      decoration: const InputDecoration(
                        labelText: '博文目录 (posts)',
                        helperText: '例如: source/_posts, content/posts',
                      ),
                    ),
                    TextField(
                      controller: pages,
                      decoration: const InputDecoration(
                        labelText: '页面目录 (pages)',
                        helperText: '例如: source, content',
                      ),
                    ),
                    // ── 文件名规则 ──
                    CheckboxListTile(
                      title: const Text('博文自动日期前缀'),
                      subtitle: const Text('2026-08-02-title.md (Jekyll/Hugo)'),
                      value: postDatePrefix,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) =>
                          setDlg(() => postDatePrefix = v ?? false),
                    ),
                    TextField(
                      controller: site,
                      decoration: const InputDecoration(labelText: '站点 URL'),
                    ),
                    if (settings.githubTokens.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value:
                            settings.githubTokens.any(
                              (e) => e.id == selectedTokenId,
                            )
                            ? selectedTokenId
                            : null,
                        decoration: const InputDecoration(
                          labelText: '选用已登录 Token',
                          helperText: '可选择已保存令牌，或下方手动填写',
                        ),
                        items: [
                          ...settings.githubTokens.map(
                            (t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(
                                t.displayLabel,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          final t = settings.githubTokens.firstWhere(
                            (e) => e.id == v,
                          );
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
                        labelText: 'GitHub Token',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存'),
                ),
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
      updateTemplates =
          await showDialog<bool>(
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
      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.text.trim().isEmpty ? repo.text.trim() : name.text.trim(),
      owner: owner.text.trim(),
      repo: repo.text.trim(),
      branch: branch.text.trim().isEmpty ? 'main' : branch.text.trim(),
      postsPath: posts.text.trim().isEmpty
          ? 'source/_posts'
          : posts.text.trim(),
      pagesPath: pages.text.trim().isEmpty ? 'source' : pages.text.trim(),
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
      final exists = settings.githubTokens.any((e) => e.token == tokenValue);
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
        if (pickedTokenId != null && pickedTokenId.isNotEmpty) {
          await _activateGithubToken(pickedTokenId);
        }
      }
    }

    if (mounted) setState(() {});
  }

  // ============ Commit Rollback ============

  Future<void> _showCommitActions(GitCommitItem c) async {
    final pathController = TextEditingController(
      text: activeRepo == null ? 'source/_posts/' : '${activeRepo!.postsPath}/',
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
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _doRollback(pathController.text.trim(), c.sha);
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
            title: Text(c.message.split('\n').first, maxLines: 1),
            subtitle: Text('${c.sha.substring(0, 7)} · ${_fmt(c.date)}'),
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
    final ok = await _confirm('将 $path 恢复为 $sha 的内容并新建提交？');
    if (!ok) return;
    setState(() => busy = true);
    try {
      final article = await github.rollbackFile(repo, path, sha);
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
    _updateSystemBarStyle();
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
      logService.add(
        '删除远程文章',
        '已从 ${adapter.config.type.name} 删除: ${post.title}',
      );
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
    final ok = await _confirm('确认删除远程文章 ${item.path}？此操作会提交到 GitHub，不可撤销。');
    if (!ok) return;
    setState(() => busy = true);
    try {
      final article = await github.getArticle(repo, item);
      await github.deleteArticle(repo, article);
      final idx = drafts.indexWhere(
        (d) => d.remotePath == item.path || d.fileName == item.name,
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
    final ok = await _confirm('确认批量删除 ${items.length} 篇远程文章？此操作不可撤销。');
    if (!ok) return;
    setState(() => busy = true);
    int success = 0;
    int fail = 0;
    for (final item in items) {
      try {
        final repo = effectiveRepo;
        if (repo == null) continue;
        final article = await github.getArticle(repo, item);
        await github.deleteArticle(repo, article);
        success++;
      } catch (e) {
        debugPrint('App: site data load failed: $e');
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
              Clipboard.setData(ClipboardData(text: site));
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

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
        // 编辑页为全屏主题画布（透明承载背景层），其余页面保持主题背景
        backgroundColor: _currentPage == 0 ? Colors.transparent : AppTheme.bg,
        appBar: _buildAppBar(),
        drawer: _buildDrawer(),
        body: _buildPage(),
      ),
    );
  }


  PreferredSizeWidget _buildAppBar() {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: _currentPage == 0 ? Colors.transparent : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.black.withOpacity(0.04),
      leading: IconButton(
        icon: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: globalTextColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.menu_rounded,
            color: _currentPage == 0 ? globalTextColor : cs.primary,
            size: 20,
          ),
        ),
        onPressed: _openDrawer,
      ),
      title: _currentPage == 0
          ? _buildEditorAppBarTitle(cs)
          : Text(
              _pageTitle,
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
      actions: _currentPage == 0
          ? [
              _WordCountBadge(
                titleCtrl: _doc.titleCtrl,
                contentCtrl: _doc.contentCtrl,
                textColor: globalTextColor,
              ),
              _appBarAction(
                icon: Icons.visibility_outlined,
                tooltip: '预览',
                color: globalTextColor,
                onTap: _openArticlePreview,
              ),
              _appBarAction(
                icon: Icons.widgets_outlined,
                tooltip: '工具箱',
                color: globalTextColor,
                onTap: () => _showEditorToolbox(),
              ),
              _appBarAction(
                icon: Icons.more_vert,
                tooltip: '更多',
                color: globalTextColor,
                onTap: () => _showEditorMoreMenu(),
              ),
              _appBarAction(
                icon: Icons.widgets_outlined,
                tooltip: '工具箱',
                color: cs.primary,
                onTap: () => _showEditorToolbox(),
              ),
              _appBarAction(
                icon: Icons.more_vert,
                tooltip: '更多',
                onTap: () => _showEditorMoreMenu(),
              ),
            ]
          : null,
    );
  }










  /// 预览文章（复用原 AppBar 预览逻辑）
  void _openArticlePreview() {
    if (_editorBusy) return;
    final mdStyle = createMobileMarkdownStyle(context: context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: AppBar(
            title: Text(
              _doc.titleCtrl.text.isEmpty ? '预览' : _doc.titleCtrl.text,
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Markdown(
              data: _doc.contentCtrl.text.isEmpty
                  ? '*暂无内容*'
                  : _doc.contentCtrl.text,
              selectable: true,
              styleSheet: mdStyle,
            ),
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
      final ok = await channel.invokeMethod<bool>('openFolder', {
        'path': dir.path,
      });
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
                    Text(
                      a.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
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
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final file = File(filePath);
          await file.writeAsBytes(byteData.buffer.asUint8List());
          if (mounted) {
            _showToast(
              'PNG 长图已保存到 ${StorageService.dirLongImages}/\n$filePath',
            );
          }
        }
      }
      entry.remove();
    } catch (e) {
      if (mounted) _showToast('导出失败: $e');
    }
  }

  // ============ DRAWER ============


  Widget _drawerSection(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.muted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _drawerItem(
    int page,
    IconData icon,
    String label, {
    int badge = 0,
    bool isPrimary = false,
  }) {
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: fgColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      color: fgColor,
                    ),
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? cs.primary : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: sel ? Colors.white : AppTheme.muted,
                      ),
                    ),
                  ),
              ],
            ),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.text),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============ PAGES ============


  void _openExistingArticle(Article a) {
    // 先关闭抽屉，再切换页面——确保每个页面点击进入时侧边栏完全收回
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
    // 打开阅读页，而不是直接进入编辑器
    _openReader(a);
  }

  // ============ EDITOR PAGE ============

  /// 当前站点标识：动态站点用类型名，静态站点用仓库名
  String get _currentSiteLabel {
    if (siteManager.isDynamicSite) {
      return siteManager.currentBlogType.displayName;
    }
    return _resolvedRepo?.name ?? '我的博客';
  }

  // ============================================================
  // 编辑器主题（写作界面全屏背景 + 全局文字色）
  // ============================================================

  EditorTheme get _editorTheme => settings.ui.editorTheme;

  /// 编辑器背景颜色：纯白 / 纯黑，壁纸模式下返回透明底色
  Color get _editorBgColor {
    return switch (_editorTheme.bgMode) {
      1 => const Color(0xFF000000),
      _ => Colors.white,
    };
  }

  /// 全局文字颜色：强制黑白 > 自动适配背景亮度
  Color get globalTextColor {
    final mode = _editorTheme.forceTextMode;
    if (mode == 1) return Colors.black;
    if (mode == 2) return Colors.white;
    if (_editorTheme.bgMode == 2 && _wallpaperPath.isNotEmpty) {
      return _wallpaperTextColor;
    }
    return _editorBgColor.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
  }

  /// 壁纸路径
  String get _wallpaperPath => _editorTheme.wallpaperPath;

  /// 壁纸模式下自动适配的文字颜色（固定按亮度估算：壁纸视为中等亮度，默认黑字）
  Color get _wallpaperTextColor => Colors.black;

  /// 是否使用深色系统栏图标（浅背景黑字时用深色图标）
  bool get _useDarkSystemIcons => globalTextColor.computeLuminance() > 0.5;

  /// 同步系统栏样式：编辑页跟随主题，其余页面恢复浅色默认
  void _updateSystemBarStyle() {
    if (_currentPage != 0) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );
      return;
    }
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: _useDarkSystemIcons
            ? Brightness.dark
            : Brightness.light,
        statusBarBrightness: _useDarkSystemIcons
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarIconBrightness: _useDarkSystemIcons
            ? Brightness.dark
            : Brightness.light,
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SiteManagementScreen(
          siteManager: siteManager,
          repos: repos,
          onChanged: () {
            _persistRepos();
            setState(() {});
          },
        ),
      ),
    );
  }

  Widget _toolChip(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    Color? color,
  }) {
    final c = color ?? globalTextColor;
    return Material(
      color: c.withOpacity(0.05),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: c),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: c,
                ),
              ),
            ],
          ),
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
                .map(
                  (r) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, r),
                    child: Text('${r.name} (${r.fullName})'),
                  ),
                )
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
    final resolved = repos.map(_resolvedRepoFor).toList();
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
      final repo =
          repos.where((r) => r.id == post.siteId).firstOrNull ?? activeRepo;
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
    final repo =
        repos.where((r) => r.id == post.siteId).firstOrNull ?? activeRepo;
    if (item == null || repo == null) {
      throw Exception('未在仓库中找到该文章');
    }
    final article = await github.getArticle(_resolvedRepoFor(repo), item);
    await github.deleteArticle(_resolvedRepoFor(repo), article);
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


  void _showToolLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ToolLibraryScreen(skillManager: skillManager),
      ),
    );
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
  final Color textColor;

  const _WordCountBadge({
    required this.titleCtrl,
    required this.contentCtrl,
    this.textColor = const Color(0xFF94A3B8),
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
    if (stats.totalChars == _totalChars && stats.pureChars == _pureChars)
      return;
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
            _statRow(
              '总计',
              countWords(
                '${widget.titleCtrl.text}\n${widget.contentCtrl.text}',
              ),
            ),
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
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              '总字符 ${stats.totalChars}  ·  纯写作 ${stats.pureChars}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_totalChars == 0) return const SizedBox.shrink();
    // 淡色小字，紧贴右上角三点菜单角落；空白无文字时自动隐藏
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _showDetail,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Text(
            '$_totalChars',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: widget.textColor,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
