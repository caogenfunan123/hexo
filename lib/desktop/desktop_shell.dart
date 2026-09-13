/// 桌面版主界面外壳
/// 复刻手机版全部功能，使用桌面优化布局：
/// 顶栏 + 左面板(可折叠) + 中央编辑器 + 右悬浮抽屉 + 底栏
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';

import '../controllers/controllers.dart';

import '../models/ai_profile.dart';
import '../models/ai_chat_message.dart';
import '../models/app_settings.dart';
import '../models/design_config.dart';
import '../models/article.dart';
import '../models/article_type.dart';
import '../models/blog_framework.dart';
import '../models/blog_site_config.dart';
import '../models/blog_post.dart';
import '../core/repository/blog_repository.dart';
import '../models/github_token_profile.dart';
import '../models/repo_config.dart';
import '../models/session_state.dart';
import '../models/template_item.dart';
import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/site_dispatcher_manager.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/ai/ai_session_manager.dart';
import '../core/ai/theme_migration_service.dart';
import '../core/template_engine/template_resolver.dart';
import '../screens/ai_article_chat_screen.dart';
import '../screens/all_features_screen.dart';
import '../desktop/widgets/sidebar_customize_dialog.dart';
import '../core/task/agent_task_type.dart';
import '../screens/agent_workbench_screen.dart';
import '../screens/ai_model_manager_screen.dart';
import '../screens/blog_site_editor_screen.dart';
import '../screens/drafts_screen.dart';
import '../screens/remote_screen.dart';
import '../screens/remote_posts_screen.dart';
import '../screens/sync_screen.dart';
import '../screens/sync_settings_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/rss_screen.dart';
import '../screens/history_screen.dart';
import '../screens/folder_upload_screen.dart';
import '../screens/preview_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/site_editor_screen.dart';
import '../screens/site_management_screen.dart';
import '../screens/site_operations_screen.dart';
import '../screens/template_manager_screen.dart';
import '../screens/theme_migration_screen.dart';
import '../screens/theme_store_screen.dart';
import '../screens/tool_library_screen.dart';
import '../screens/log_screen.dart';
import '../screens/local_file_zone_screen.dart';
import '../core/tools/skill_manager.dart';
import '../core/tools/remote_cms_tools.dart';
import '../core/cancel_token.dart';
import '../core/site_manager.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/image_service.dart';
import '../services/rss_service.dart';
import '../services/session_service.dart';
import '../services/storage_service.dart';
import '../services/cms_draft_service.dart';
import '../services/webdav_service.dart';
import '../services/log_service.dart';
import '../services/sync_service.dart' hide SyncStatus;
import '../services/cloud_sync_service.dart';
import '../services/html_to_markdown.dart';
import '../services/spell_check_service.dart' as spell_svc;
import '../services/recycle_bin_service.dart';
import '../services/version_snapshot_service.dart';
import '../services/frontmatter_service.dart';
import '../services/p2p_sync_service.dart';
import '../screens/recycle_bin_screen.dart';
import '../screens/image_bed_screen.dart';
import '../screens/link_checker_screen.dart';
import '../screens/batch_tools_screen.dart';
import '../screens/ai_prompt_templates_screen.dart';
import '../screens/content_stats_screen.dart';
import '../screens/backup_restore_screen.dart';
import '../screens/p2p_sync_screen.dart';
import '../widgets/ai_chat_panel.dart';
import 'widgets/wysiwyg_editor_poc.dart';
import '../widgets/markdown_preview_smooth.dart';
import 'widgets/ai_selection_edit_dialog.dart';
import 'widgets/markdown_formatter.dart';

// ── 新功能集成（桌面版） ──
import '../theme/app_color.dart';
import '../widgets/typewriter_scroll.dart';
import '../widgets/orientation_guard.dart';
import '../widgets/unified_markdown_styles.dart';
import '../services/site_isolation_service.dart';
import '../services/draft_encryption_service.dart';
import '../services/template_sync_service.dart';
import '../services/full_text_search_isolate.dart';

// webview_flutter 在桌面端不可用，Mermaid 预览改为纯文本展示
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:gbk_codec/gbk_codec.dart';

import 'widgets/title_bar.dart';
import 'widgets/left_panel.dart';
import 'widgets/editor_area.dart';
import 'widgets/right_drawer.dart';
import 'widgets/status_bar.dart';
import 'widgets/editor_themes.dart';
import 'widgets/desktop_split_editor.dart';
import '../screens/home_screen.dart';
import 'package:window_manager/window_manager.dart';
import '../models/ui_settings.dart';
import '../models/editor_theme.dart' as editor_theme_model;
import 'widgets/markdown_syntax_highlighter.dart';
import 'widgets/editor_drop_target.dart';
import 'widgets/spell_check_panel.dart';
import 'widgets/command_palette.dart';
import 'shell_action_bus.dart';
import '../core/shared_bootstrap.dart';
part 'shell_parts/shell_publish_ext.dart';
part 'shell_parts/shell_sync_ext.dart';
part 'shell_parts/shell_autosave_ext.dart';
part 'shell_parts/shell_drafts_ext.dart';
part 'shell_parts/shell_remote_ext.dart';
part 'shell_parts/shell_ai_ext.dart';
part 'shell_parts/shell_import_export_ext.dart';
part 'shell_parts/shell_dialogs_ext.dart';
part 'shell_parts/shell_style_ext.dart';
part 'shell_parts/shell_search_ext.dart';
part 'shell_parts/shell_tools_ext.dart';
part 'shell_parts/shell_text_ext.dart';
part 'shell_parts/shell_nav_ext.dart';
part 'shell_parts/shell_workbench_ui_ext.dart';
part 'shell_parts/shell_mode_ui_ext.dart';
part 'shell_parts/shell_misc_ext.dart';


/// 单个编辑器标签页的会话状态。
///
/// 所有编辑器标签共享同一个 `_doc`/`contentCtrl`，本类在切换标签时保存/恢复
/// 各自的正文、标题、元数据与未保存内容，避免标签间内容互串。
class _EditorTabSession {
  Article article;
  String content;
  String title;
  String tags;
  String categories;
  String cover;
  RepoConfig? repo;
  String lastSavedContent;
  String lastSavedTitle;
  bool showEditorMeta = false;
  // 文章类型/模板与分栏视图按标签独立保存，避免切标签后被其他标签的状态覆盖
  ArticleType articleType;
  String? templateId;
  SplitEditorMode splitMode;
  double splitRatio;

  _EditorTabSession({
    required this.article,
    required this.content,
    required this.title,
    required this.tags,
    required this.categories,
    required this.cover,
    this.repo,
    required this.lastSavedContent,
    required this.lastSavedTitle,
    this.articleType = ArticleType.post,
    this.templateId,
    this.splitMode = SplitEditorMode.sourceOnly,
    this.splitRatio = 0.5,
  });
}

// ============================================================
// 桌面版 Shell — 完整功能复刻
// ============================================================

class DesktopShell extends StatefulWidget {
  final VoidCallback? onToggleAppTheme;
  final VoidCallback? onShortcutsChanged;
  final ValueChanged<DesignConfig>? onDesignConfigChanged;
  final ValueChanged<String>? onLanguageChanged;

  const DesktopShell({
    super.key,
    this.onToggleAppTheme,
    this.onShortcutsChanged,
    this.onDesignConfigChanged,
    this.onLanguageChanged,
  });

  @override
  State<DesktopShell> createState() => DesktopShellState();
}

class DesktopShellState extends State<DesktopShell>
    with WidgetsBindingObserver {
  // ──────────────────────────────────────────────
  // 服务层
  // ──────────────────────────────────────────────
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
  late final RecycleBinService recycleBinService;
  late final VersionSnapshotService versionSnapshotService;
  late final FrontMatterService frontMatterService;
  late final P2PSyncService p2pSyncService;
  late final spell_svc.SpellCheckService spellCheckService;
  late final SiteIsolationService siteIsolation;
  late final TemplateSyncService? templateSync;
  late final FullTextSearchIsolate? searchIsolate;
  late SiteManager siteManager;

  /// 全部动态 CMS 站点适配器（用于远程文章多站点聚合查看）
  List<BlogRepository> get _allCmsAdapters {
    final result = <BlogRepository>[];
    for (final site in siteManager.dynamicSites) {
      final adapter = siteManager.getAdapter(site.id);
      if (adapter != null) result.add(adapter);
    }
    return result;
  }

  // ──────────────────────────────────────────────
  // 状态
  // ──────────────────────────────────────────────
  AppSettings settings = const AppSettings();
  List<RepoConfig> repos = [];
  List<Article> drafts = [];
  List<GitHubFileItem> remotePosts = [];
  List<RssItem> rssItems = [];
  List<GitCommitItem> commits = [];
  List<TemplateItem> templates = [];
  List<SnippetItem> snippets = [];
  bool loading = true;
  bool busy = false;
  bool _autoSyncing = false;
  String? error;

  // ──────────────────────────────────────────────
  // 布局状态 — 已迁移至 LayoutController，通过 _layout getter 访问
  // ──────────────────────────────────────────────

  // ──────────────────────────────────────────────
  // 编辑器标签页 & 状态 — 已迁移至 EditorController，通过 _editor getter 访问
  // ──────────────────────────────────────────────

  // ──────────────────────────────────────────────
  // 编辑器中保留的 Shell 级状态
  // （这些涉及服务交互，不适合放入纯状态 Controller）
  // ──────────────────────────────────────────────
  RepoConfig? _editorRepo;
  final CancelToken _publishCancelToken = CancelToken();

  // ──────────────────────────────────────────────
  // 工作区文件夹
  // ──────────────────────────────────────────────
  String? _workspaceFolder;
  final ScrollController _focusScrollCtrl = ScrollController();
  int _lastCursorLine = 0;
  /// 专注模式当前光标行（驱动行高亮条局部刷新，避免整壳重建）
  final ValueNotifier<int> _focusCursorLine = ValueNotifier(1);

  // ──────────────────────────────────────────────
  // 自动保存 Timer（涉及 Storage 操作，保留在 Shell 层）
  // ──────────────────────────────────────────────
  Timer? _autoSaveTimer;
  Timer? _autoSyncTimer;
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, _PendingSave> _pendingSaveMap = {};
  final Map<String, String> _lastSavedContentMap = {};
  final Map<String, String> _lastSavedTitleMap = {};

  String _lastSavedContent = '';

  String _lastSavedTitle = '';
  // ──────────────────────────────────────────────
  // 文章打开防抖守卫（防止同一文章被连点多次重复打开）
  // ──────────────────────────────────────────────
  String _lastOpenGuardKey = '';
  DateTime _lastOpenGuardTime = DateTime.fromMillisecondsSinceEpoch(0);

  // ──────────────────────────────────────────────
  // 标签页会话状态（key = 标签 id，见 _addEditorTab 的 tabId）
  // ──────────────────────────────────────────────
  final Map<String, _EditorTabSession> _tabSessions = {};

  // ──────────────────────────────────────────────
  // 文章属性（front matter）面板是否展开
  // ──────────────────────────────────────────────
  bool _frontMatterExpanded = false;

  // 工作区顶部元数据区（仓库/类型/Front Matter）是否展开
  bool _showEditorMeta = false;

  // 本地保存进行中标志，防止连点/多入口并发重复落盘
  bool _savingLocal = false;

  // 会话载入期间抑制标签标题回写，避免载入过程误改其它标签标题
  bool _loadingSession = false;

  // ──────────────────────────────────────────────
  // 编辑器壁纸（对应 settings.ui.editorTheme，桌面写作界面背景）
  // ──────────────────────────────────────────────
  double _wallpaperBrightness = 1.0;

  editor_theme_model.EditorTheme get _deskEditorTheme =>
      settings.ui.editorTheme;

  /// 是否启用自定义壁纸背景
  bool get _deskUseWallpaper =>
      _deskEditorTheme.bgMode == 2 &&
      _deskEditorTheme.wallpaperPath.isNotEmpty;

  /// 编辑器背景底色：纯黑 / 浅灰白（壁纸模式仅作兜底）
  Color get _deskBgColor =>
      _deskEditorTheme.bgMode == 1 ? const Color(0xFF000000) : const Color(0xFFF9FAFB);

  /// 写作界面是否启用非纯白背景（壁纸 / 纯黑）
  bool get _deskCustomBg => _deskEditorTheme.bgMode != 0;

  /// 正文文字颜色：强制黑白 > 自动适配背景亮度
  Color get _deskTextColor {
    final m = _deskEditorTheme.forceTextMode;
    if (m == 1) return Colors.black;
    if (m == 2) return Colors.white;
    if (_deskUseWallpaper) {
      return _wallpaperBrightness > 0.5 ? Colors.black : Colors.white;
    }
    return _deskBgColor.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
  }

  /// 非纯白模式下卡片背景（半透明浮层，与文字色反色保证可读）
  Color get _deskCardBg {
    final white = _deskTextColor.computeLuminance() < 0.5;
    return (white ? Colors.white : const Color(0xFF111827))
        .withOpacity(0.82);
  }

  /// 异步计算壁纸平均亮度（0=纯黑 ~ 1=纯白），用于自动适配字色

  // ──────────────────────────────────────────────
  // 会话
  // ──────────────────────────────────────────────
  bool _sessionRestored = false;

  // ──────────────────────────────────────────────
  // 最近打开文件
  // ──────────────────────────────────────────────
  final List<RecentFile> _recentFiles = [];
  static const int _maxRecentFiles = 10;

  // ── 新功能：打字机滚动 ──
  late final TypewriterScrollController _typewriterCtrl;

  // ── 新功能：分栏编辑器 ──
  // 阶段2.5：主编辑区默认所见即所得（源码/分栏/预览仍可随时切换）
  SplitEditorMode _splitEditorMode = SplitEditorMode.wysiwyg;
  double _splitEditorRatio = 0.5;

  // ── 新功能：命令面板 ──
  bool _showCommandPalette = false;

  // ── 极简写作模式（改造 focus）：更多菜单展开的格式化工具栏 ──
  bool _focusShowToolbar = false;

  // 极简写作模式：内嵌预览面板开关（与右抽屉互斥）
  bool _focusPreviewOpen = false;

  // ── 新功能：源码语法高亮 ──
  BridgedSyntaxController? _sourceSyntaxCtrl;

  // ── 新功能：横竖屏状态保持 ──
  late final EditorStateManager _orientationManager;

  // ──────────────────────────────────────────────
  // 同步日志（已迁移到 SyncController，此处保留兼容）
  // ──────────────────────────────────────────────

  // ── 控制器访问器（从 Provider 获取） ──
  LayoutController get _layout => context.read<LayoutController>();
  EditorController get _editor => context.read<EditorController>();
  DocumentController get _doc => context.read<DocumentController>();
  SyncController get _sync => context.read<SyncController>();
  SiteController get _site => context.read<SiteController>();
  UiStateController get _ui => context.read<UiStateController>();

  // ── 辅助属性 ──

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

  void _updateSiteManager() {
    final activeId = settings.effectiveActiveSiteId;
    siteManager = SiteManager(
      staticRepos: repos,
      dynamicSites: settings.blogSiteConfigs,
      appSettings: settings,
      activeSiteId: activeId.isNotEmpty ? activeId : (activeRepo?.id ?? ''),
    );
    RemoteCmsTools.siteManager = siteManager;
  }

  // ============================================================
  // 生命周期
  // ============================================================
  /// 供 part 扩展调用的 setState 包装（extension 无法直接访问 protected 成员）
  void _applyState(VoidCallback fn) => setState(fn);


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshWallpaperBrightness();
    syncService = SyncService(logService);
    cloudSyncService = CloudSyncService(logService);
    recycleBinService = RecycleBinService();
    versionSnapshotService = VersionSnapshotService(logService);
    frontMatterService = FrontMatterService(logService);
    p2pSyncService = P2PSyncService(
      deviceName: 'Desktop-${Platform.localHostname}',
    );
    spellCheckService = spell_svc.SpellCheckService();
    spellCheckService.init();
    _typewriterCtrl = TypewriterScrollController(
      scrollController: _focusScrollCtrl,
      lineHeight: 22.0,
      visibleLines: 30,
    );
    _orientationManager = EditorStateManager(
      scrollController: _focusScrollCtrl,
      textController: _doc.contentCtrl,
    );
    // 纯光标移动（方向键/点击）不触发 onChanged，此处监听 selection 刷新专注模式行高亮
    _doc.contentCtrl.addListener(_onCursorSelectionChanged);
    // 标题变化实时回写当前标签标题（标签栏与编辑内容同步）
    _doc.titleCtrl.addListener(_onTitleChanged);
    aiService.modelManager = aiModelManager;
    _bus = ShellActionBus(
    // 导航
    onNewArticle: _newArticle,
    onOpenHome: _openHome,
    onOpenDrafts: _openDrafts,
    onOpenRemote: _openRemote,
    onOpenBatchUpload: _openBatchUpload,
    onOpenPreview: _openPreview,
    onOpenSettings: _openSettings,
    onOpenSyncSettings: _openSyncSettings,
    onOpenLogs: _openLogs,
    onOpenDashboard: _openDashboard,
    onOpenHistory: _openHistory,
    onOpenRss: _openRss,
    onOpenSync: _openSyncStatus,
    onOpenThemeMigration: _openThemeMigration,
    onShowTemplateManager: _showTemplateManager,
    onShowSnippetManager: _showSnippetManager,
    onShowConfigEditor: _showConfigEditor,
    onShowHelp: _showHelpDialog,
    onOpenRecycleBin: _openRecycleBin,
    onOpenP2PSync: _openP2PSync,
    onOpenImageBedManager: _openImageBedManager,
    onOpenProxySettings: _openProxySettings,
    onOpenCacheCleanup: _openCacheCleanup,
    onExportLogs: _exportLogs,
    onOpenLinkChecker: _openLinkChecker,
    onOpenBatchTools: _openBatchTools,
    onShowContentStats: _openContentStats,
    onShowBackupRestore: _openBackupRestore,
    onOpenAiPromptTemplates: _openAiPromptTemplates,
    onShowAgentWorkbench: _showAgentWorkbench,
    onShowThemeStore: _showThemeStore,
    onShowAiModelManager: _showAiModelManager,
    onShowAiTemplateChat: _showAiTemplateChat,
    onShowToolLibrary: _showToolLibrary,
    onShowBlogSiteManager: _showBlogSiteManager,
    onShowSiteEditor: _showSiteEditor,
    onShowSiteOperations: _showSiteOperations,
    onSiteChange: _switchSite,
    // 布局
    onToggleLeftPanel: _toggleLeftPanel,
    onToggleRightDrawer: _toggleRightDrawer,
    onThemeToggle: _toggleTheme,
    // 同步 & 发布
    onSync: _handleSync,
    onPublish: _handlePublish,
    // 文件操作
    onOpenFile: _openFileDialog,
    onOpenFileZone: _openLocalFileZone,
    // 侧边栏自定义 & 全部功能
    onOpenAllFeatures: _openAllFeatures,
    onOpenCustomizeSidebar: _openSidebarCustomize,
    // 文章管理
    onOpenArticle: (a) => _openExistingArticle(a),
    onRenameArticle: _renameArticle,
    onMoveArticleVolume: _moveArticleVolume,
    onExportArticle: _exportArticle,
    onDeleteArticle: _deleteDraft,
    );
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoSave();
    _stopAutoSync();
    _doc.contentCtrl.removeListener(_onCursorSelectionChanged);
    _doc.titleCtrl.removeListener(_onTitleChanged);
    _typewriterCtrl.dispose();
    _focusScrollCtrl.dispose();
    _focusCursorLine.dispose();
    _orientationManager.dispose();
    searchIsolate?.cancel();
    p2pSyncService.dispose();
    templateSync?.dispose();
    siteIsolation.dispose();
    siteManager.disposeAll();
    if (_siteDispatcherManagerUsed) {
      siteDispatcherManager.disposeAll();
    }
    cloudSyncService.dispose();
    cmsDraftService.close();
    _scheduledPublishTimer?.cancel();
    _scheduledPublishTimer = null;
    _publishCancelToken.cancel();
    _sourceSyntaxCtrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // 三重落盘：APP 转入后台时强制冲刷所有等待中的保存任务（不依赖云同步开关）
      _flushAllPendingSaves();
      if (settings.draftSyncEnabled) {
        _autoSyncToCloud();
      }
    } else if (state == AppLifecycleState.resumed) {
      _autoPullFromCloud();
    }
  }

  // ============================================================
  // 启动
  // ============================================================

  Future<void> _bootstrap() async {
    _ui.setLoading(true);
    try {
      final (s, r, d, t, sn) = await _loadAppData();
      storage.setCustomRoot(s.storageRootDir);
      storage.setExternalSafUri(s.externalSafUri);
      await _bootstrapCore(s, r, d, t, sn);
    } catch (e) {
      debugPrint('Bootstrap error: $e');
      if (mounted) _ui.setLoading(false);
    }
    try {
      await skillManager.init(await storage.root);
    } catch (e) {
      debugPrint('SkillManager init error: $e');
    }
    _loadRecentFiles();
    _loadEditorSettings();
    _initCloudSync();
    _initRecycleBin();
    _initVersionSnapshots();
    _initFrontMatter();
    _initNewServices();
  }

  /// 加载应用持久化数据
  Future<
    (
      AppSettings,
      List<RepoConfig>,
      List<Article>,
      List<TemplateItem>,
      List<SnippetItem>,
    )
  >
  _loadAppData() async {
    var s = await storage.loadSettings();
    var r = await storage.loadRepos();
    final d = await storage.loadDrafts();
    final t = await storage.loadAllTemplates();
    final sn = await storage.loadSnippets();
    return (s, r, d, t, sn);
  }

  /// 核心引导逻辑（Token 迁移、默认仓库、站点同步）
  Future<void> _bootstrapCore(
    AppSettings s,
    List<RepoConfig> r,
    List<Article> d,
    List<TemplateItem> t,
    List<SnippetItem> sn,
  ) async {
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
        github: s.github.copyWith(
          imageBedOwner: 'caogenfunan123',
          imageBedRepo: 'xiamend',
        ),
      );
      await storage.saveSettings(s);
    } else {
      r = backfillRepoTokens(r, s.effectiveGithubToken);
      if (r.any((repo) => repo.token != s.effectiveGithubToken)) {
        // no-op: backfillRepoTokens already returns the updated list
      }
      await storage.saveRepos(r);
    }
    _editorRepo = activeRepo ?? (r.isNotEmpty ? r.first : null);
    String? autoTemplateId;
    if (_editorRepo != null) {
      autoTemplateId = TemplateResolver.resolvePostTemplateId(_editorRepo!, t);
      _doc.setSelectedTemplateId(autoTemplateId);
    }

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
    });
    // 初始语言同步给 DesktopApp
    widget.onLanguageChanged?.call(s.language);
    _ui.setLoading(false);
    _updateSiteManager();
    if (s.needsModeGuide) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showModeGuideDialog(s),
      );
    }
    if (s.restoreSession) {
      await _restoreSession();
    }
  }

  /// 存量用户首次升级进入：弹出界面模式选择引导

  /// 初始化新功能服务（站点隔离、P2P、模板同步、全文检索）
  Future<void> _initNewServices() async {
    try {
      final root = await storage.root;
      // 草稿加密：加载元数据并注册加解密钩子
      await DraftEncryptionService.load(storage);
      StorageService.draftsEncryptor = DraftEncryptionService.encryptJson;
      StorageService.draftsDecryptor = DraftEncryptionService.decryptJson;
      siteIsolation = SiteIsolationService(root);
      await siteIsolation.init();
      // 日志持久化
      await logService.init(root);
      templateSync = TemplateSyncService(
        templateDir: Directory('${root.path}/templates'),
        deviceId: 'desktop-${Platform.localHostname}',
      );
      searchIsolate = FullTextSearchIsolate(logService);
    } catch (e) {
      debugPrint('Init new services (desktop) error: $e');
    }
  }

  Future<void> _initCloudSync() async {
    final deviceKey = await storage.loadDeviceKey();
    cloudSyncService.initDeviceKey(deviceKey);
    final githubBackend = GitHubSyncBackend(github);
    cloudSyncService.registerBackend(githubBackend);
    githubBackend.configureFromSyncSettings(settings.sync);
    final webdavBackend = WebDavSyncBackend();
    webdavBackend.configureFromSettings(settings);
    cloudSyncService.registerBackend(webdavBackend);
    _startAutoSync();
    if (cloudSyncService.hasConfiguredBackend && settings.draftSyncEnabled) {
      _autoPullFromCloud();
    }
  }

  Future<void> _initRecycleBin() async {
    try {
      await recycleBinService.init(await storage.root);
      // 自动清理超过30天的回收站文件
      await recycleBinService.autoClean(30);
    } catch (e) {
      debugPrint('RecycleBin init error: $e');
    }
  }

  Future<void> _initVersionSnapshots() async {
    try {
      await versionSnapshotService.init(await storage.root);
      // 自动清理超过7天的快照
      await versionSnapshotService.autoClean(days: 7);
    } catch (e) {
      debugPrint('VersionSnapshot init error: $e');
    }
  }

  Future<void> _initFrontMatter() async {
    try {
      frontMatterService.refreshFromArticles(drafts);
    } catch (e) {
      debugPrint('FrontMatter init error: $e');
    }
  }

  AppSettings _ensureGithubTokensFromLegacy(
    AppSettings s,
    List<RepoConfig> repos,
  ) {
    return ensureGithubTokensFromLegacy(s, repos);
  }

  // ============================================================
  // 自动保存
  // ============================================================

  /// 冲刷所有等待中的保存任务（三重落盘：文本变更 / 页面切换 / APP 转入后台）。
  /// 返回所有发起的落盘 Future，便于关闭窗口时真正 await 完成后再销毁。

  /// 标题变化时同步标签栏标题（未命名兜底）

  /// 纯光标移动（方向键/点击/拖动选择）时刷新专注模式行高亮与打字机居中

  /// 专注模式下将光标所在行滚动到屏幕中央
  /// 正文上方固定头部，与 _buildFocusEditor 布局一致：
  /// 滚动纵向 padding 48 + 标题(28×1.3 文本 + 主题 contentPadding 2×14) + 间距16 + 分隔线1 + 间距16
  static const double _focusHeaderOffset =
      48 + (28 * 1.3 + 28) + 16 + 1 + 16;

  // ============================================================
  // 云同步
  // ============================================================

  // ============================================================
  // 会话管理
  // ============================================================

  // ============================================================
  // 文章操作
  // ============================================================

  RepoConfig? get _resolvedRepo {
    final r = _editorRepo;
    if (r == null) return null;
    if (r.token.isNotEmpty) return r;
    final t = settings.effectiveGithubToken;
    if (t.isEmpty) return r;
    return r.copyWith(token: t);
  }

  // ============================================================
  // 保存草稿
  // ============================================================

  // ============================================================
  // 发布
  // ============================================================

  /// 一键发布当前文章到所有已保存的动态 CMS 站点

  // ============================================================
  // 远程操作
  // ============================================================

  // ============================================================
  // 设置更新
  // ============================================================

  Future<void> _persistSettings() => storage.saveSettings(settings);
  Future<void> _persistRepos() => storage.saveRepos(repos);

  // ──────────────────────────────────────────────
  // 编辑器自定义设置持久化
  // ──────────────────────────────────────────────

  /// 加载编辑器自定义设置

  /// 保存编辑器自定义设置

  // ============================================================
  // 草稿/文章管理
  // ============================================================

  /// 将指定标签的会话内容保存回会话存储（保留未保存改动）

  /// 把指定标签的会话内容载入共享的 `_doc` 与 shell 状态

  /// 切换编辑器标签：先保存当前标签状态，再载入目标标签状态

  // ============================================================
  // 文章管理（首页 / 侧边栏长按操作）
  // ============================================================

  /// 重命名文章：更新标题并保存

  /// 移动文章到卷宗：弹出卷宗选择器（含「未分类」与新建卷宗）

  /// 导出文章为 Markdown 文件

  // ============================================================
  // 标签页管理
  // ============================================================

  // ============================================================
  // 嵌入式编辑器
  // ============================================================

  // ── 编辑器辅助组件 ──

  /// 元数据面板最大高度：按窗口高度计算并预留顶栏/工具栏/底栏空间，
  /// 避免短窗口下固定内容超出可用高度导致 RenderFlex 溢出。

  /// 折叠态摘要：title · tags · categories · cover · template

  /// 文章属性面板：折叠态显示 YAML 摘要，展开态编辑全部元数据。

  /// 完整格式化工具栏 chip 集合（工作台模式常驻、极简模式展开共用）

  /// 低频专业工具（批量图床 + AI 动作）收纳菜单；
  /// 命令面板（Ctrl+K）仍可直达全部动作。

  // ============================================================
  // 编辑器操作
  // ============================================================

  /// 处理拖拽放入的图片文件

  // ============================================================
  // 查找/替换对话框
  // ============================================================

  // ============================================================
  // [toc] 自动生成
  // ============================================================

  // ============================================================
  // 图片路径管理
  // ============================================================

  // ============================================================
  // 可视化表格编辑
  // ============================================================

  // ============================================================
  // 全文格式化
  // ============================================================

  // ============================================================
  // 发布路径修复
  // ============================================================

  // ============================================================
  // 批量操作
  // ============================================================

  // ============================================================
  // 导航方法 - 复刻手机版全部功能入口
  // ============================================================

  /// 远程文章批量删除（静态站点，GitHub 文件级删除）

  /// 远程文章回滚到历史提交（静态站点，GitHub 文件级恢复）

  /// PWA / 主屏幕快捷方式指南（与移动端一致，桌面仅作指引与复制站点地址）

  // ── 同步冲突解决 ──

  /// 显示同步冲突解决对话框
  /// [conflicts] 冲突列表，每个条目包含本地和远程内容

  /// 冲突解决后应用结果

  /// 检查并处理同步冲突

  /// 生成简单 diff 文本（逐行对比两个字符串）

  // ── 版本历史对话框 ──

  final _aiChatKey = GlobalKey<AiChatPanelState>();

  // ── AI 选区处理 ──

  /// 将编辑器选中文本发送到 AI 选区编辑对话框（含 Diff 对比）

  /// 将编辑器全文发送到 AI 聊天

  /// 等待右侧 AI 面板挂载后发送消息，避免面板动画期间消息丢失

  // ── AI 输出对比 ──

  /// 显示 AI 修改内容 diff 预览，选择性接受改动

  // ── 发布增强 ──

  /// 发布变更日志：对比本地与线上版本，展示改动内容

  /// 定时发布：设置延迟时间推送到 CMS
  Timer? _scheduledPublishTimer;
  DateTime? _scheduledPublishTime;

  /// 执行发布（不显示确认对话框）

  /// 拼写检查面板

  // ============================================================
  // AI 功能入口
  // ============================================================

  /// AI 模板与博客框架入口：打开工作台的模板任务，并刷新模板列表

  /// 一键建站入口（AI 对话主模式）。

  // ============================================================
  // 工具方法
  // ============================================================

  // ============================================================
  // 全局操作入口（由 desktop_main 快捷键/托盘/拖拽调用）
  // ============================================================

  /// 窗口关闭/托盘退出前强制冲刷所有待保存内容（由 desktop_main 调用）。
  /// 返回的 Future 在全部落盘完成时 resolve，供关闭前 await，避免销毁竞态。
  Future<void> flushAllPendingSaves() async {
    final futures = _flushAllPendingSaves();
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
    await Future.wait(futures);
  }

  /// GlobalKey 调用的统一入口
  void handleGlobalAction(String action) {    switch (action) {
      case 'save':
        _saveLocal();
        break;
      case 'publish':
        _handlePublish();
        break;
      case 'new':
        _newArticle();
        break;
      case 'openFile':
        _openFileDialog();
        break;
      case 'bold':
        _wrapSelection('**', '**');
        break;
      case 'italic':
        _wrapSelection('*', '*');
        break;
      case 'strikethrough':
        _wrapSelection('~~', '~~');
        break;
      case 'link':
        _insertLink();
        break;
      case 'h1':
        _prefixLine('# ');
        break;
      case 'h2':
        _prefixLine('## ');
        break;
      case 'h3':
        _prefixLine('### ');
        break;
      case 'focus':
        _switchWorkMode(WorkMode.focus);
        break;
      case 'toggleLeft':
        _toggleLeftPanel();
        break;
      case 'preview':
        _openRightDrawer(RightDrawerTab.outline);
        break;
      case 'pasteImage':
        _pasteImageFromClipboard();
        break;
      case 'commandPalette':
        _openCommandPalette();
        break;
      case 'saveAs':
        _saveAsToLocal();
        break;
      case 'findReplace':
        _showFindReplace();
        break;
      case 'insertToc':
        _insertToc();
        break;
      case 'insertTable':
        _insertTable();
        break;
      case 'addTableRow':
        _addTableRow();
        break;
      case 'addTableCol':
        _addTableCol();
        break;
      case 'toggleImagePath':
        _toggleImagePathMode();
        break;
      case 'formatDocument':
        _formatDocument();
        break;
      case 'repairPaths':
        _repairPublishPaths();
        break;
      case 'batchOps':
        _showBatchOperations();
        break;
      // 导出功能
      case 'exportHtml':
        _exportHtml();
        break;
      case 'exportPdf':
        _exportPdf();
        break;
      case 'exportDocx':
        _exportDocx();
        break;
      case 'exportEpub':
        _exportEpub();
        break;
      // 文件管理
      case 'openFolder':
        _openFolderWorkspace();
        break;
      case 'renameFile':
        _renameCurrentFile();
        break;
      case 'moveFile':
        _moveCurrentFile();
        break;
      // 编辑器自定义功能
      case 'fontSettings':
        _showFontSettings();
        break;
      case 'themePicker':
        _showThemePicker();
        break;
      case 'customCss':
        _showCustomCssEditor();
        break;
      case 'shortcutEditor':
        _showShortcutEditor();
        break;
      case 'help':
        _showHelpDialog();
        break;
      case 'recycleBin':
        _openRecycleBin();
        break;
      case 'imageBed':
        _openImageBedManager();
        break;
      case 'versionHistory':
        _openVersionHistory();
        break;
      case 'proxySettings':
        _openProxySettings();
        break;
      case 'globalSearch':
        _openGlobalSearch();
        break;
      case 'cacheCleanup':
        _openCacheCleanup();
        break;
      case 'exportLogs':
        _exportLogs();
        break;
      case 'fixEncoding':
        _fixEncoding();
        break;
      case 'offlineMode':
        _toggleOfflineMode();
        break;
      case 'nightEye':
        _toggleNightEyeProtection();
        break;
      case 'linkChecker':
        _openLinkChecker();
        break;
      case 'batchTools':
        _openBatchTools();
        break;
      case 'aiTemplates':
        _openAiPromptTemplates();
        break;
      case 'importHtml':
        _importHtmlFile();
        break;
      case 'importDocx':
        _importDocxFile();
        break;
      case 'conflictResolve':
        _checkAndResolveConflicts();
        break;
      case 'aiSelection':
        _sendSelectionToAi();
        break;
      case 'aiFullText':
        _sendFullToAi();
        break;
      case 'schedulePublish':
        _schedulePublish();
        break;
      case 'publishChangeLog':
        _showPublishChangeLog('');
        break;
      case 'aiDiffPreview':
        _showAiDiffPreview();
        break;
      case 'p2pSync':
        _openP2PSync();
        break;
      // 快捷键新增
      case 'newArticle':
        _newArticle();
        break;
      case 'sync':
        _handleSync();
        break;
      case 'saveLocal':
        _saveLocal();
        break;
      case 'toggleLeftPanel':
        _toggleLeftPanel();
        break;
      case 'toggleRightDrawer':
        _toggleRightDrawer();
        break;
      case 'focusMode':
        _switchWorkMode(WorkMode.focus);
        break;
      case 'sourceMode':
        _switchWorkMode(WorkMode.source);
        break;
      case 'workspaceMode':
        _switchWorkMode(WorkMode.workspace);
        break;
      case 'insertImage':
        _insertImage();
        break;
      case 'find':
      case 'replace':
        _showFindReplace();
        break;
      case 'escape':
        _handleEscape();
        break;
    }
  }

  /// 打开外部 .md 文件加载到编辑器
  void openExternalFile(String fileName, String content, String filePath) {
    _addRecentFile(filePath, fileName);
    final article = Article(
      // 稳定 id：同一路径重复打开复用同一标签，避免生成多个独立标签
      id: 'external_${filePath.hashCode}',
      title: fileName,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDraft: true,
      remotePath: filePath,
    );
    _openExistingArticle(article);
    _showToast('已打开: $fileName');
  }

  /// 记录最近打开的文件

  /// 文件打开对话框

  /// 打开本地文件区（文件浏览器）

  /// 打开"全部功能"枢纽页

  /// 打开"自定义侧边栏"对话框

  // ============================================================
  // 剪贴板图片粘贴（桌面版：粘贴截图 → 上传图床 → 插入 Markdown）
  // ============================================================

  // ============================================================
  // IDE 风格 Markdown 快捷键助手
  // ============================================================

  /// 用前后缀包裹选中文本（对应手机版 _wrap 方法）

  /// 插入 Markdown 标题（对应手机版 _insertHeading）

  /// 插入列表标记（对应手机版 _insertList）

  /// 用前后缀包裹选中文本（保留兼容性）

  /// 在当前行首添加前缀

  /// 插入 Markdown 链接

  // ============================================================
  // 编辑器自定义功能
  // ============================================================

  /// 根据字体名称获取对应的 FontFamily 字符串
  String? _resolveFontFamily(String fontFamily) {
    switch (fontFamily) {
      case 'System':
        return null;
      case 'monospace':
        return 'monospace';
      case 'serif':
        return 'serif';
      case 'sans-serif':
        return 'sans-serif';
      default:
        return null;
    }
  }

  // ──────────────────────────────────────────────
  // 1. 字体设置对话框
  // ──────────────────────────────────────────────

  // ──────────────────────────────────────────────
  // 3. 编辑器主题选择器
  // ──────────────────────────────────────────────

  // ──────────────────────────────────────────────
  // 4. 自定义 CSS 编辑器
  // ──────────────────────────────────────────────

  // ──────────────────────────────────────────────
  // 5. 自定义快捷键编辑器
  // ──────────────────────────────────────────────

  /// 默认快捷键定义
  static const Map<String, String> _defaultShortcuts = {
    'save': 'Ctrl+S',
    'publish': 'Ctrl+P',
    'new': 'Ctrl+N',
    'openFile': 'Ctrl+O',
    'bold': 'Ctrl+B',
    'italic': 'Ctrl+I',
    'strikethrough': 'Ctrl+Shift+X',
    'link': 'Ctrl+K',
    'h1': 'Ctrl+1',
    'h2': 'Ctrl+2',
    'h3': 'Ctrl+3',
    'focus': 'Ctrl+Shift+F',
    'toggleLeft': 'Ctrl+L',
    'preview': 'Ctrl+E',
    'pasteImage': 'Ctrl+Shift+V',
    'commandPalette': 'Ctrl+Shift+P',
    'saveAs': 'Ctrl+Shift+S',
    'fontSettings': '',
    'themePicker': '',
    'customCss': '',
    'shortcutEditor': '',
  };

  static const Map<String, String> _actionLabels = {
    'save': '保存草稿',
    'publish': '一键发布',
    'new': '新建文章',
    'openFile': '打开文件',
    'bold': '加粗',
    'italic': '斜体',
    'strikethrough': '删除线',
    'link': '插入链接',
    'h1': '一级标题',
    'h2': '二级标题',
    'h3': '三级标题',
    'focus': '专注模式',
    'toggleLeft': '切换左侧面板',
    'preview': '打开大纲',
    'pasteImage': '粘贴图片',
    'commandPalette': '命令面板',
    'saveAs': '另存为',
    'fontSettings': '字体设置',
    'themePicker': '编辑器主题',
    'customCss': '自定义 CSS',
    'shortcutEditor': '快捷键设置',
  };

  // ============================================================
  // 帮助 / 快捷键速查 (F1)
  // ============================================================

  // ============================================================
  // 命令面板 (Ctrl+Shift+P)
  // ============================================================

  // ============================================================
  // 另存为到本地目录
  // ============================================================

  // ============================================================
  // 导出功能
  // ============================================================

  /// 安全的文件名（去除非法字符）

  /// 将 Markdown 内容转换为 HTML 字符串

  /// 清洗 HTML 防止存储型 XSS：移除脚本/样式块、事件属性与危险 URL

  /// 对 HTML 特殊字符进行转义

  /// 导出 HTML 文件

  /// 导出 PDF 文件

  /// 导出 DOCX 文件（基于 Office Open XML 格式）

  /// 构建 DOCX ZIP 文件

  /// 导出 EPUB 电子书

  /// 构建 EPUB ZIP 文件

  /// 转义 XML 特殊字符

  /// 转义 XML body 中的特殊字符（在纯文本片段中）

  /// 创建一个 ZIP 文件（使用 archive 库）
  /// 用于生成 DOCX / EPUB 等基于 ZIP 的格式

  // ============================================================
  // 文件管理
  // ============================================================

  /// 打开文件夹工作区
  Future<void> _openFolderWorkspace() async {
    try {
      final folderPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择工作区文件夹',
      );
      if (folderPath == null) return;
      _workspaceFolder = folderPath;

      // 递归扫描文件夹中的 .md 文件
      final mdFiles = <FileSystemEntity>[];
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.md')) {
            mdFiles.add(entity);
          }
        }
      }

      mdFiles.sort((a, b) => a.path.compareTo(b.path));

      if (!mounted) return;

      // 显示文件列表对话框
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.folder_open, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '工作区: ${folderPath.split('/').last}',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: mdFiles.isEmpty
                ? const Center(
                    child: Text(
                      '该文件夹中没有找到 .md 文件',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: mdFiles.length,
                    itemBuilder: (_, i) {
                      final file = mdFiles[i] as File;
                      final relativePath = file.path.substring(
                        folderPath.length + 1,
                      );
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.article_outlined, size: 18),
                        title: Text(
                          relativePath.replaceAll('.md', ''),
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          relativePath,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            final content = await file.readAsString();
                            final name = relativePath.replaceAll('.md', '');
                            openExternalFile(name, content, file.path);
                          } catch (e) {
                            if (mounted) _showToast('打开文件失败: $e');
                          }
                        },
                      );
                    },
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

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _showToast('打开文件夹失败: $e');
    }
  }

  /// 重命名当前文件
  Future<void> _renameCurrentFile() async {
    try {
      final currentPath = _doc.currentArticle.remotePath;
      if (currentPath == null || currentPath.isEmpty) {
        if (mounted) _showToast('当前文章未关联文件，无法重命名');
        return;
      }

      final currentFile = File(currentPath);
      if (!await currentFile.exists()) {
        if (mounted) _showToast('文件不存在，无法重命名');
        return;
      }

      final oldName = currentPath
          .split('/')
          .last
          .replaceAll(RegExp(r'\.md$'), '');
      final nameCtrl = TextEditingController(text: oldName);

      if (!mounted) return;
      String? newName;
      try {
        newName = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('重命名文件', style: TextStyle(fontSize: 16)),
            content: TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '新文件名',
                hintText: '输入新文件名（不含扩展名）',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
                child: const Text('重命名'),
              ),
            ],
          ),
        );
      } finally {
        nameCtrl.dispose();
      }

      if (newName == null || newName.isEmpty || newName == oldName) return;

      // 清理文件名
      final safeName = newName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final dirPath = currentPath.contains('/')
        ? currentPath.substring(0, currentPath.lastIndexOf('/'))
        : '';
      final newPath = '$dirPath/$safeName.md';

      // 检查目标文件是否已存在
      if (File(newPath).existsSync()) {
        if (mounted) _showToast('目标文件已存在，请使用其他名称');
        return;
      }

      await currentFile.rename(newPath);

      // 更新当前文章路径
      _doc.setCurrentArticle(_doc.currentArticle.copyWith(remotePath: newPath));
      if (mounted) {
        _showToast('文件已重命名为: $safeName.md');
      }
    } catch (e) {
      if (mounted) _showToast('重命名失败: $e');
    }
  }

  /// 移动当前文件到指定目录
  Future<void> _moveCurrentFile() async {
    try {
      final currentPath = _doc.currentArticle.remotePath;
      if (currentPath == null || currentPath.isEmpty) {
        if (mounted) _showToast('当前文章未关联文件，无法移动');
        return;
      }

      final currentFile = File(currentPath);
      if (!await currentFile.exists()) {
        if (mounted) _showToast('文件不存在，无法移动');
        return;
      }

      if (!mounted) return;
      final destDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择目标文件夹',
      );
      if (destDir == null) return;

      final fileName = currentPath.split('/').last;
      final newPath = '$destDir/$fileName';

      // 检查目标文件是否已存在
      if (File(newPath).existsSync()) {
        if (mounted) _showToast('目标位置已存在同名文件');
        return;
      }

      // 复制文件到目标位置，然后删除原文件
      await currentFile.copy(newPath);
      await currentFile.delete();

      // 更新当前文章路径
      _doc.setCurrentArticle(_doc.currentArticle.copyWith(remotePath: newPath));
      if (mounted) {
        _showToast('文件已移动到: $newPath');
      }
    } catch (e) {
      if (mounted) _showToast('移动文件失败: $e');
    }
  }

  // ============================================================
  // 站点切换
  // ============================================================

  // ============================================================
  // 布局交互
  // ============================================================

  // ============================================================
  // 构建
  // ============================================================

  late final ShellActionBus _bus;

  // 左面板折叠状态恢复标记（首次依赖就绪时执行一次）
  bool _leftPanelRestored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_leftPanelRestored) {
      _leftPanelRestored = true;
      if (settings.ui.leftPanelExpanded && !_layout.leftPanelExpanded) {
        _layout.expandLeftPanel();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UiStateController>();
    if (ui.loading) return const Center(child: CircularProgressIndicator());

    final layout = context.watch<LayoutController>();
    context.read<EditorController>();
    context.read<DocumentController>();

    final stackChildren = <Widget>[
      ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        // Material(transparency)：桌面壳没有 Scaffold，必须显式提供 Material
        // 祖先，否则工作台编辑器 TextField / 各处 InkWell 会抛
        // "No Material widget found" 渲染成红色错误框（存量 bug 根治）。
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              _buildTopBar(layout),
              _buildMainArea(layout),
              _buildBottomBar(layout),
            ],
          ),
        ),
      ),
    ];

    if (settings.nightEyeProtection) {
      stackChildren.add(
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: Color.fromRGBO(
                255,
                200,
                100,
                settings.nightEyeIntensity * 0.3,
              ),
            ),
          ),
        ),
      );
    }
    // 命令面板覆盖层
    if (_showCommandPalette) {
      stackChildren.add(
        Positioned.fill(
          child: CommandPalette(
            commands: _buildCommandItems(),
            onClose: _closeCommandPalette,
          ),
        ),
      );
    }
    return Focus(
      onKeyEvent: _handleGlobalKeyEvent,
      child: Stack(children: stackChildren),
    );
  }

  /// 全局快捷键：Ctrl+Shift+E 在极简写作模式与完整编辑模式间切换
  KeyEventResult _handleGlobalKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyE &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed) {
      _switchWorkMode(
        _layout.workMode == WorkMode.focus
            ? WorkMode.workspace
            : WorkMode.focus,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 顶部标题栏

  /// 主体三栏区域

  /// 工作区三栏布局

  /// 右侧抽屉

  /// 底部状态栏

  // ============================================================
  // 专注模式（写字模式）
  // ============================================================

  /// 极简写作模式：切换内嵌预览面板（与右抽屉互斥）

  /// 极简写作模式：正文选区悬浮工具条（Obsidian/Notion 风格，选中即弹出）

  /// 源码模式编辑器：全屏等宽字体 Markdown 源码视图

}

// ============================================================
// 辅助数据类
// ============================================================

/// 防抖保存的待保存内容（捕获切换文章时的旧改动，避免丢失）
class _PendingSave {
  final String articleId;
  final String content;
  final String title;
  final String tags;
  final String categories;
  final String cover;

  const _PendingSave({
    required this.articleId,
    required this.content,
    required this.title,
    this.tags = '',
    this.categories = '',
    this.cover = '',
  });
}

/// 最近打开文件记录
class RecentFile {
  final String path;
  final String name;
  final DateTime openedAt;

  const RecentFile({
    required this.path,
    required this.name,
    required this.openedAt,
  });
}

// 帮助对话框辅助 Widget
// ============================================================

/// 帮助页 - 工作模式卡片
class _HelpModeCard extends StatelessWidget {
  final String title;
  final String desc;
  final String tip;
  const _HelpModeCard(this.title, this.desc, this.tip);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 2),
            Text(
              tip,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 帮助页 - 布局说明项
class _HelpLayoutItem extends StatelessWidget {
  final String label;
  final String desc;
  const _HelpLayoutItem(this.label, this.desc);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 帮助页 - 使用技巧卡片
class _HelpTipCard extends StatelessWidget {
  final String title;
  final String content;
  const _HelpTipCard(this.title, this.content);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              content,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 版本历史对话框 Widget ──

class _VersionHistoryDialog extends StatefulWidget {
  final String articleId;
  final String articleTitle;
  final VersionSnapshotService versionSnapshotService;
  final ValueChanged<String> onRestore;

  const _VersionHistoryDialog({
    required this.articleId,
    required this.articleTitle,
    required this.versionSnapshotService,
    required this.onRestore,
  });

  @override
  State<_VersionHistoryDialog> createState() => _VersionHistoryDialogState();
}

class _VersionHistoryDialogState extends State<_VersionHistoryDialog> {
  List<VersionSnapshot>? _snapshots;
  bool _loading = true;
  String? _previewContent;
  String? _previewId;

  @override
  void initState() {
    super.initState();
    _loadSnapshots();
  }

  Future<void> _loadSnapshots() async {
    final snapshots = await widget.versionSnapshotService.getSnapshots(
      widget.articleId,
    );
    if (mounted)
      setState(() {
        _snapshots = snapshots.reversed.toList();
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.history, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '版本历史 — ${widget.articleTitle}',
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: 500,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _snapshots == null || _snapshots!.isEmpty
            ? const Center(
                child: Text('暂无版本快照', style: TextStyle(color: Colors.grey)),
              )
            : Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: ListView.builder(
                      itemCount: _snapshots!.length,
                      itemBuilder: (_, i) {
                        final s = _snapshots![i];
                        final isSelected = _previewId == s.id;
                        final time =
                            '${s.createdAt.month.toString().padLeft(2, '0')}-${s.createdAt.day.toString().padLeft(2, '0')} ${s.createdAt.hour.toString().padLeft(2, '0')}:${s.createdAt.minute.toString().padLeft(2, '0')}';
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.1),
                          title: Text(
                            time,
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                          subtitle: Text(
                            '${s.contentLength} 字符',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () async {
                            final content = await widget.versionSnapshotService
                                .getSnapshotContent(widget.articleId, s.id);
                            if (mounted)
                              setState(() {
                                _previewId = s.id;
                                _previewContent = content ?? '';
                              });
                          },
                        );
                      },
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _previewContent == null
                        ? const Center(
                            child: Text(
                              '点击左侧快照预览',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    _previewContent!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        widget.onRestore(_previewContent!);
                                        Navigator.pop(context);
                                      },
                                      child: const Text('恢复此版本'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

// ============================================================
// Diff 模型
// ============================================================

enum _DiffType { equal, added, removed }

class _DiffLine {
  final _DiffType type;
  final String text;
  final int lineNum;

  const _DiffLine({
    required this.type,
    required this.text,
    required this.lineNum,
  });
}

// ============================================================
// 同步冲突解决对话框
// ============================================================

class _ConflictResolutionDialog extends StatefulWidget {
  final List<SyncEntry> conflicts;
  final List<Article> drafts;
  final SyncService syncService;
  final SiteManager siteManager;
  final ValueChanged<Map<String, String>> onResolved;

  const _ConflictResolutionDialog({
    required this.conflicts,
    required this.drafts,
    required this.syncService,
    required this.siteManager,
    required this.onResolved,
  });

  @override
  State<_ConflictResolutionDialog> createState() =>
      _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState extends State<_ConflictResolutionDialog> {
  final Map<String, String> _resolutions =
      {}; // articleId -> 'local' | 'remote'
  int _currentIndex = 0;

  SyncEntry get currentConflict => widget.conflicts[_currentIndex];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final localArticle = widget.drafts.firstWhere(
      (a) => a.id == currentConflict.localArticleId,
      orElse: () => Article(
        id: currentConflict.localArticleId ?? '',
        title: currentConflict.title,
        content: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.compare_arrows, size: 22, color: Colors.orange),
          const SizedBox(width: 8),
          Text(
            '同步冲突 (${_currentIndex + 1}/${widget.conflicts.length})',
            style: const TextStyle(fontSize: 17),
          ),
        ],
      ),
      content: SizedBox(
        width: 900,
        height: 550,
        child: Column(
          children: [
            // 冲突标题
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    size: 18,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '冲突文章: ${currentConflict.title}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 策略选择
            Row(
              children: [
                _strategyChip('local', '保留本地', Icons.phone_android, cs),
                const SizedBox(width: 8),
                _strategyChip('remote', '使用云端', Icons.cloud, cs),
                const SizedBox(width: 8),
                _strategyChip('skip', '稍后处理', Icons.skip_next, cs),
                const Spacer(),
                Text(
                  '本地: ${currentConflict.localModifiedAt?.toString().substring(0, 16) ?? "未知"}  |  云端: ${currentConflict.remoteModifiedAt?.toString().substring(0, 16) ?? "未知"}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 双栏 Diff 对比
            Expanded(
              child: Row(
                children: [
                  // 本地版本
                  Expanded(
                    child: _buildDiffPane(
                      '本地版本',
                      Icons.phone_android,
                      Colors.blue,
                      localArticle.content,
                      _resolutions[currentConflict.localArticleId] == 'local',
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  // 云端版本
                  Expanded(
                    child: _buildDiffPane(
                      '云端版本',
                      Icons.cloud,
                      Colors.green,
                      '(云端内容将在同步时获取)',
                      _resolutions[currentConflict.localArticleId] == 'remote',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.conflicts.length > 1)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.flag, size: 16),
                label: const Text('全部本地优先'),
                onPressed: () {
                  for (final c in widget.conflicts) {
                    _resolutions[c.localArticleId ?? ''] = 'local';
                  }
                  widget.onResolved(_resolutions);
                },
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.cloud, size: 16),
                label: const Text('全部云端优先'),
                onPressed: () {
                  for (final c in widget.conflicts) {
                    _resolutions[c.localArticleId ?? ''] = 'remote';
                  }
                  widget.onResolved(_resolutions);
                },
              ),
            ],
          ),
        const Spacer(),
        if (_currentIndex > 0)
          TextButton(
            onPressed: () => setState(() => _currentIndex--),
            child: const Text('上一个'),
          ),
        if (_currentIndex < widget.conflicts.length - 1)
          TextButton(
            onPressed: () {
              setState(() => _currentIndex++);
            },
            child: const Text('下一个'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('应用解决'),
          onPressed: () {
            for (final c in widget.conflicts) {
              if (c.localArticleId != null &&
                  !_resolutions.containsKey(c.localArticleId)) {
                _resolutions[c.localArticleId!] = 'skip';
              }
            }
            widget.onResolved(_resolutions);
          },
        ),
      ],
    );
  }

  Widget _strategyChip(
    String value,
    String label,
    IconData icon,
    ColorScheme cs,
  ) {
    final isSelected = _resolutions[currentConflict.localArticleId] == value;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
      selected: isSelected,
      onSelected: (v) {
        setState(() {
          if (v) {
            _resolutions[currentConflict.localArticleId ?? ''] = value;
          } else {
            _resolutions.remove(currentConflict.localArticleId);
          }
        });
      },
    );
  }

  Widget _buildDiffPane(
    String title,
    IconData icon,
    Color color,
    String content,
    bool isSelected,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? color : Colors.grey.withOpacity(0.2),
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 14, color: isSelected ? color : Colors.grey),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? color : Colors.grey,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.check_circle, size: 14, color: Colors.green),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Text(
                content,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
