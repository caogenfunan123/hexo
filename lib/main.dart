import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:file_picker/file_picker.dart';

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
import 'models/git_provider.dart';
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
import 'core/task/agent_task_type.dart';
import 'screens/agent_workbench_screen.dart';
import 'screens/ai_article_chat_screen.dart';
import 'screens/ai_model_manager_screen.dart';
import 'screens/article_reader_screen.dart';
import 'screens/blog_site_editor_screen.dart';
import 'screens/drafts_screen.dart';
import 'screens/theme_store_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/remote_posts_screen.dart';
import 'screens/all_static_blogs_screen.dart';
import 'screens/all_features_screen.dart';
import 'models/nav_custom_config.dart';
import 'desktop/nav_entries_meta.dart';
import 'desktop/shell_action_bus.dart';
import 'desktop/widgets/sidebar_customize_dialog.dart';
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
import 'screens/local_file_zone_screen.dart';
import 'screens/mobile_recycle_bin_screen.dart';
import 'core/tools/skill_manager.dart';
import 'core/tools/remote_cms_tools.dart';
import 'core/cancel_token.dart';
import 'core/shared_bootstrap.dart';
import 'core/site_manager.dart';
import 'core/repository/blog_repository.dart';
import 'core/repository/static_blog_repository.dart';
import 'services/ai_service.dart';
import 'services/github_service.dart';
import 'services/git_providers.dart';
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
import 'widgets/quick_note_floater.dart';
import 'widgets/ai_selection_edit_mobile.dart';
import 'services/site_isolation_service.dart';
import 'services/p2p_sync_service.dart';
import 'screens/p2p_sync_screen.dart';
import 'services/template_sync_service.dart';
import 'services/full_text_search_isolate.dart';
import 'services/recycle_bin_service.dart';
import 'services/quick_note_service.dart';
import 'services/timestamp_util.dart';
import 'services/writing_stats_service.dart';
import 'core/utils/abi_util.dart';
import 'services/update_checker_service.dart';
import 'services/draft_encryption_service.dart';
import 'services/version_snapshot_service.dart';
import 'widgets/word_count_badge.dart';
import 'widgets/markdown_preview_webview.dart';
import 'widgets/markdown_preview_smooth.dart';
import 'screens/home_screen.dart';
import 'models/ui_settings.dart';
import 'desktop/feature_entries.dart';

part 'mixins/editor_publish_ext.dart';
part 'mixins/editor_sync_ext.dart';
part 'mixins/settings_dialogs_ext.dart';
part 'mixins/editor_ui_ext.dart';
part 'mixins/editor_text_ext.dart';
part 'mixins/editor_ai_ext.dart';
part 'mixins/editor_repo_ext.dart';
part 'mixins/editor_remote_ext.dart';
part 'mixins/editor_misc_ext.dart';
part 'mixins/editor_drawer_ext.dart';

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

  // ── 抽屉分区折叠状态（按分区 key 独立折叠） ──
  final Set<String> _drawerCollapsed = {};

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
  QuickNoteService? _quickNoteService; // ignore: unused_field 保持监听器生命周期
  StreamSubscription<QuickNoteRequest>? _quickNoteSub;
  bool _quickNoteInited = false;
  static const MethodChannel _fileOpenChannel = MethodChannel('hexo/file_open');
  bool _fileOpenInited = false;
  WritingStatsService? _statsService;

  /// 每个草稿上次统计的字数（用于记录增量，避免重复累计）
  final Map<String, int> _lastWordCounts = {};
  UpdateCheckerService? _updateChecker;
  String _appVersion = '1.0.10';

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
      case 14:
        return l10n.translate('nav_home');
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
    aiService.modelManager = aiModelManager;
    // 提前注册速记通道（小部件/磁贴深链），不再依赖 bootstrap 尾部初始化：
    // 拉得越早，冷启动深链消费越快；配合 resumed 补拉彻底消灭热启动丢参数
    _initQuickNote();
    _initFileOpen();
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _quickNoteSub?.cancel();
    _quickNoteSub = null;
    _stopAutoSave();
    _stopAutoSync();
    for (final e in _debounceTimers.values) {
      e.cancel();
    }
    _debounceTimers.clear();
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
      // 同步全局统一存储目录配置 / SAF 导出文件夹
      storage.setCustomRoot(s.storageRootDir);
      storage.setExternalSafUri(s.externalSafUri);
      var d = await storage.loadDrafts();
      // 导入原生悬浮速记窗写入的 md（若有），并入草稿并持久化防丢
      try {
        final nativeNotes = await storage.importNativeQuickNotes();
        if (nativeNotes.isNotEmpty) {
          d = [...nativeNotes, ...d];
          await storage.saveDrafts(d);
        }
      } catch (e) {
        debugPrint('Bootstrap native note import error: $e');
      }
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
      // 启动时若有壁纸，异步计算自动字色
      _refreshWallpaperBrightness();
      _doc.setDrafts(drafts);
      _doc.setTemplates(templates);
      // 初始化站点管理器（统一管理静态仓库和动态 CMS 站点）
      _updateSiteManager();
      // 存量用户首次升级进入：弹出界面模式选择引导
      if (s.needsModeGuide) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showModeGuideDialog(s),
        );
      }
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
    try { _initCloudSync(); } catch (e) { debugPrint('Init cloud sync error: $e'); }
    _initNewServices();
  }

  /// 初始化新功能服务（站点隔离、P2P、模板同步、全文检索）
  Future<void> _initNewServices() async {
    if (kIsWeb) return;
    try {
      // 异步获取真实应用版本号
      try {
        final info = await PackageInfo.fromPlatform();
        if (info.version.isNotEmpty) _appVersion = info.version;
      } catch (_) {}
      // 草稿加密：加载元数据并注册加解密钩子
      await DraftEncryptionService.load(storage);
      StorageService.draftsEncryptor = DraftEncryptionService.encryptJson;
      StorageService.draftsDecryptor = DraftEncryptionService.decryptJson;
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
      // 写作统计
      _statsService = WritingStatsService(root);
      await _statsService!.load();
    } catch (e) {
      debugPrint('Init new services error: $e');
    }
    // 速记入口通道（桌面小部件 / 通知栏磁贴）
    _initQuickNote();
    // 自动检测更新（静默）
    _initUpdateCheck();
  }

  /// 启动时静默检查更新，有新版本时提示
  void _initUpdateCheck() {
    if (kIsWeb) return;
    try {
      _updateChecker = UpdateCheckerService(currentVersion: _appVersion);
      Future.delayed(const Duration(seconds: 3), () async {
        try {
          final result = await _updateChecker!.check();
          if (!mounted || !result.hasUpdate) return;
          final r = result.release!;
          final artifact = Platform.isAndroid
              ? (r.androidArtifact(await getDeviceAbi()) ?? r.firstArtifact)
              : (r.artifactFor(_platformKey) ?? r.firstArtifact);
          if (!mounted) return;
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('发现新版本'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '当前 ${result.currentVersion} → 最新 ${r.version}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (r.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        r.notes.trim(),
                        style: const TextStyle(fontSize: 12, height: 1.4),
                        maxLines: 8,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (artifact != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '下载: ${artifact.url}',
                        style: const TextStyle(fontSize: 11, color: Colors.blue),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (artifact.sha256 != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'SHA256: ${artifact.sha256}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Colors.grey,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('稍后'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openUpdateUrl(artifact?.url ?? r.version);
                  },
                  child: const Text('去更新'),
                ),
              ],
            ),
          );
        } catch (e) {
          debugPrint('Update check async error: $e');
        }
      });
    } catch (e) {
      debugPrint('Init update check error: $e');
    }
  }

  /// 当前运行平台标识（与 release.json platforms 键对齐）
  String get _platformKey {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    return 'other';
  }

  /// 打开更新页面
  void _openUpdateUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 初始化速记入口：拉取冷启动参数 + 监听热启动推送
  /// 幂等：initState 与 bootstrap 尾部都可能调用，只注册一次
  void _initQuickNote() {
    if (_quickNoteInited) return;
    try {
      final service = QuickNoteService();
      _quickNoteService = service;
      _quickNoteInited = true;
      // 热启动推送（应用已在运行）
      _quickNoteSub = service.requests.listen(_handleQuickNote);
      // 冷启动参数（引擎刚就绪时拉取）
      service.fetchLaunchRequest().then((req) {
        if (req != null && mounted) _handleQuickNote(req);
      });
      service.startListening();
    } catch (e) {
      debugPrint('Init quick note error: $e');
      _quickNoteInited = false;
    }
  }

  /// 初始化外部文件打开监听：拉取冷启动参数 + 监听热启动推送
  void _initFileOpen() {
    if (_fileOpenInited) return;
    _fileOpenInited = true;
    if (kIsWeb) return;
    // 热启动推送（应用已在运行）
    _fileOpenChannel.setMethodCallHandler((call) async {
      if (call.method == 'onOpenFile' && call.arguments is String) {
        final path = call.arguments as String;
        if (mounted) _openArticleFromNative(path);
      }
    });
    // 冷启动参数（引擎刚就绪时拉取）
    try {
      const nativeChannel = MethodChannel('hexo/native');
      nativeChannel
          .invokeMethod<String>('getPendingOpenFile')
          .then((path) {
            if (path != null && path.isNotEmpty && mounted) {
              _openArticleFromNative(path);
            }
          })
          .catchError((_) {
            // Web/iOS 没有 hexo/native channel 处理，静默忽略
          });
    } catch (_) {
      // iOS 没有 hexo/native channel 处理，静默忽略
    }
  }

  /// 处理速记请求：弹出悬浮速记窗，独立记录，保存后自动关闭
  void _handleQuickNote(QuickNoteRequest req) {
    if (!mounted) return;
    if (req.isOpenArticle) {
      _openArticleFromNative(req.path);
      return;
    }
    if (req.isPickArticle) {
      // 延迟一帧：极早期（initState 阶段）收到的选文请求此时 Navigator 可能尚未挂载，
      // showDialog 需要 Navigator；postFrame 后必有可用的根 Navigator。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickArticleForWidget();
      });
      return;
    }
    if (req.mode != 'new') return;
    final ui = settings.ui;
    final initialText = QuickNoteTemplate.compose(
      anchor: ui.quickNoteAnchor,
      timestampFormatKey: ui.timestampFormat,
      insertTimestamp: ui.quickNoteTimestamp,
      userText: req.text,
    );
    QuickNoteFloater.show(
      context,
      initialText: initialText,
      anchor: ui.quickNoteAnchor,
      insertTimestamp: ui.quickNoteTimestamp,
      timestampFormatKey: ui.timestampFormat,
      onSave: (text) async {
        final now = DateTime.now();
        final title = _titleFromQuickNote(text);
        final article = Article(
          id: now.millisecondsSinceEpoch.toString(),
          title: title,
          content: text,
          createdAt: now,
          updatedAt: now,
          isDraft: true,
          repoId: activeRepo?.id,
          articleType: ArticleType.post,
        );
        await _saveDraft(article);
        await _quickNoteService?.refreshWidget(widget: 'quick_note');
        if (mounted) _showToast('速记已保存到草稿箱');
        return true;
      },
    );
  }

  /// 从阅读/任务小部件「编辑」打开指定 md 文章到编辑器
  Future<void> _openArticleFromNative(String path) async {
    if (path.isEmpty) {
      _showToast('文章不存在');
      return;
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        _showToast('文章文件不存在');
        return;
      }
      final content = await file.readAsString();
      final title = _titleFromQuickNote(content);
      final now = DateTime.now();
      final article = Article(
        id: now.millisecondsSinceEpoch.toString(),
        title: title,
        content: content.trim(),
        createdAt: now,
        updatedAt: now,
        isDraft: true,
        repoId: activeRepo?.id,
        articleType: ArticleType.post,
      );
      _doc.setCurrentArticle(article);
      _doc.setArticleType(ArticleType.post);
      _doc.setEditorRepoId(activeRepo?.id);
      setState(() => _currentPage = 0);
      _updateSystemBarStyle();
      if (mounted) _showToast('已打开文章编辑');
    } catch (e) {
      debugPrint('Open article from native failed: $e');
      _showToast('打开文章失败');
    }
  }

  /// 从小部件「选文」弹出文章选择器，选中后回写路径并刷新小部件
  Future<void> _pickArticleForWidget() async {
    final paths = await _quickNoteService?.listNativeMds() ?? const <String>[];
    if (!mounted) return;
    if (paths.isEmpty) {
      _showToast('暂无文章，请先在速记窗或编辑器中创建');
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final items = <String, String>{};
        for (final p in paths) {
          final name = p
              .split(Platform.pathSeparator)
              .last
              .replaceAll('.md', '');
          items[p] = name;
        }
        return SimpleDialog(
          title: const Text('选择要显示的文章'),
          children: [
            for (final e in items.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, e.key),
                child: Text(
                  e.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      },
    );
    if (chosen == null || !mounted) return;
    await _quickNoteService?.setWidgetArticlePath(chosen, widget: 'read');
    await _quickNoteService?.setWidgetArticlePath(chosen, widget: 'task');
    await _quickNoteService?.refreshWidget(widget: 'read');
    await _quickNoteService?.refreshWidget(widget: 'task');
    await _quickNoteService?.refreshWidget(widget: 'quick_note');
    if (mounted) _showToast('已选择文章，小部件已刷新');
  }

  /// 从速记文本提取标题（首行去 markdown 前缀，截断 40 字）
  String _titleFromQuickNote(String text) {
    var first = text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    first = first
        .replaceAll(RegExp(r'^#+\s*'), '')
        .replaceAll(RegExp(r'^[-*]\s*'), '')
        .replaceAll(RegExp(r'^>\s*'), '')
        .trim();
    if (first.isEmpty) first = '速记';
    return first.length <= 40 ? first : '${first.substring(0, 40)}…';
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
      // 兜底补拉：热启动时 Java 侧 onNewIntent 的推送可能在 Flutter 监听器就绪前
      // 发出并被丢弃；回到前台时主动拉一次 pendingQuickNote（Java 侧失败会保留缓存）
      _quickNoteService?.fetchLaunchRequest().then((req) {
        if (req != null && mounted) _handleQuickNote(req);
      });
    }
  }

  AppSettings _ensureGithubTokensFromLegacy(
    AppSettings s,
    List<RepoConfig> repos,
  ) {
    return ensureGithubTokensFromLegacy(s, repos);
  }

  void _navigateTo(int page) {
    // 简易普通用户模式：目标页面入口不可见时重定向首页
    if (settings.ui.appMode == AppMode.simple) {
      final targetId = _pageEntryId(page);
      if (targetId != null &&
          !NavEntries.navVisibleFor(
            targetId,
            AppMode.simple,
            settings.ui.simpleModeExtras,
            settings.ui.navCustom,
          )) {
        page = MobilePage.home.index;
      }
    }
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

  /// 移动端页面索引 → 入口 id 映射（阅读页 reader 无对应入口，返回 null）
  static String? _pageEntryId(int page) {
    return switch (page) {
      0 => 'new_article',
      1 => 'drafts',
      2 => 'remote_posts',
      3 => 'dashboard',
      4 => 'rss',
      5 => 'history',
      6 => 'batch_upload',
      7 => 'preview',
      8 => 'settings',
      10 => 'theme_migration',
      11 => 'logs',
      12 => 'sync_status',
      13 => 'cloud_sync',
      14 => 'home',
      _ => null,
    };
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

  /// 存量用户首次升级进入：弹出界面模式选择引导
  Future<void> _showModeGuideDialog(AppSettings s) async {
    final choice = await showDialog<AppMode>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('选择使用模式'),
        content: const Text(
          '「简易普通用户模式」面向写作用户，隐藏专业开发与运维入口，保留写作、同步与 AI 配置；'
          '「标准专业模式」展示全部功能入口。可在设置中随时切换。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, AppMode.standard),
            child: const Text('标准专业模式'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, AppMode.simple),
            child: const Text('简易普通用户模式'),
          ),
        ],
      ),
    );
    if (choice != null) {
      await _updateSettings(s.copyWith(ui: s.ui.copyWith(appMode: choice)));
      _showToast(choice == AppMode.simple ? '已切换到简易普通用户模式' : '已切换到标准专业模式');
    }
  }

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

  // ============ Site Editor ============

  // ============ AI Profile Management ============

  // ============ GitHub Token Management ============

  // ============ Repo Management ============

  // ============ Commit Rollback ============

  // ============ CMS Remote Post Operations ============

  // ============ Remote Delete ============

  // ============ Import & PWA ============

  // ============ UI BUILD ============

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // ── 专注模式：全屏沉浸式写作 ──
    if (_focusModeEnabled && _currentPage == 0) {
      return _buildFocusMode();
    }

    final scaffold = PopScope(
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

    // 编辑页：全屏壁纸层垫底，壁纸/纯色背景延伸覆盖状态栏与顶栏
    if (_currentPage == 0) {
      return Stack(
        children: [
          Positioned.fill(child: _buildEditorBackground()),
          scaffold,
        ],
      );
    }
    return scaffold;
  }

  PreferredSizeWidget _buildAppBar() {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: _currentPage == 0 ? Colors.transparent : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      centerTitle: _currentPage == 0,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              Icons.menu_rounded,
              color: _currentPage == 0 ? globalTextColor : cs.primary,
              size: 22,
            ),
            onPressed: _openDrawer,
          ),
          // 仅编辑页显示软件名，避免与其他页面标题重叠
          if (_currentPage == 0)
            const Text(
              '拓墨',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: 2,
              ),
            ),
        ],
      ),
      title: _currentPage == 0
          ? null
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
              _appBarAction(
                icon: Icons.check,
                tooltip: '保存',
                color: globalTextColor,
                onTap: () {
                  _saveLocal();
                  _flushAllPendingSaves();
                },
              ),
              WordCountBadge(
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
                icon: Icons.more_vert,
                tooltip: '更多',
                color: globalTextColor,
                onTap: () => _showEditorMoreMenu(),
              ),
            ]
          : null,
    );
  }

  // ============ DRAWER ============

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

  /// 壁纸平均亮度缓存（0=纯黑 ~ 1=纯白），未计算时默认按浅色处理
  double _wallpaperBrightness = 1.0;

  /// 异步计算壁纸平均亮度，用于自动适配字色
  Future<void> _refreshWallpaperBrightness() async {
    if (_editorTheme.bgMode == 2 && _wallpaperPath.isNotEmpty) {
      try {
        final bytes = await File(_wallpaperPath).readAsBytes();
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 32,
          targetHeight: 32,
        );
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        frame.image.dispose();
        if (data != null) {
          final bytesData = data.buffer.asUint8List();
          var sum = 0.0;
          final step = bytesData.length ~/ 4;
          for (
            var i = 0;
            i + 2 < bytesData.length;
            i += 4 * (step > 400 ? step ~/ 400 : 1)
          ) {
            final r = bytesData[i] / 255;
            final g = bytesData[i + 1] / 255;
            final b = bytesData[i + 2] / 255;
            sum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
          }
          final count =
              (bytesData.length / (4 * (step > 400 ? step ~/ 400 : 1))).ceil();
          if (count > 0) sum /= count;
          _wallpaperBrightness = sum.clamp(0.0, 1.0);
        }
      } catch (_) {
        // 读取失败保持默认
      }
    }
  }

  /// 壁纸模式下自动适配的文字颜色：按壁纸平均亮度自动选择黑/白
  Color get _wallpaperTextColor =>
      _wallpaperBrightness > 0.5 ? Colors.black : Colors.white;

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
