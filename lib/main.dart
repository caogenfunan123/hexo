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
part 'mixins/editor_ai_ext.dart';
part 'mixins/editor_repo_ext.dart';
part 'mixins/editor_remote_ext.dart';

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




  // ============ AI Profile Management ============



  // ============ GitHub Token Management ============





  // ============ Repo Management ============



  // ============ Commit Rollback ============




  // ============ CMS Remote Post Operations ============



  // ============ Remote Delete ============



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
