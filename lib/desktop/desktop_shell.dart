/// 桌面版主界面外壳
/// 复刻手机版全部功能，使用桌面优化布局：
/// 顶栏 + 左面板(可折叠) + 中央编辑器 + 右悬浮抽屉 + 底栏
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:file_picker/file_picker.dart';

import '../models/ai_profile.dart';
import '../models/app_settings.dart';
import '../models/article.dart';
import '../models/blog_framework.dart';
import '../models/blog_site_config.dart';
import '../models/blog_post.dart';
import '../models/github_token_profile.dart';
import '../models/repo_config.dart';
import '../models/session_state.dart';
import '../models/template_item.dart';
import '../core/ai/ai_model_entity.dart';
import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/ai/ai_session_manager.dart';
import '../core/ai/theme_migration_service.dart';
import '../core/template_engine/template_resolver.dart';
import '../screens/ai_article_chat_screen.dart';
import '../screens/ai_audit_screen.dart';
import '../screens/ai_model_manager_screen.dart';
import '../screens/ai_theme_chat_screen.dart';
import '../screens/article_reader_screen.dart';
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
import '../screens/template_manager_screen.dart';
import '../screens/theme_migration_screen.dart';
import '../screens/tool_library_screen.dart';
import '../screens/log_screen.dart';
import '../core/tools/skill_manager.dart';
import '../core/tools/remote_cms_tools.dart';
import '../core/cancel_token.dart';
import '../core/site_manager.dart';
import '../core/repository/blog_repository.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/image_service.dart';
import '../services/rss_service.dart';
import '../services/session_service.dart';
import '../services/storage_service.dart';
import '../services/cms_draft_service.dart';
import '../services/webdav_service.dart';
import '../services/log_service.dart';
import '../services/sync_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/html_to_markdown.dart';
import '../services/recycle_bin_service.dart';
import '../services/version_snapshot_service.dart';
import '../services/frontmatter_service.dart';
import '../screens/recycle_bin_screen.dart';
import '../screens/image_bed_screen.dart';
import '../screens/link_checker_screen.dart';
import '../screens/batch_tools_screen.dart';
import '../screens/ai_prompt_templates_screen.dart';
import '../theme/app_theme.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart' as highlight_github;
import 'package:flutter_highlight/themes/monokai-sublime.dart' as highlight_monokai;
import 'package:flutter_highlight/themes/dracula.dart' as highlight_dracula;
import 'package:flutter_highlight/themes/nord.dart' as highlight_nord;
import 'package:flutter_highlight/themes/vs.dart' as highlight_vs;
import 'package:flutter_math_fork/flutter_math_fork.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:printing/printing.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:gbk_codec/gbk_codec.dart';

import 'widgets/title_bar.dart';
import 'widgets/left_panel.dart';
import 'widgets/editor_area.dart';
import 'widgets/right_drawer.dart';
import 'widgets/status_bar.dart';
import 'widgets/work_mode.dart';
import 'widgets/editor_themes.dart';

// ============================================================
// 桌面版 Shell — 完整功能复刻
// ============================================================

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => DesktopShellState();
}

class DesktopShellState extends State<DesktopShell> with WidgetsBindingObserver {
  // ──────────────────────────────────────────────
  // 服务层
  // ──────────────────────────────────────────────
  final storage = StorageService();
  final github = GitHubService();
  late final imageService = ImageService(github);
  final aiService = AiService();
  late final aiModelManager = AiModelManager(storage);
  late final aiDispatcher = AiRequestDispatcher(aiService, aiModelManager);
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
  late SiteManager siteManager;

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
  String? error;

  // ──────────────────────────────────────────────
  // 布局状态
  // ──────────────────────────────────────────────
  bool _leftPanelExpanded = true;
  double _leftPanelWidth = 260;
  bool _rightDrawerOpen = false;
  RightDrawerTab _activeDrawerTab = RightDrawerTab.outline;
  WorkMode _workMode = WorkMode.workspace;
  ThemeMode _themeMode = ThemeMode.system;

  // ──────────────────────────────────────────────
  // 编辑器标签页
  // ──────────────────────────────────────────────
  final List<EditorTab> _openTabs = [];
  int _activeTabIndex = -1;

  // ──────────────────────────────────────────────
  // 编辑器状态
  // ──────────────────────────────────────────────
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  late TextEditingController _tagsCtrl;
  late TextEditingController _categoriesCtrl;
  late TextEditingController _coverCtrl;
  late Article _currentArticle;
  String _articleType = 'post';
  String? _selectedTemplateId;
  RepoConfig? _editorRepo;
  bool _editorBusy = false;
  String? _editorStatus;
  final CancelToken _publishCancelToken = CancelToken();
  Uint8List? _failedImageBytes;
  final FocusNode _contentFocus = FocusNode();

  // ──────────────────────────────────────────────
  // 工作区文件夹
  // ──────────────────────────────────────────────
  String? _workspaceFolder;
  final ScrollController _focusScrollCtrl = ScrollController();
  // 打字机滚动：记录上次光标行号，用于判断是否需要滚动
  int _lastCursorLine = 0;

  // ──────────────────────────────────────────────
  // 自动保存
  // ──────────────────────────────────────────────
  Timer? _autoSaveTimer;
  Timer? _debounceTimer;
  Timer? _autoSyncTimer;
  String _lastSavedContent = '';
  bool _hasUnsavedChanges = false;

  // ──────────────────────────────────────────────
  // 会话
  // ──────────────────────────────────────────────
  SessionState _lastSession = SessionState.empty;
  bool _sessionRestored = false;

  // ──────────────────────────────────────────────
  // 最近打开文件
  // ──────────────────────────────────────────────
  final List<RecentFile> _recentFiles = [];
  static const int _maxRecentFiles = 10;

  // ──────────────────────────────────────────────
  // 编辑器统计
  // ──────────────────────────────────────────────
  int _wordCount = 0;
  int _charCount = 0;
  (int, int) _cursorPos = (1, 1);

  // ──────────────────────────────────────────────
  // 编辑器自定义设置
  // ──────────────────────────────────────────────
  /// 字体设置
  double _editorFontSize = 16.0;
  double _editorLineHeight = 1.6;
  String _editorFontFamily = 'System';

  /// 编辑器主题
  String _editorTheme = 'default';

  /// 自定义 CSS
  String _customCss = '';

  /// 自定义快捷键
  Map<String, String> _customShortcuts = {};

  // ──────────────────────────────────────────────
  // 图片路径模式
  // ──────────────────────────────────────────────
  bool _useRelativeImagePath = false;

  // ──────────────────────────────────────────────
  // 同步日志
  // ──────────────────────────────────────────────
  final List<String> _syncLogs = [];

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _titleCtrl = TextEditingController();
    _contentCtrl = TextEditingController();
    _tagsCtrl = TextEditingController();
    _categoriesCtrl = TextEditingController();
    _coverCtrl = TextEditingController();
    syncService = SyncService(logService);
    cloudSyncService = CloudSyncService(logService);
    recycleBinService = RecycleBinService();
    versionSnapshotService = VersionSnapshotService(logService);
    frontMatterService = FrontMatterService(logService);
    _currentArticle = Article(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: '',
      content: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDraft: true,
      repoId: activeRepo?.id,
      articleType: 'post',
    );
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoSave();
    _stopAutoSync();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _tagsCtrl.dispose();
    _categoriesCtrl.dispose();
    _coverCtrl.dispose();
    _contentFocus.dispose();
    _focusScrollCtrl.dispose();
    siteManager.disposeAll();
    cmsDraftService.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _autoSyncToCloud();
    } else if (state == AppLifecycleState.resumed) {
      _autoPullFromCloud();
    }
  }

  // ============================================================
  // 启动
  // ============================================================

  Future<void> _bootstrap() async {
    setState(() => loading = true);
    try {
      var s = await storage.loadSettings();
      var r = await storage.loadRepos();
      final d = await storage.loadDrafts();
      final t = await storage.loadAllTemplates();
      final sn = await storage.loadSnippets();
      s = _ensureGithubTokensFromLegacy(s, r);
      await storage.saveSettings(s);
      if (r.isEmpty) {
        r = [
          RepoConfig(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: '小子的博客',
            owner: 'caogenfunan123',
            repo: 'xiamend',
            branch: 'main',
            postsPath: 'source/_posts',
            siteUrl: 'https://caogenfunan.me/',
            token: s.effectiveGithubToken,
            isDefault: true,
          )
        ];
        await storage.saveRepos(r);
        s = s.copyWith(activeRepoId: r.first.id, imageBedOwner: 'caogenfunan123', imageBedRepo: 'xiamend');
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
      String? autoTemplateId;
      if (_editorRepo != null) {
        autoTemplateId = TemplateResolver.resolvePostTemplateId(_editorRepo!, t);
        _selectedTemplateId = autoTemplateId;
      }
      setState(() {
        settings = s;
        repos = r;
        drafts = d..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        templates = t;
        snippets = sn;
        loading = false;
      });
      _updateSiteManager();
      if (s.restoreSession) {
        await _restoreSession();
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
    try {
      await skillManager.init(await storage.root);
    } catch (_) {}
    _loadRecentFiles();
    _loadEditorSettings();
    _initCloudSync();
    _initRecycleBin();
    _initVersionSnapshots();
    _initFrontMatter();
  }

  void _initCloudSync() async {
    final deviceKey = await storage.loadDeviceKey();
    cloudSyncService.initDeviceKey(deviceKey);
    final githubBackend = GitHubSyncBackend(github);
    cloudSyncService.registerBackend(githubBackend);
    if (effectiveRepo != null) {
      githubBackend.configureRepo(effectiveRepo!);
    }
    final webdavBackend = WebDavSyncBackend();
    webdavBackend.configureFromSettings(settings);
    cloudSyncService.registerBackend(webdavBackend);
    _startAutoSync();
    if (cloudSyncService.hasConfiguredBackend) {
      _autoPullFromCloud();
    }
  }

  void _initRecycleBin() async {
    try {
      await recycleBinService.init(await storage.root);
      // 自动清理超过30天的回收站文件
      await recycleBinService.autoClean(30);
    } catch (_) {}
  }

  void _initVersionSnapshots() async {
    try {
      await versionSnapshotService.init(await storage.root);
      // 自动清理超过7天的快照
      await versionSnapshotService.autoClean(days: 7);
    } catch (_) {}
  }

  void _initFrontMatter() async {
    try {
      frontMatterService.refreshFromArticles(drafts);
    } catch (_) {}
  }

  AppSettings _ensureGithubTokensFromLegacy(AppSettings s, List<RepoConfig> repos) {
    var tokens = List<GithubTokenProfile>.from(s.githubTokens);
    bool changed = false;
    if (s.defaultToken.isNotEmpty && !tokens.any((t) => t.token == s.defaultToken)) {
      tokens.add(GithubTokenProfile(id: 'legacy_token', name: '默认 Token', token: s.defaultToken));
      changed = true;
    }
    for (final r in repos) {
      if (r.token.isNotEmpty && !tokens.any((t) => t.token == r.token)) {
        tokens.add(GithubTokenProfile(id: 'repo_${r.id}', name: r.name, token: r.token));
        changed = true;
      }
    }
    if (changed) {
      final seen = <String>{};
      tokens = tokens.where((t) => seen.add(t.token.trim())).toList();
      return s.copyWith(githubTokens: tokens, activeGithubTokenId: tokens.first.id);
    }
    return s;
  }

  // ============================================================
  // 自动保存
  // ============================================================

  void _startAutoSave() {
    _stopAutoSave();
    if (!settings.autoSaveEnabled) return;
    _autoSaveTimer = Timer.periodic(
      Duration(seconds: settings.autoSaveIntervalSeconds),
      (_) => _autoSaveSnapshot(),
    );
  }

  void _stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void _onContentChanged() {
    final current = _contentCtrl.text;
    if (current == _lastSavedContent) {
      _hasUnsavedChanges = false;
      return;
    }
    _hasUnsavedChanges = true;
    _trackStats();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), _autoSaveSnapshot);
  }

  void _trackStats() {
    final text = _contentCtrl.text;
    _charCount = text.length;
    _wordCount = text.isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final sel = _contentCtrl.selection;
    if (sel.isValid) {
      final before = text.substring(0, sel.start);
      final line = '\n'.allMatches(before).length + 1;
      final lastNewline = before.lastIndexOf('\n');
      final col = lastNewline < 0 ? sel.start + 1 : sel.start - lastNewline;
      _cursorPos = (line, col);

      // 打字机滚动：专注模式下光标始终在屏幕中间
      if (_workMode == WorkMode.focus && line != _lastCursorLine) {
        _lastCursorLine = line;
        _centerCursorInFocusMode(line);
      }
    }
    if (mounted) setState(() {}); // 确保状态栏实时刷新
  }

  /// 专注模式下将光标所在行滚动到屏幕中央
  void _centerCursorInFocusMode(int line) {
    if (!_focusScrollCtrl.hasClients) return;
    final lineHeight = _editorFontSize * _editorLineHeight;
    final viewportHeight = _focusScrollCtrl.position.viewportDimension;
    final targetY = (line - 1) * lineHeight - viewportHeight / 2 + lineHeight;
    if (targetY < 0) return;
    _focusScrollCtrl.animateTo(
      targetY.clamp(0, _focusScrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Future<void> _autoSaveSnapshot() async {
    final content = _contentCtrl.text;
    if (content.isEmpty || content == _lastSavedContent) return;
    final title = _titleCtrl.text;
    try {
      await sessionService.saveAutoSnapshot(
        articleId: _currentArticle.id,
        content: content,
        title: title.isEmpty ? '未命名' : title,
        tags: _tagsCtrl.text,
        categories: _categoriesCtrl.text,
        cover: _coverCtrl.text,
      );
      _lastSavedContent = content;
      _hasUnsavedChanges = false;
      await sessionService.cleanupSnapshots(_currentArticle.id);
      await _saveDraft(_collect(draft: true));
      if (mounted) _showToast('草稿已自动保存');
    } catch (_) {}
  }

  // ============================================================
  // 云同步
  // ============================================================

  void _startAutoSync() {
    _stopAutoSync();
    if (!settings.webdavAutoSyncEnabled) return;
    _autoSyncTimer = Timer.periodic(
      Duration(seconds: settings.webdavAutoSyncIntervalSeconds),
      (_) => _autoSyncToCloud(),
    );
  }

  void _stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  Future<void> _autoSyncToCloud() async {
    if (busy) return;
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) return;
    try {
      await cloudSyncService.pushDrafts(backend, drafts);
      await cloudSyncService.pushSyncMappings(backend, syncService);
    } catch (_) {}
  }

  Future<void> _autoPullFromCloud() async {
    if (busy) return;
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) return;
    try {
      final pulled = await cloudSyncService.pullDrafts(backend, existingDrafts: drafts);
      if (pulled.isNotEmpty) {
        setState(() {
          drafts = pulled..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        });
        storage.saveDrafts(drafts);
      }
      await cloudSyncService.pullSyncMappings(backend, syncService);
    } catch (_) {}
  }

  Future<void> _pushAllToCloud() async {
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) { _showToast('请先配置同步后端'); return; }
    setState(() => busy = true);
    try {
      final result = await cloudSyncService.pushAll(backend, drafts: drafts, settings: settings, syncService: syncService, templates: templates, snippets: snippets);
      if (mounted) {
        setState(() => busy = false);
        if (result.isSuccess) { _showToast('推送完成: ${result.pushed} 项'); } else { _showToast('推送完成: ${result.pushed} 成功, ${result.errors.length} 失败'); }
      }
    } catch (e) { if (mounted) { setState(() => busy = false); _showToast('推送失败: $e'); } }
  }

  Future<void> _pullAllFromCloud() async {
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) { _showToast('请先配置同步后端'); return; }
    setState(() => busy = true);
    try {
      await cloudSyncService.pullAll(backend,
        existingDrafts: drafts, syncService: syncService,
        onSettingsLoaded: (s) { setState(() => settings = s); _updateSiteManager(); _startAutoSync(); storage.saveSettings(s); },
        onDraftsLoaded: (d) { setState(() { drafts = d..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); }); storage.saveDrafts(drafts); },
        onTemplatesLoaded: (tList) {
          final merged = <TemplateItem>[];
          final seen = <String>{};
          for (final remote in tList) {
            final t = TemplateItem.fromJson(remote);
            merged.add(t);
            seen.add(t.id);
          }
          for (final t in templates) {
            if (!seen.contains(t.id)) merged.add(t);
          }
          setState(() => templates = merged);
          storage.saveTemplates(merged);
        },
        onSnippetsLoaded: (sList) {
          final merged = <SnippetItem>[];
          final seen = <String>{};
          for (final s in sList) {
            final item = SnippetItem.fromJson(s);
            merged.add(item);
            seen.add(item.id);
          }
          for (final s in snippets) {
            if (!seen.contains(s.id)) merged.add(s);
          }
          setState(() => snippets = merged);
          storage.saveSnippets(merged);
        },
      );
      if (mounted) { setState(() => busy = false); _showToast('拉取完成'); }
    } catch (e) { if (mounted) { setState(() => busy = false); _showToast('拉取失败: $e'); } }
  }

  // ============================================================
  // 会话管理
  // ============================================================

  Future<void> _restoreSession() async {
    if (_sessionRestored) return;
    _sessionRestored = true;
    try {
      final session = await sessionService.loadSession();
      if (!session.hasArticle || session.isHome) return;
      _lastSession = session;
      final article = Article(
        id: session.articleId,
        title: session.articleTitle,
        content: session.articleContent,
        tags: session.articleTags.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        categories: session.articleCategories.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        cover: session.articleCover.isEmpty ? null : session.articleCover,
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
        isDraft: true, repoId: session.articleRepoId,
        remotePath: session.articleRemotePath, remoteSha: session.articleRemoteSha,
      );
      if (session.pageType == SessionPageType.editor) {
        _openExistingArticle(article);
      }
    } catch (_) {}
  }

  // ============================================================
  // 文章操作
  // ============================================================

  Article _collect({bool draft = true}) {
    final cover = _coverCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    return _currentArticle.copyWith(
      title: title.isEmpty ? '未命名' : title,
      content: _contentCtrl.text,
      tags: _tagsCtrl.text.split(RegExp(r'[,，]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      categories: _categoriesCtrl.text.split(RegExp(r'[,，]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      cover: cover.isEmpty ? null : cover,
      updatedAt: DateTime.now(),
      isDraft: draft,
      published: draft ? false : true,
      repoId: _editorRepo?.id ?? _currentArticle.repoId,
      articleType: _articleType,
      templateId: _selectedTemplateId,
    );
  }

  RepoConfig? get _resolvedRepo {
    final r = _editorRepo;
    if (r == null) return null;
    if (r.token.isNotEmpty) return r;
    final t = settings.effectiveGithubToken;
    if (t.isEmpty) return r;
    return r.copyWith(token: t);
  }

  String _generateSlug(String title) {
    final slug = title.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? 'untitled' : slug;
  }

  // ============================================================
  // 保存草稿
  // ============================================================

  Future<void> _saveDraft(Article a) async {
    final i = drafts.indexWhere((e) => e.id == a.id);
    if (i >= 0) drafts[i] = a; else drafts.insert(0, a);
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await storage.saveDrafts(drafts);
    await storage.exportDraftMarkdown(a);
    if (mounted) setState(() {});
  }

  Future<void> _saveLocal() async {
    final a = _collect(draft: true);
    setState(() {
      _currentArticle = a;
      _editorStatus = '本地已保存';
    });
    await _saveDraft(a);
    if (siteManager.isDynamicSite) {
      final adapter = siteManager.currentAdapter;
      if (adapter != null) {
        final post = BlogPost(
          title: a.title, contentMd: a.content, status: 'draft',
          slug: _generateSlug(a.title), tags: a.tags, categories: a.categories,
          date: DateTime.now(), siteId: adapter.config.id, siteType: adapter.config.type,
        );
        await cmsDraftService.saveDraft(post);
      }
    }
    _lastSavedContent = a.content;
    _hasUnsavedChanges = false;
    // 创建版本快照
    versionSnapshotService.createSnapshot(a.id, a.title, a.content);
    logService.add('保存草稿', '标题: ${a.title.isNotEmpty ? a.title : "(无标题)"}');
    if (mounted) _showToast('草稿已保存到本地');
  }

  Future<void> _saveMdBackup() async {
    try {
      final a = _collect(draft: false);
      final rootDir = await storage.root;
      final dir = Directory('${rootDir.path}/hexo_backups');
      if (!await dir.exists()) await dir.create(recursive: true);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final safeTitle = a.title.isNotEmpty ? a.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_') : 'untitled';
      final fileName = '${timestamp}_$safeTitle.md';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(a.toMarkdownWithFrontMatter());
      if (mounted) _showToast('MD 备份已保存到 hexo_backups/$fileName');
    } catch (e) {
      if (mounted) _showToast('MD 备份保存失败: $e');
    }
  }

  // ============================================================
  // 发布
  // ============================================================

  Future<void> _handlePublish() async {
    // 先检查同步冲突
    if (siteManager.isDynamicSite) {
      final canProceed = await _checkAndResolveConflicts();
      if (!canProceed) {
        _showToast('存在同步冲突，请先解决冲突后再发布');
        return;
      }
    }

    final publishTarget = siteManager.isDynamicSite
        ? siteManager.currentBlogType.displayName
        : (_resolvedRepo?.fullName ?? 'GitHub');
    bool saveMdBackup = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.cloud_upload_outlined, color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            const Text('确认发布', style: TextStyle(fontSize: 17)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('即将发布到: $publishTarget', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text('标题: ${_titleCtrl.text.isNotEmpty ? _titleCtrl.text : "(无标题)"}', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: saveMdBackup,
                onChanged: (v) => setDialogState(() => saveMdBackup = v ?? false),
                title: const Text('同时保存一份 MD 备份到本地目录', style: TextStyle(fontSize: 13)),
                subtitle: const Text('备份到文档目录的 hexo_backups/ 文件夹', style: TextStyle(fontSize: 11)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton.icon(icon: const Icon(Icons.cloud_upload_outlined, size: 18), label: const Text('确认发布'), onPressed: () => Navigator.pop(ctx, true)),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    if (saveMdBackup) await _saveMdBackup();

    // FrontMatter 校验
    final article = _collect(draft: false);
    final validation = frontMatterService.validate(article);
    if (!validation.isValid) {
      final missing = validation.missingFields.join('、');
      final warnings = validation.warnings.join('\n');
      final continuePublish = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
            SizedBox(width: 8),
            Text('发布前校验', style: TextStyle(fontSize: 17)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('缺少必填字段: $missing', style: const TextStyle(color: Colors.red, fontSize: 13)),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(warnings, style: TextStyle(fontSize: 12, color: Colors.orange[700])),
              ],
              const SizedBox(height: 12),
              const Text('是否继续发布？', style: TextStyle(fontSize: 13)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续发布')),
          ],
        ),
      );
      if (continuePublish != true || !mounted) return;
    }

    // 增强发布预检测：空内容、图片链接、语法检查
    final preCheckWarnings = <String>[];
    // 空内容检查
    if (article.content.trim().isEmpty) {
      preCheckWarnings.add('⚠ 文章内容为空');
    }
    // 图片链接检查
    final imgRegex = RegExp(r'!\[.*?\]\((https?://[^\s)]+)\)');
    final imgMatches = imgRegex.allMatches(article.content).toList();
    if (imgMatches.isNotEmpty) {
      preCheckWarnings.add('ℹ 文章包含 ${imgMatches.length} 个外部图片链接，建议检查图片是否可访问');
    }
    // 空标题检查
    if (article.title.isEmpty || article.title == '未命名') {
      preCheckWarnings.add('⚠ 文章标题为空或未命名');
    }
    // 内容过短检查
    if (article.content.trim().length < 20 && article.content.trim().isNotEmpty) {
      preCheckWarnings.add('⚠ 文章内容过短（<20字符），建议补充内容');
    }

    if (preCheckWarnings.isNotEmpty) {
      final continuePublish2 = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.fact_check_outlined, color: Colors.blue, size: 22),
            SizedBox(width: 8),
            Text('发布预检测', style: TextStyle(fontSize: 17)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...preCheckWarnings.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(w, style: const TextStyle(fontSize: 13)),
              )),
              const SizedBox(height: 12),
              const Text('是否继续发布？', style: TextStyle(fontSize: 13)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续发布')),
          ],
        ),
      );
      if (continuePublish2 != true || !mounted) return;
    }

    if (siteManager.isDynamicSite) {
      await _publishToCms();
      return;
    }

    final repo = _resolvedRepo;
    if (repo == null || repo.token.isEmpty) {
      _showToast('请先配置仓库与 Token');
      return;
    }
    setState(() { _editorBusy = true; _editorStatus = '正在发布...'; });
    try {
      final a = _collect(draft: false);
      final pub = await github.upsertArticle(repo, a);
      setState(() { _currentArticle = pub; _editorStatus = '已发布'; });
      _lastSavedContent = pub.content;
      _hasUnsavedChanges = false;
      await _saveDraft(pub.copyWith(isDraft: false, published: true));
      await _refreshRemote();
      logService.add('发布成功', '已发布到 ${repo.fullName}: ${pub.title}');
      if (mounted) _showToast('已发布到 ${repo.fullName}');
    } catch (e) {
      setState(() => _editorStatus = '发布失败');
      logService.add('发布失败', '$e', success: false);
      if (mounted) _showToast('发布失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
  }

  Future<void> _publishToCms() async {
    final adapter = siteManager.currentAdapter;
    if (adapter == null) {
      _showToast('当前站点未配置动态 CMS 适配器，请先添加 CMS 站点');
      return;
    }
    final a = _collect(draft: false);
    setState(() { _editorBusy = true; _editorStatus = '正在发布到 ${adapter.config.type.displayName}...'; });
    try {
      final remoteId = _currentArticle.remoteSha != null ? int.tryParse(_currentArticle.remoteSha!) : null;
      final post = BlogPost(
        id: remoteId, title: a.title, contentMd: a.content, status: 'publish',
        slug: _generateSlug(a.title), tags: a.tags, categories: a.categories,
        date: DateTime.now(), siteId: adapter.config.id, siteType: adapter.config.type,
      );
      final result = remoteId != null ? await adapter.updatePost(post) : await adapter.createPost(post);
      final pub = a.copyWith(isDraft: false, published: true, remotePath: result.link, remoteSha: result.id?.toString());
      setState(() { _currentArticle = pub; _editorStatus = '已发布到 ${adapter.config.type.displayName}'; });
      _lastSavedContent = a.content;
      _hasUnsavedChanges = false;
      await _saveDraft(pub);
      await cmsDraftService.saveDraft(result);
      if (result.id != null) {
        syncService.setMapping(SyncMapping(
          localArticleId: pub.id, remotePostId: result.id!, siteId: adapter.config.id,
          lastSyncAt: DateTime.now(), localModifiedAt: pub.updatedAt, remoteModifiedAt: result.modifiedDate,
        ));
      }
      logService.add('CMS发布成功', '已发布到 ${adapter.config.type.displayName}: ${result.title}');
      if (mounted) _showToast('已发布到 ${adapter.config.type.displayName}: ${result.link ?? result.title}');
    } catch (e) {
      setState(() => _editorStatus = '发布失败');
      logService.add('CMS发布失败', '$e', success: false);
      if (mounted) _showToast('发布失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
  }

  // ============================================================
  // 远程操作
  // ============================================================

  Future<void> _refreshRemote() async {
    final repo = effectiveRepo;
    if (repo == null || repo.token.isEmpty) return;
    setState(() => busy = true);
    try { remotePosts = await github.listPosts(repo); } catch (_) {}
    if (mounted) setState(() => busy = false);
  }

  Future<void> _refreshRss() async {
    final url = activeRepo?.siteUrl.isNotEmpty == true ? activeRepo!.siteUrl : 'https://caogenfunan.me/';
    try { rssItems = await rssService.fetch(url); if (mounted) setState(() {}); } catch (_) {}
  }

  Future<void> _refreshCommits() async {
    final repo = effectiveRepo;
    if (repo == null || repo.token.isEmpty) return;
    try { commits = await github.listCommits(repo); if (mounted) setState(() {}); } catch (_) {}
  }

  // ============================================================
  // 设置更新
  // ============================================================

  Future<void> _updateSettings(AppSettings s) async {
    setState(() => settings = s);
    _updateSiteManager();
    _startAutoSync();
    await storage.saveSettings(s);
  }

  Future<void> _updateRepos(List<RepoConfig> r) async {
    setState(() => repos = r);
    _updateSiteManager();
    await storage.saveRepos(r);
  }

  Future<void> _persistSettings() => storage.saveSettings(settings);
  Future<void> _persistRepos() => storage.saveRepos(repos);

  // ──────────────────────────────────────────────
  // 编辑器自定义设置持久化
  // ──────────────────────────────────────────────

  /// 加载编辑器自定义设置
  Future<void> _loadEditorSettings() async {
    try {
      final rootDir = await storage.root;
      final file = File('${rootDir.path}/editor_settings.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _editorFontSize = (data['fontSize'] as num?)?.toDouble() ?? 16.0;
            _editorLineHeight = (data['lineHeight'] as num?)?.toDouble() ?? 1.6;
            _editorFontFamily = data['fontFamily'] as String? ?? 'System';
            _editorTheme = data['editorTheme'] as String? ?? 'default';
            _customCss = data['customCss'] as String? ?? '';
            _customShortcuts = (data['customShortcuts'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v.toString())) ?? {};
          });
        }
      }
    } catch (_) {}
  }

  /// 保存编辑器自定义设置
  Future<void> _saveEditorSettings() async {
    try {
      final rootDir = await storage.root;
      final file = File('${rootDir.path}/editor_settings.json');
      await file.writeAsString(jsonEncode({
        'fontSize': _editorFontSize,
        'lineHeight': _editorLineHeight,
        'fontFamily': _editorFontFamily,
        'editorTheme': _editorTheme,
        'customCss': _customCss,
        'customShortcuts': _customShortcuts,
      }));
    } catch (_) {}
  }

  // ============================================================
  // 草稿/文章管理
  // ============================================================

  void _openExistingArticle(Article a) {
    _currentArticle = a;
    _titleCtrl.text = a.title;
    _contentCtrl.text = a.content;
    _tagsCtrl.text = a.tags.join(', ');
    _categoriesCtrl.text = a.categories.join(', ');
    _coverCtrl.text = a.cover ?? '';
    _editorRepo = repos.where((r) => r.id == a.repoId).firstOrNull ?? activeRepo;
    _lastSavedContent = a.content;
    _hasUnsavedChanges = false;
    _startAutoSave();
    _addEditorTab(a);
    setState(() {});
  }

  Future<void> _deleteDraft(Article a) async {
    drafts.removeWhere((e) => e.id == a.id);
    await storage.saveDrafts(drafts);
    logService.add('删除草稿', '标题: ${a.title.isNotEmpty ? a.title : "(无标题)"}');
    if (mounted) setState(() {});
  }

  void _newArticle() {
    final repo = activeRepo;
    _editorRepo = repo;
    _articleType = 'post';
    String? autoTemplateId;
    if (repo != null) autoTemplateId = TemplateResolver.resolvePostTemplateId(repo, templates);
    _currentArticle = Article(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: '', content: '', createdAt: DateTime.now(), updatedAt: DateTime.now(),
      isDraft: true, repoId: repo?.id, articleType: _articleType, templateId: autoTemplateId,
    );
    _titleCtrl.text = '';
    _contentCtrl.text = '';
    _tagsCtrl.text = '';
    _categoriesCtrl.text = '';
    _coverCtrl.text = '';
    _lastSavedContent = '';
    _hasUnsavedChanges = false;
    _selectedTemplateId = autoTemplateId;
    _startAutoSave();
    _addEditorTab(_currentArticle);
    setState(() {});
  }

  // ============================================================
  // 标签页管理
  // ============================================================

  void _addEditorTab(Article article) {
    final tabId = 'editor_${article.id}';
    final existingIdx = _openTabs.indexWhere((t) => t.id == tabId);
    if (existingIdx >= 0) {
      _activeTabIndex = existingIdx;
      return;
    }
    _openTabs.add(EditorTab(
      id: tabId,
      title: article.title.isNotEmpty ? article.title : '未命名',
      icon: Icons.edit_note,
      content: _buildEmbeddedEditor(),
      canClose: true,
    ));
    _activeTabIndex = _openTabs.length - 1;
  }

  void _openTab(String id, String title, IconData icon, Widget content) {
    final existingIdx = _openTabs.indexWhere((t) => t.id == id);
    if (existingIdx >= 0) {
      _activeTabIndex = existingIdx;
      setState(() {});
      return;
    }
    _openTabs.add(EditorTab(id: id, title: title, icon: icon, content: content, canClose: true));
    _activeTabIndex = _openTabs.length - 1;
    setState(() {});
  }

  void _closeTab(int index) {
    setState(() {
      if (_openTabs.length <= 1) {
        _openTabs.clear();
        _activeTabIndex = -1;
        return;
      }
      _openTabs.removeAt(index);
      if (_activeTabIndex >= _openTabs.length) _activeTabIndex = _openTabs.length - 1;
      if (_activeTabIndex < 0) _activeTabIndex = 0;
    });
  }

  // ============================================================
  // 嵌入式编辑器
  // ============================================================

  Widget _buildEmbeddedEditor() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 标题栏
          TextField(
            controller: _titleCtrl,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _currentEditorTheme.headingColor,
              fontFamily: _resolveFontFamily(_editorFontFamily),
            ),
            decoration: const InputDecoration(
              hintText: '文章标题',
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => _onContentChanged(),
          ),
          const SizedBox(height: 8),
          // 元数据行
          Row(
            children: [
              _metaChip('文章', _articleType == 'post'),
              _metaChip('页面', _articleType == 'page'),
              const Spacer(),
              _editorToolButton(Icons.image_outlined, '插入图片', _insertImage),
              _editorToolButton(Icons.collections_outlined, '批量插图', _batchInsertImages),
              _editorToolButton(Icons.code, '代码块', _insertCodeBlock),
              _editorToolButton(Icons.toc, '插入目录', _insertToc),
              _editorToolButton(Icons.table_chart, '插入表格', _insertTable),
              PopupMenuButton<String>(
                tooltip: '图片尺寸',
                icon: const Icon(Icons.photo_size_select_large, size: 18),
                onSelected: _setImageSize,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                splashRadius: 18,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'small', child: Text('小 (200px)', style: TextStyle(fontSize: 13))),
                  const PopupMenuItem(value: 'medium', child: Text('中 (400px)', style: TextStyle(fontSize: 13))),
                  const PopupMenuItem(value: 'large', child: Text('大 (600px)', style: TextStyle(fontSize: 13))),
                  const PopupMenuItem(value: 'full', child: Text('全宽 (100%)', style: TextStyle(fontSize: 13))),
                ],
              ),
              _editorToolButton(Icons.auto_awesome, 'AI润色', () => _aiAction('polish')),
              _editorToolButton(Icons.auto_awesome, 'AI续写', () => _aiAction('continue')),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          // 内容编辑区
          Expanded(
            child: _workMode == WorkMode.source
                ? TextField(
                    controller: _contentCtrl,
                    maxLines: null,
                    expands: true,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: _editorFontSize,
                      height: _editorLineHeight,
                      color: _currentEditorTheme.textColor,
                    ),
                    decoration: const InputDecoration(
                      hintText: '开始写作...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => _onContentChanged(),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _contentCtrl,
                          maxLines: null,
                          expands: true,
                          style: TextStyle(
                            fontSize: _editorFontSize,
                            height: _editorLineHeight,
                            color: _currentEditorTheme.textColor,
                            fontFamily: _resolveFontFamily(_editorFontFamily),
                          ),
                          decoration: const InputDecoration(
                            hintText: '开始写作...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) => _onContentChanged(),
                        ),
                      ),
                      Container(width: 1, color: Colors.grey.shade200),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: _buildMarkdownPreview(_contentCtrl.text),
                        ),
                      ),
                    ],
                  ),
          ),
          // 底部操作栏
          if (_editorBusy)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(_editorStatus ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaChip(String label, bool active) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        setState(() => _articleType = label == '文章' ? 'post' : 'page');
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? cs.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? cs.primary : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: active ? cs.primary : Colors.grey.shade600)),
      ),
    );
  }

  Widget _editorToolButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: _editorBusy ? null : onTap,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
        splashRadius: 18,
      ),
    );
  }

  // ============================================================
  // 编辑器操作
  // ============================================================

  void _insertText(String t) {
    final sel = _contentCtrl.selection;
    final txt = _contentCtrl.text;
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(s, e, t),
      selection: TextSelection.collapsed(offset: s + t.length),
    );
    _contentFocus.requestFocus();
  }

  void _insertCodeBlock() {
    final sel = _contentCtrl.selection;
    final txt = _contentCtrl.text;
    final selected = (sel.isValid && sel.start != sel.end) ? txt.substring(sel.start, sel.end) : '';
    final fence = '```\n$selected\n```\n';
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(s, e, fence),
      selection: TextSelection.collapsed(offset: s + 4),
    );
    _contentFocus.requestFocus();
  }

  Future<void> _insertImage() async {
    setState(() { _editorBusy = true; _editorStatus = '正在选择图片...'; });
    try {
      final bytes = await imageService.pickImageBytes();
      if (bytes == null) { setState(() => _editorStatus = '已取消'); return; }
      _failedImageBytes = bytes;
      final sizeKB = (bytes.length / 1024).toStringAsFixed(1);
      setState(() => _editorStatus = '正在上传图片 ($sizeKB KB)...');
      final url = await imageService.uploadToImageBed(bytes, settings);
      _insertText(imageService.markdownImage(url));
      _failedImageBytes = null;
      setState(() => _editorStatus = '图片已插入');
    } catch (e) {
      _insertText('\n> ⚠️ 图片上传失败，[点击重试](#retry-upload)\n');
      setState(() => _editorStatus = '上传失败（可点击重试）');
      if (mounted) _showToast('上传失败，点击文中标记可重试');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
  }

  Future<void> _batchInsertImages() async {
    setState(() { _editorBusy = true; _editorStatus = '正在选择图片...'; });
    try {
      final bytesList = await imageService.pickMultipleImageBytes();
      if (bytesList == null || bytesList.isEmpty) { setState(() => _editorStatus = '已取消'); return; }
      final total = bytesList.length;
      setState(() => _editorStatus = '正在预处理 $total 张图片...');
      final preResult = await imageService.preprocessImages(bytesList, settings, onProgress: (current, total, beforeKB, afterKB) {
        if (mounted) setState(() => _editorStatus = '预处理 $current/$total: ${beforeKB}KB → ${afterKB}KB');
      });
      int uploaded = 0, failed = 0;
      final buf = StringBuffer();
      for (var i = 0; i < total; i++) {
        setState(() => _editorStatus = '正在上传图片 ${i + 1}/$total...');
        try {
          final url = await imageService.uploadToImageBed(preResult.images[i], settings, skipCompress: true);
          buf.writeln(imageService.markdownImage(url));
          uploaded++;
        } catch (_) {
          buf.writeln('> ⚠️ 第 ${i + 1} 张图片上传失败');
          failed++;
        }
      }
      _insertText('\n\n${buf.toString()}');
      setState(() => _editorStatus = '完成: $uploaded/$total 张上传成功');
    } catch (e) {
      setState(() => _editorStatus = '批量上传失败');
      if (mounted) _showToast('批量上传失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
  }

  Future<void> _aiAction(String action) async {
    setState(() { _editorBusy = true; _editorStatus = 'AI 处理中...'; });
    try {
      final text = _contentCtrl.text;
      switch (action) {
        case 'polish':
          final result = await aiService.polish(settings, text);
          _contentCtrl.text = result;
          break;
        case 'continue':
          final result = await aiService.continueWrite(settings, text);
          _insertText('\n\n$result');
          break;
        case 'summary':
          final result = await aiService.summarize(settings, text);
          if (mounted) {
            await showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('AI 摘要'),
                content: Text(result),
                actions: [
                  TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: result)); Navigator.pop(context); }, child: const Text('复制')),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
                ],
              ),
            );
          }
          break;
        case 'outline':
          final result = await aiService.generateOutline(settings, text);
          _insertText('\n$result');
          break;
      }
      setState(() => _editorStatus = 'AI 完成');
    } catch (e) {
      setState(() => _editorStatus = 'AI 失败');
      if (mounted) _showToast('AI 处理失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
  }

  // ============================================================
  // 查找/替换对话框
  // ============================================================

  void _showFindReplace() {
    final findCtrl = TextEditingController();
    final replaceCtrl = TextEditingController();
    bool caseSensitive = false;
    bool useRegex = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('查找和替换'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: findCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '查找',
                      hintText: '输入要查找的文本...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: replaceCtrl,
                    decoration: const InputDecoration(
                      labelText: '替换',
                      hintText: '输入替换文本...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: caseSensitive,
                        onChanged: (v) => setDialogState(() => caseSensitive = v ?? false),
                      ),
                      GestureDetector(
                        onTap: () => setDialogState(() => caseSensitive = !caseSensitive),
                        child: const Text('区分大小写', style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 24),
                      Checkbox(
                        value: useRegex,
                        onChanged: (v) => setDialogState(() => useRegex = v ?? false),
                      ),
                      GestureDetector(
                        onTap: () => setDialogState(() => useRegex = !useRegex),
                        child: const Text('正则表达式', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final findText = findCtrl.text;
                  if (findText.isEmpty) return;
                  _findNext(findText, caseSensitive: caseSensitive, useRegex: useRegex);
                },
                child: const Text('查找下一个'),
              ),
              TextButton(
                onPressed: () {
                  final findText = findCtrl.text;
                  final replaceText = replaceCtrl.text;
                  if (findText.isEmpty) return;
                  _replaceCurrent(findText, replaceText, caseSensitive: caseSensitive, useRegex: useRegex);
                },
                child: const Text('替换'),
              ),
              FilledButton(
                onPressed: () {
                  final findText = findCtrl.text;
                  final replaceText = replaceCtrl.text;
                  if (findText.isEmpty) return;
                  final count = _replaceAll(findText, replaceText, caseSensitive: caseSensitive, useRegex: useRegex);
                  if (mounted) _showToast('已替换 $count 处');
                },
                child: const Text('全部替换'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  int _findNext(String findText, {bool caseSensitive = false, bool useRegex = false}) {
    final text = _contentCtrl.text;
    final sel = _contentCtrl.selection;
    int startOffset = sel.isValid ? sel.end : 0;

    try {
      RegExp pattern;
      if (useRegex) {
        pattern = RegExp(findText, caseSensitive: caseSensitive ? false : true, multiLine: true);
      } else {
        pattern = RegExp(RegExp.escape(findText), caseSensitive: caseSensitive ? false : true);
      }

      final match = pattern.firstMatch(text, startOffset > 0 ? startOffset : 0);
      if (match != null) {
        _contentCtrl.selection = TextSelection(baseOffset: match.start, extentOffset: match.end);
        _contentFocus.requestFocus();
        if (mounted) {
          _contentCtrl.value = _contentCtrl.value.copyWith(
            selection: TextSelection(baseOffset: match.start, extentOffset: match.end),
          );
        }
        return match.start;
      } else {
        // 从头开始搜索
        final match2 = pattern.firstMatch(text, 0);
        if (match2 != null) {
          _contentCtrl.selection = TextSelection(baseOffset: match2.start, extentOffset: match2.end);
          _contentFocus.requestFocus();
          if (mounted) {
            _contentCtrl.value = _contentCtrl.value.copyWith(
              selection: TextSelection(baseOffset: match2.start, extentOffset: match2.end),
            );
          }
          return match2.start;
        }
        if (mounted) _showToast('未找到匹配项');
      }
    } catch (e) {
      if (mounted) _showToast('搜索出错: $e');
    }
    return -1;
  }

  void _replaceCurrent(String findText, String replaceText, {bool caseSensitive = false, bool useRegex = false}) {
    final text = _contentCtrl.text;
    final sel = _contentCtrl.selection;
    if (!sel.isValid || sel.start == sel.end) {
      _findNext(findText, caseSensitive: caseSensitive, useRegex: useRegex);
      return;
    }

    final selected = text.substring(sel.start, sel.end);
    try {
      RegExp pattern;
      if (useRegex) {
        pattern = RegExp(findText, caseSensitive: caseSensitive ? false : true);
      } else {
        pattern = RegExp(RegExp.escape(findText), caseSensitive: caseSensitive ? false : true);
      }

      if (pattern.hasMatch(selected)) {
        final replaced = selected.replaceAll(pattern, replaceText);
        _contentCtrl.value = TextEditingValue(
          text: text.replaceRange(sel.start, sel.end, replaced),
          selection: TextSelection.collapsed(offset: sel.start + replaced.length),
        );
        _contentFocus.requestFocus();
        _onContentChanged();
      } else {
        _findNext(findText, caseSensitive: caseSensitive, useRegex: useRegex);
      }
    } catch (e) {
      if (mounted) _showToast('替换出错: $e');
    }
  }

  int _replaceAll(String findText, String replaceText, {bool caseSensitive = false, bool useRegex = false}) {
    final text = _contentCtrl.text;
    try {
      RegExp pattern;
      if (useRegex) {
        pattern = RegExp(findText, caseSensitive: caseSensitive ? false : true, multiLine: true);
      } else {
        pattern = RegExp(RegExp.escape(findText), caseSensitive: caseSensitive ? false : true);
      }

      int count = 0;
      final replaced = text.replaceAllMapped(pattern, (m) {
        count++;
        return replaceText;
      });
      _contentCtrl.text = replaced;
      _contentCtrl.selection = TextSelection.collapsed(offset: 0);
      _onContentChanged();
      return count;
    } catch (e) {
      if (mounted) _showToast('替换出错: $e');
      return 0;
    }
  }

  // ============================================================
  // [toc] 自动生成
  // ============================================================

  void _insertToc() {
    final text = _contentCtrl.text;
    final lines = text.split('\n');
    final tocBuf = StringBuffer();
    tocBuf.writeln('<!-- TOC -->');
    tocBuf.writeln();

    final headingPattern = RegExp(r'^(#{1,6})\s+(.+)$');
    for (final line in lines) {
      final match = headingPattern.firstMatch(line.trim());
      if (match != null) {
        final level = match.group(1)!.length;
        final title = match.group(2)!.trim();
        final anchor = title
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s\u4e00-\u9fff-]'), '')
            .replaceAll(RegExp(r'\s+'), '-')
            .replaceAll(RegExp(r'-+'), '-')
            .replaceAll(RegExp(r'^-|-$'), '');
        final indent = '  ' * (level - 1);
        tocBuf.writeln('$indent- [$title](#$anchor)');
      }
    }

    tocBuf.writeln();
    tocBuf.writeln('<!-- /TOC -->');

    final toc = tocBuf.toString();

    // 检查是否有 [toc] 占位符
    final tocPlaceholder = RegExp(r'\[toc\]', caseSensitive: false);
    final placeholderMatch = tocPlaceholder.firstMatch(text);
    if (placeholderMatch != null) {
      _contentCtrl.value = TextEditingValue(
        text: text.replaceRange(placeholderMatch.start, placeholderMatch.end, toc),
        selection: TextSelection.collapsed(offset: placeholderMatch.start + toc.length),
      );
    } else {
      // 插入到光标位置
      final sel = _contentCtrl.selection;
      final pos = sel.isValid ? sel.start : text.length;
      _contentCtrl.value = TextEditingValue(
        text: text.replaceRange(pos, pos, '\n$toc\n'),
        selection: TextSelection.collapsed(offset: pos + toc.length + 2),
      );
    }
    _contentFocus.requestFocus();
    _onContentChanged();
    if (mounted) _showToast('TOC 已生成');
  }

  // ============================================================
  // 图片路径管理
  // ============================================================

  void _toggleImagePathMode() {
    final siteUrl = activeRepo?.siteUrl ?? '';
    if (siteUrl.isEmpty) {
      if (mounted) _showToast('请先配置站点 URL');
      return;
    }

    final text = _contentCtrl.text;
    // 规范化 siteUrl（去掉末尾斜杠）
    final baseUrl = siteUrl.endsWith('/') ? siteUrl.substring(0, siteUrl.length - 1) : siteUrl;
    final imagePattern = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');

    if (!_useRelativeImagePath) {
      // 转换为相对路径：https://site.com/images/photo.png → images/photo.png
      final escapedBase = RegExp.escape(baseUrl);
      final replaced = text.replaceAllMapped(imagePattern, (m) {
        final alt = m.group(1) ?? '';
        var url = m.group(2) ?? '';
        if (url.startsWith(baseUrl)) {
          url = url.substring(baseUrl.length);
          if (url.startsWith('/')) url = url.substring(1);
        }
        return '![$alt]($url)';
      });
      _contentCtrl.text = replaced;
      if (mounted) {
        setState(() => _useRelativeImagePath = true);
        _showToast('已切换为相对路径模式');
      }
    } else {
      // 转换为绝对路径：images/photo.png → https://site.com/images/photo.png
      final replaced = text.replaceAllMapped(imagePattern, (m) {
        final alt = m.group(1) ?? '';
        var url = m.group(2) ?? '';
        // 只转换相对路径或本地路径
        if (!url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('//')) {
          // 处理 ./ ../ 等相对路径
          url = url.replaceAll(RegExp(r'^\./'), '');
          url = url.replaceAll(RegExp(r'^(\.\./)+'), '');
          if (!url.startsWith('/')) url = '/$url';
          return '![$alt]($baseUrl$url)';
        }
        return m.group(0)!;
      });
      _contentCtrl.text = replaced;
      if (mounted) {
        setState(() => _useRelativeImagePath = false);
        _showToast('已切换为绝对路径模式');
      }
    }
    _onContentChanged();
  }

  // ============================================================
  // 图片尺寸快捷设置
  // ============================================================

  void _setImageSize(String size) {
    final text = _contentCtrl.text;
    final sel = _contentCtrl.selection;
    final pos = sel.isValid ? sel.start : text.length;

    // 检查光标是否在图片语法附近
    String width;
    switch (size) {
      case 'small':  width = '200'; break;
      case 'medium': width = '400'; break;
      case 'large':  width = '600'; break;
      case 'full':   width = '100%'; break;
      default:       width = '400';
    }

    // 查找光标附近的图片语法
    final beforeText = text.substring(0, pos);
    final imageMatch = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)', multiLine: true);
    final matches = imageMatch.allMatches(beforeText);
    int? lastEnd;
    String? lastUrl;
    for (final m in matches) {
      if (m.end <= pos) {
        lastEnd = m.end;
        lastUrl = m.group(2);
      }
    }

    if (lastEnd != null && lastUrl != null) {
      // 在图片 URL 后面插入尺寸标记
      final sizeStr = ' =${width}x';
      // 使用 HTML img 标签风格
      final htmlImg = '<img src="$lastUrl" width="$width"/>';
      // 检查是否已经是 HTML 格式
      final beforeMarkdown = text.substring(0, lastEnd);
      final mdMatch = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)$', multiLine: true);
      final mdLastMatch = mdMatch.firstMatch(beforeMarkdown);
      if (mdLastMatch != null) {
        final alt = mdLastMatch.group(1) ?? '';
        final url = mdLastMatch.group(2) ?? '';
        _contentCtrl.value = TextEditingValue(
          text: text.replaceRange(mdLastMatch.start, mdLastMatch.end, '<img src="$url" alt="$alt" width="$width"/>'),
          selection: TextSelection.collapsed(offset: mdLastMatch.start + '<img src="$url" alt="$alt" width="$width"/>'.length),
        );
      }
    } else {
      // 没有找到图片，直接插入 HTML 模板
      _insertText('<img src="url" width="$width" alt=""/>');
    }
    _contentFocus.requestFocus();
    _onContentChanged();
  }

  // ============================================================
  // 可视化表格编辑
  // ============================================================

  void _insertTable() {
    const table = '| 列1 | 列2 | 列3 |\n'
        '| --- | --- | --- |\n'
        '| 内容 | 内容 | 内容 |\n'
        '| 内容 | 内容 | 内容 |\n'
        '| 内容 | 内容 | 内容 |\n';
    _insertText('\n$table\n');
    if (mounted) _showToast('表格已插入');
  }

  void _addTableRow() {
    final text = _contentCtrl.text;
    final sel = _contentCtrl.selection;
    final pos = sel.isValid ? sel.start : text.length;

    // 找到光标所在行
    final before = text.substring(0, pos);
    final after = text.substring(pos);
    final lineStart = before.lastIndexOf('\n') + 1;
    final lineEnd = after.indexOf('\n');
    final currentLine = lineEnd >= 0
        ? text.substring(lineStart, pos + lineEnd)
        : text.substring(lineStart);

    // 检测是否在表格中
    if (!currentLine.trimLeft().startsWith('|')) {
      if (mounted) _showToast('光标不在表格中');
      return;
    }

    // 分析表格列数
    final cols = '|'.allMatches(currentLine).length - 1;
    if (cols <= 0) {
      if (mounted) _showToast('未检测到有效表格');
      return;
    }

    // 构建新行
    final newRow = '| ${List.filled(cols, '内容').join(' | ')} |\n';

    // 找到当前行结束位置
    final rowEnd = lineEnd >= 0 ? lineStart + lineEnd : text.length;
    // 找到下一行开始
    final nextLineStart = rowEnd < text.length ? rowEnd + 1 : text.length;

    _contentCtrl.value = TextEditingValue(
      text: text.replaceRange(nextLineStart, nextLineStart, newRow),
      selection: TextSelection.collapsed(offset: nextLineStart + newRow.length),
    );
    _contentFocus.requestFocus();
    _onContentChanged();
    if (mounted) _showToast('已添加表格行');
  }

  void _addTableCol() {
    final text = _contentCtrl.text;
    final sel = _contentCtrl.selection;
    final pos = sel.isValid ? sel.start : text.length;

    // 找到光标所在行
    final before = text.substring(0, pos);
    final after = text.substring(pos);
    final lineStart = before.lastIndexOf('\n') + 1;
    final lineEnd = after.indexOf('\n');
    final currentLine = lineEnd >= 0
        ? text.substring(lineStart, pos + lineEnd)
        : text.substring(lineStart);

    if (!currentLine.trimLeft().startsWith('|')) {
      if (mounted) _showToast('光标不在表格中');
      return;
    }

    // 找到表格块
    int tableStart = lineStart;
    while (tableStart > 0) {
      final prevLineStart = text.lastIndexOf('\n', tableStart - 2) + 1;
      final prevLineEnd = text.indexOf('\n', tableStart) >= 0 ? text.indexOf('\n', tableStart) : text.length;
      final prevLine = text.substring(prevLineStart, prevLineEnd);
      if (!prevLine.trimLeft().startsWith('|')) break;
      tableStart = prevLineStart;
    }

    int tableEnd = lineStart + (lineEnd >= 0 ? lineEnd : (text.length - lineStart));
    while (tableEnd < text.length) {
      final nextLineStart = tableEnd + 1;
      final nextLineEnd = text.indexOf('\n', nextLineStart);
      final nextLine = nextLineEnd >= 0
          ? text.substring(nextLineStart, nextLineEnd)
          : text.substring(nextLineStart);
      if (!nextLine.trimLeft().startsWith('|')) break;
      tableEnd = nextLineEnd >= 0 ? nextLineEnd : text.length;
    }

    // 提取表格所有行
    final tableText = tableEnd < text.length
        ? text.substring(tableStart, tableEnd)
        : text.substring(tableStart);
    final tableLines = tableText.split('\n');
    final buf = StringBuffer();
    for (int i = 0; i < tableLines.length; i++) {
      final line = tableLines[i].trimRight();
      if (line.trimLeft().startsWith('|')) {
        // 判断是否是分隔行
        if (RegExp(r'^\|[\s\-:]+\|').hasMatch(line.trimLeft())) {
          buf.writeln('${line} --- |');
        } else {
          buf.writeln('$line 内容 |');
        }
      } else {
        buf.writeln(line);
      }
    }

    final newTable = buf.toString();
    final end = tableEnd < text.length ? tableEnd + 1 : text.length;
    _contentCtrl.value = TextEditingValue(
      text: text.replaceRange(tableStart, end > text.length ? text.length : end, newTable),
      selection: TextSelection.collapsed(offset: tableStart + newTable.length),
    );
    _contentFocus.requestFocus();
    _onContentChanged();
    if (mounted) _showToast('已添加表格列');
  }

  // ============================================================
  // 全文格式化
  // ============================================================

  void _formatDocument() {
    try {
      final lines = _contentCtrl.text.split('\n');
      final result = <String>[];
      int emptyLineCount = 0;
      int prevHeadingLevel = 0;

      for (int i = 0; i < lines.length; i++) {
        var line = lines[i];

        // 去除行尾空白
        line = line.trimRight();

        // 处理空行
        if (line.trim().isEmpty) {
          emptyLineCount++;
          if (emptyLineCount <= 2) {
            result.add(line);
          }
          // 超过 2 个连续空行则跳过
          continue;
        }
        emptyLineCount = 0;

        // 检测标题
        final headingMatch = RegExp(r'^(#{1,6})\s').firstMatch(line);
        if (headingMatch != null) {
          final level = headingMatch.group(1)!.length;

          // 确保标题前有空行（除非是文档开头）
          if (result.isNotEmpty && result.last.trim().isNotEmpty) {
            result.add('');
          }

          // 规范化标题级别：不允许跳级
          if (prevHeadingLevel > 0 && level > prevHeadingLevel + 1) {
            // 调整标题级别
            final newLevel = prevHeadingLevel + 1;
            line = '${'#' * newLevel}${line.substring(level)}';
          }
          prevHeadingLevel = headingMatch.group(1)!.length;
          result.add(line);

          // 确保标题后有空行
          if (i + 1 < lines.length && lines[i + 1].trim().isNotEmpty) {
            result.add('');
          }
        } else {
          result.add(line);
        }
      }

      // 去除末尾多余空行
      while (result.isNotEmpty && result.last.trim().isEmpty) {
        result.removeLast();
      }

      _contentCtrl.text = '${result.join('\n')}\n';
      _onContentChanged();
      if (mounted) _showToast('文档格式化完成');
    } catch (e) {
      if (mounted) _showToast('格式化出错: $e');
    }
  }

  // ============================================================
  // 发布路径修复
  // ============================================================

  void _repairPublishPaths() {
    final siteUrl = activeRepo?.siteUrl ?? '';
    if (siteUrl.isEmpty) {
      if (mounted) _showToast('请先配置站点 URL');
      return;
    }

    final baseUrl = siteUrl.endsWith('/') ? siteUrl.substring(0, siteUrl.length - 1) : siteUrl;
    final text = _contentCtrl.text;
    int fixedCount = 0;

    // 匹配图片语法
    final imagePattern = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');
    final replaced = text.replaceAllMapped(imagePattern, (m) {
      final alt = m.group(1) ?? '';
      var url = m.group(2) ?? '';

      // 如果已经是绝对 URL，跳过
      if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('//')) {
        return m.group(0)!;
      }

      // 处理相对路径
      var cleaned = url
          .replaceAll(RegExp(r'^\./'), '')
          .replaceAll(RegExp(r'^(\.\./)+'), '');
      if (!cleaned.startsWith('/')) cleaned = '/$cleaned';
      fixedCount++;
      return '![$alt]($baseUrl$cleaned)';
    });

    if (fixedCount > 0) {
      _contentCtrl.text = replaced;
      _onContentChanged();
      if (mounted) _showToast('已修复 $fixedCount 个图片路径');
    } else {
      if (mounted) _showToast('未发现需要修复的本地路径');
    }
  }

  // ============================================================
  // 批量操作
  // ============================================================

  void _showBatchOperations() {
    if (drafts.isEmpty) {
      if (mounted) _showToast('没有可用的草稿');
      return;
    }

    final selected = <String, bool>{};
    for (final d in drafts) {
      selected[d.id] = false;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final selectedIds = selected.entries.where((e) => e.value).map((e) => e.key).toList();
          return AlertDialog(
            title: const Text('批量操作'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          final allSelected = selected.values.every((v) => v);
                          for (final k in selected.keys) {
                            selected[k] = !allSelected;
                          }
                          setDialogState(() {});
                        },
                        child: Text(selected.values.every((v) => v) ? '取消全选' : '全选'),
                      ),
                      const Spacer(),
                      Text('已选: ${selectedIds.length} / ${drafts.length}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: drafts.length,
                      itemBuilder: (_, i) {
                        final d = drafts[i];
                        return CheckboxListTile(
                          dense: true,
                          value: selected[d.id] ?? false,
                          onChanged: (v) {
                            selected[d.id] = v ?? false;
                            setDialogState(() {});
                          },
                          title: Text(
                            d.title.isNotEmpty ? d.title : '未命名',
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            d.updatedAt.toString().substring(0, 16),
                            style: const TextStyle(fontSize: 11),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: selectedIds.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _batchExportMd(selectedIds);
                      },
                child: const Text('批量导出 MD'),
              ),
              TextButton(
                onPressed: selectedIds.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _batchFormat(selectedIds);
                      },
                child: const Text('批量格式化'),
              ),
              FilledButton(
                onPressed: selectedIds.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _batchPublish(selectedIds);
                      },
                child: const Text('批量发布'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _batchExportMd(List<String> articleIds) async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择导出目录');
      if (result == null) return;

      int exported = 0;
      for (final id in articleIds) {
        final article = drafts.firstWhere((a) => a.id == id, orElse: () => Article(
          id: '', title: '', content: '', createdAt: DateTime.now(), updatedAt: DateTime.now(), isDraft: true,
        ));
        if (article.id.isEmpty) continue;

        final safeTitle = (article.title.isNotEmpty ? article.title : 'untitled')
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final fileName = '$safeTitle.md';
        final file = File('$result/$fileName');
        await file.writeAsString(article.toMarkdownWithFrontMatter());
        exported++;
      }
      if (mounted) _showToast('已导出 $exported 篇草稿');
    } catch (e) {
      if (mounted) _showToast('导出失败: $e');
    }
  }

  Future<void> _batchFormat(List<String> articleIds) async {
    try {
      int formatted = 0;
      for (final id in articleIds) {
        final article = drafts.firstWhere((a) => a.id == id, orElse: () => Article(
          id: '', title: '', content: '', createdAt: DateTime.now(), updatedAt: DateTime.now(), isDraft: true,
        ));
        if (article.id.isEmpty) continue;

        // 格式化文章内容
        final lines = article.content.split('\n');
        final result = <String>[];
        int emptyLineCount = 0;
        for (final line in lines) {
          final trimmed = line.trimRight();
          if (trimmed.isEmpty) {
            emptyLineCount++;
            if (emptyLineCount <= 2) result.add(trimmed);
            continue;
          }
          emptyLineCount = 0;

          final headingMatch = RegExp(r'^(#{1,6})\s').firstMatch(trimmed);
          if (headingMatch != null) {
            if (result.isNotEmpty && result.last.trim().isNotEmpty) result.add('');
            result.add(trimmed);
          } else {
            result.add(trimmed);
          }
        }
        while (result.isNotEmpty && result.last.trim().isEmpty) {
          result.removeLast();
        }

        final formattedContent = '${result.join('\n')}\n';
        final updated = article.copyWith(content: formattedContent, updatedAt: DateTime.now());
        final idx = drafts.indexWhere((a) => a.id == id);
        if (idx >= 0) drafts[idx] = updated;
        formatted++;
      }
      await storage.saveDrafts(drafts);
      if (mounted) {
        setState(() {});
        _showToast('已格式化 $formatted 篇草稿');
      }
    } catch (e) {
      if (mounted) _showToast('批量格式化失败: $e');
    }
  }

  Future<void> _batchPublish(List<String> articleIds) async {
    final repo = _resolvedRepo;
    if (repo == null || repo.token.isEmpty) {
      if (mounted) _showToast('请先配置仓库与 Token');
      return;
    }

    setState(() { _editorBusy = true; _editorStatus = '正在批量发布...'; });
    int published = 0;
    int failed = 0;

    try {
      for (final id in articleIds) {
        final article = drafts.firstWhere((a) => a.id == id, orElse: () => Article(
          id: '', title: '', content: '', createdAt: DateTime.now(), updatedAt: DateTime.now(), isDraft: true,
        ));
        if (article.id.isEmpty) continue;

        final pubArticle = article.copyWith(isDraft: false, published: true);
        try {
          final pub = await github.upsertArticle(repo, pubArticle);
          final idx = drafts.indexWhere((a) => a.id == id);
          if (idx >= 0) drafts[idx] = pub.copyWith(isDraft: false, published: true);
          published++;
        } catch (_) {
          failed++;
        }
      }
      await storage.saveDrafts(drafts);
      if (mounted) {
        setState(() { _editorBusy = false; _editorStatus = null; });
        _showToast('批量发布完成: $published 成功, $failed 失败');
      }
    } catch (e) {
      if (mounted) {
        setState(() { _editorBusy = false; _editorStatus = null; });
        _showToast('批量发布出错: $e');
      }
    }
  }

  // ============================================================
  // 导航方法 - 复刻手机版全部功能入口
  // ============================================================

  void _openDrafts() {
    _openTab('drafts', '草稿箱', Icons.drafts_outlined, DraftsScreen(
      drafts: drafts,
      repos: repos,
      blogSiteConfigs: settings.blogSiteConfigs,
      onOpen: (a) => _openExistingArticle(a),
      onDelete: _deleteDraft,
    ));
  }

  void _openRemote() {
    if (siteManager.isDynamicSite) {
      final adapter = siteManager.currentAdapter;
      if (adapter == null) {
        _showToast('未配置 CMS 站点');
        return;
      }
      _openTab('remote_posts', '远程文章', Icons.cloud_outlined, RemotePostsScreen(
        adapter: adapter,
        logService: logService,
        onOpenInEditor: (post) {
          // 打开远程文章到编辑器
          _openExistingArticle(Article(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: post.title, content: post.contentMd ?? '',
            tags: post.tags, categories: post.categories,
            createdAt: post.date ?? DateTime.now(), updatedAt: DateTime.now(),
            isDraft: true, remoteSha: post.id?.toString(),
          ));
        },
        onDeletePost: (post) async {
          try { await adapter.deletePost(post.id!); _showToast('已删除'); } catch (e) { _showToast('删除失败: $e'); }
        },
      ));
    } else {
      _openTab('remote', '远程文章', Icons.cloud_outlined, RemoteScreen(
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
          } catch (e) { _showToast('打开失败: $e'); }
        },
        onDelete: (item) async {
          try {
            final repo = effectiveRepo;
            if (repo != null) { await github.deleteFile(repo, item.path, item.sha); _refreshRemote(); _showToast('已删除'); }
          } catch (e) { _showToast('删除失败: $e'); }
        },
        onBatchDelete: (items) async {},
        onRollback: (item) async {},
      ));
    }
  }

  void _openSyncStatus() {
    final adapter = siteManager.currentAdapter;
    final config = adapter?.config;
    if (adapter != null && config != null) {
      _openTab('sync', '同步状态', Icons.sync, SyncScreen(
        adapter: adapter,
        siteConfig: config,
        syncService: syncService,
        logService: logService,
        localArticles: drafts,
        onOpenArticle: _openExistingArticle,
        onOpenRemotePost: (post) {
          _openExistingArticle(Article(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: post.title, content: post.contentMd,
            tags: post.tags, categories: post.categories,
            createdAt: post.date, updatedAt: post.modifiedDate,
            isDraft: false, published: true, articleType: 'post',
            remotePath: post.link, remoteSha: post.id?.toString(),
          ));
        },
      ));
    } else {
      _showToast('请先在"动态博客登录"中配置 CMS 站点');
    }
  }

  void _openDashboard() {
    _openTab('dashboard', '仪表盘', Icons.dashboard_outlined, DashboardScreen(
      drafts: drafts,
      remotePosts: remotePosts,
      commits: commits,
      settings: settings,
      activeRepo: activeRepo,
      onNewPost: _newArticle,
      onNavigateToRemote: _openRemote,
      onNavigateToHistory: _openHistory,
      onNavigateToSettings: _openSettings,
      onNavigateToPreview: _openPreview,
      onNavigateToDrafts: _openDrafts,
    ));
  }

  void _openHistory() {
    _openTab('history', '提交历史', Icons.history_outlined, HistoryScreen(
      commits: commits,
      github: github,
      effectiveRepo: effectiveRepo,
      onRefresh: _refreshCommits,
      onCommitTap: (commit) {},
    ));
  }

  void _openRss() {
    _openTab('rss', 'RSS 订阅', Icons.rss_feed_outlined, RssScreen(
      items: rssItems,
      activeRepo: activeRepo,
      onRefresh: _refreshRss,
    ));
  }

  void _openBatchUpload() {
    _openTab('batch_upload', '批量上传', Icons.drive_folder_upload, FolderUploadScreen(
      repos: repos,
      github: github,
      activeRepo: effectiveRepo,
    ));
  }

  void _openPreview() {
    _openTab('preview', '网站预览', Icons.language, PreviewScreen(
      activeRepo: activeRepo,
    ));
  }

  void _openSettings() {
    _openTab('settings', '设置', Icons.settings_outlined, SettingsScreen(
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
      onShowGithubTokenManager: _showGithubTokenManager,
      onShowRepoManager: _showRepoManager,
      onShowSiteEditor: _showSiteEditor,
      onShowThemeColorPicker: _showThemeColorPicker,
      onShowPwaGuide: () {},
      onPersistSettings: _persistSettings,
      onShowToast: _showToast,
      onShowBlogSiteManager: _showBlogSiteManager,
    ));
  }

  void _openSyncSettings() {
    _openTab('sync_settings', '云同步', Icons.cloud_sync, SyncSettingsScreen(
      cloudSyncService: cloudSyncService,
      logService: logService,
      settings: settings,
      repos: repos,
      onSettingsChanged: _updateSettings,
      onPushAll: _pushAllToCloud,
      onPullAll: _pullAllFromCloud,
    ));
  }

  void _openLogs() {
    _openTab('logs', '操作日志', Icons.history, LogScreen(logService: logService));
  }

  void _openThemeMigration() {
    _openTab('theme_migration', 'AI 主题迁移', Icons.auto_fix_high, ThemeMigrationScreen(
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
    ));
  }

  void _openRecycleBin() {
    _openTab('recycle_bin', '回收站', Icons.delete_outline, RecycleBinScreen(
      recycleBinService: recycleBinService,
      onRestored: (path) {
        _showToast('已恢复: $path');
      },
    ));
  }

  void _openImageBedManager() {
    _openTab('image_bed', '图床管理', Icons.photo_library_outlined, ImageBedScreen(
      settings: settings,
      githubService: github,
      imageService: imageService,
      allArticles: drafts,
      onUrlReplaced: (oldUrl, newUrl) {
        // 批量替换所有文章中的图片URL
        for (int i = 0; i < drafts.length; i++) {
          final a = drafts[i];
          if (a.content.contains(oldUrl)) {
            drafts[i] = a.copyWith(content: a.content.replaceAll(oldUrl, newUrl));
          }
        }
        storage.saveDrafts(drafts);
        // 如果当前文章也受影响，更新编辑器
        if (_currentArticle.content.contains(oldUrl)) {
          _contentCtrl.text = _currentArticle.content.replaceAll(oldUrl, newUrl);
          setState(() {});
        }
        _showToast('图片URL批量替换完成');
      },
    ));
  }

  void _openVersionHistory() {
    final articleId = _currentArticle.id;
    final articleTitle = _currentArticle.title;
    showDialog(
      context: context,
      builder: (ctx) => _VersionHistoryDialog(
        articleId: articleId,
        articleTitle: articleTitle,
        versionSnapshotService: versionSnapshotService,
        onRestore: (content) {
          _contentCtrl.text = content;
          _hasUnsavedChanges = true;
          setState(() => _editorStatus = '已恢复历史版本');
          _showToast('已恢复历史版本，请保存');
        },
      ),
    );
  }

  // ── 同步冲突解决 ──

  /// 显示同步冲突解决对话框
  /// [conflicts] 冲突列表，每个条目包含本地和远程内容
  void _showConflictResolution(List<SyncEntry> conflicts) {
    showDialog(
      context: context,
      builder: (ctx) => _ConflictResolutionDialog(
        conflicts: conflicts,
        drafts: drafts,
        syncService: syncService,
        siteManager: siteManager,
        onResolved: (resolutions) {
          Navigator.pop(ctx);
          _applyConflictResolutions(resolutions);
        },
      ),
    );
  }

  /// 冲突解决后应用结果
  void _applyConflictResolutions(Map<String, String> resolutions) {
    // resolutions: key=articleId, value="local"/"remote"/"merge"
    for (final entry in resolutions.entries) {
      final articleId = entry.key;
      final strategy = entry.value;
      if (strategy == 'local') {
        // 保留本地版本，标记为需要推送
        _showToast('已保留本地版本: ${drafts.firstWhere((a) => a.id == articleId, orElse: () => _currentArticle).title}');
      } else if (strategy == 'remote') {
        // 使用远程版本覆盖本地
        _showToast('已使用远程版本覆盖本地');
      }
    }
    storage.saveDrafts(drafts);
    _showToast('冲突已解决，可重新同步');
  }

  /// 检查并处理同步冲突
  Future<bool> _checkAndResolveConflicts() async {
    if (!siteManager.isDynamicSite) return true;
    final adapter = siteManager.currentAdapter;
    if (adapter == null) return true;

    try {
      final siteConfig = siteManager.currentSiteConfig;
      if (siteConfig == null) return true;
      final entries = await syncService.compareSync(siteConfig, adapter, drafts);
      final conflicts = entries.where((e) => e.hasConflict).toList();
      if (conflicts.isNotEmpty) {
        _showConflictResolution(conflicts);
        return false;
      }
    } catch (_) {
      // 无法检测冲突，允许继续
    }
    return true;
  }

  /// 生成简单 diff 文本（逐行对比两个字符串）
  List<_DiffLine> _computeDiff(String oldText, String newText) {
    final result = <_DiffLine>[];
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');

    // 逐行 LCS diff
    final lcs = _lcsMatrix(oldLines, newLines);
    int i = oldLines.length, j = newLines.length;
    final reversed = <_DiffLine>[];

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1]) {
        reversed.add(_DiffLine(type: _DiffType.equal, text: oldLines[i - 1], lineNum: i));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j])) {
        reversed.add(_DiffLine(type: _DiffType.added, text: newLines[j - 1], lineNum: j));
        j--;
      } else if (i > 0) {
        reversed.add(_DiffLine(type: _DiffType.removed, text: oldLines[i - 1], lineNum: i));
        i--;
      }
    }
    result.addAll(reversed.reversed);
    return result;
  }

  List<List<int>> _lcsMatrix(List<String> a, List<String> b) {
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }
    return dp;
  }

  void _openProxySettings() {
    final hostCtrl = TextEditingController(text: settings.proxyHost);
    final portCtrl = TextEditingController(text: settings.proxyPort.toString());
    final userCtrl = TextEditingController(text: settings.proxyUsername);
    final passCtrl = TextEditingController(text: settings.proxyPassword);
    bool enabled = settings.proxyEnabled;
    bool applyToAi = settings.proxyApplyToAi;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.vpn_lock_outlined, size: 22),
            SizedBox(width: 8),
            Text('网络代理设置', style: TextStyle(fontSize: 17)),
          ]),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('启用代理', style: TextStyle(fontSize: 14)),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
                  contentPadding: EdgeInsets.zero,
                ),
                TextField(
                  controller: hostCtrl,
                  decoration: const InputDecoration(labelText: '代理主机', hintText: '127.0.0.1', isDense: true),
                  enabled: enabled,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portCtrl,
                  decoration: const InputDecoration(labelText: '端口', hintText: '1080', isDense: true),
                  keyboardType: TextInputType.number,
                  enabled: enabled,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: '用户名 (可选)', isDense: true),
                  enabled: enabled,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(labelText: '密码 (可选)', isDense: true),
                  obscureText: true,
                  enabled: enabled,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('对 AI 接口也启用代理', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('国内网络访问 OpenAI 等 API 需要代理', style: TextStyle(fontSize: 11)),
                  value: applyToAi,
                  onChanged: enabled ? (v) => setDialogState(() => applyToAi = v) : null,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final newSettings = settings.copyWith(
                  proxyEnabled: enabled,
                  proxyHost: hostCtrl.text.trim(),
                  proxyPort: int.tryParse(portCtrl.text.trim()) ?? 1080,
                  proxyUsername: userCtrl.text.trim(),
                  proxyPassword: passCtrl.text.trim(),
                  proxyApplyToAi: applyToAi,
                );
                await _updateSettings(newSettings);
                if (mounted) {
                  Navigator.pop(ctx);
                  _showToast('代理设置已保存');
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  // ── 版本历史对话框 ──

  void _openCacheCleanup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.cleaning_services_outlined, size: 22),
          SizedBox(width: 8),
          Text('缓存清理', style: TextStyle(fontSize: 17)),
        ]),
        content: const SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('此操作将清理以下缓存:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('  • 图片缓存 (image_cache)', style: TextStyle(fontSize: 13)),
              Text('  • 预览缓存 (webview_cache)', style: TextStyle(fontSize: 13)),
              Text('  • 临时文件', style: TextStyle(fontSize: 13)),
              SizedBox(height: 12),
              Text('清理后不会影响草稿和设置。', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              try {
                final rootDir = await storage.root;
                // 清理图片缓存
                final imgCache = Directory('${rootDir.path}/image_cache');
                if (await imgCache.exists()) await imgCache.delete(recursive: true);
                // 清理 WebView 缓存
                final webCache = Directory('${rootDir.path}/webview_cache');
                if (await webCache.exists()) await webCache.delete(recursive: true);
                // 清理临时文件
                final tmpDir = Directory('${rootDir.path}/tmp');
                if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
                if (mounted) {
                  Navigator.pop(ctx);
                  _showToast('缓存已清理');
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(ctx);
                  _showToast('清理失败: $e');
                }
              }
            },
            child: const Text('立即清理'),
          ),
        ],
      ),
    );
  }

  void _exportLogs() async {
    try {
      final logs = logService.logs;
      if (logs.isEmpty) {
        _showToast('暂无日志');
        return;
      }
      final logText = logs.map((l) => '[${l.timestamp}] ${l.success ? "✓" : "✗"} ${l.action}: ${l.detail}').join('\n');
      final rootDir = await storage.root;
      final logFile = File('${rootDir.path}/export_logs_${DateTime.now().millisecondsSinceEpoch}.txt');
      await logFile.writeAsString(logText);
      _showToast('日志已导出到: ${logFile.path}');
    } catch (e) {
      _showToast('日志导出失败: $e');
    }
  }

  void _fixEncoding() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'txt', 'markdown'],
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.first.path;
      if (filePath == null) return;
      final file = File(filePath);
      final rawBytes = await file.readAsBytes();

      // 尝试检测编码并转为 UTF-8
      String decoded;
      try {
        // 尝试 UTF-8
        decoded = utf8.decode(rawBytes);
      } catch (_) {
        try {
          // 尝试 GBK
          decoded = gbk.decode(rawBytes);
        } catch (_) {
          // 尝试 Latin-1
          decoded = latin1.decode(rawBytes);
        }
      }

      // 写回 UTF-8
      final backupPath = '$filePath.bak';
      await file.copy(backupPath);
      await file.writeAsString(decoded, encoding: utf8);
      _showToast('编码修复完成，已保存 UTF-8 版本\n备份文件: $backupPath');
    } catch (e) {
      _showToast('编码修复失败: $e');
    }
  }

  void _toggleOfflineMode() async {
    final newSettings = settings.copyWith(offlineMode: !settings.offlineMode);
    await _updateSettings(newSettings);
    _showToast(settings.offlineMode ? '已退出离线模式' : '已进入离线模式\n同步和 AI 功能已暂停');
  }

  void _toggleNightEyeProtection() async {
    final newSettings = settings.copyWith(nightEyeProtection: !settings.nightEyeProtection);
    await _updateSettings(newSettings);
    _showToast(settings.nightEyeProtection ? '已关闭护眼滤镜' : '已开启护眼滤镜');
  }

  void _openLinkChecker() {
    _openTab('link_checker', '链接检测', Icons.link_off, LinkCheckerScreen(
      articles: drafts,
      onOpenArticle: _openExistingArticle,
    ));
  }

  void _openBatchTools() {
    _openTab('batch_tools', '批量工具箱', Icons.build_circle, BatchToolsScreen(
      articles: drafts,
      onArticlesUpdated: (updated) {
        setState(() {
          drafts = updated;
          // 更新当前文章如果被修改
          for (final a in updated) {
            if (a.id == _currentArticle.id) {
              _currentArticle = a;
              _contentCtrl.text = a.content;
              _titleCtrl.text = a.title;
              _tagsCtrl.text = a.tags.join(', ');
              _categoriesCtrl.text = a.categories.join(', ');
              break;
            }
          }
        });
        storage.saveDrafts(drafts);
        _showToast('批量操作已完成，草稿已保存');
      },
    ));
  }

  void _openAiPromptTemplates() {
    showDialog(
      context: context,
      builder: (ctx) => AiPromptTemplatesScreen(
        onUseTemplate: (promptContent) {
          Navigator.pop(ctx);
          // 将模板内容插入 AI 聊天面板
          _openRightDrawer(RightDrawerTab.aiChat);
          // 通过延迟确保 AI 面板已打开
          Future.delayed(const Duration(milliseconds: 300), () {
            _sendToAiChat(promptContent);
          });
        },
      ),
    );
  }

  void _sendToAiChat(String prompt) {
    // 将提示词模板发送到 AI 聊天
    _aiPromptToSend = prompt;
  }

  String? _aiPromptToSend;

  // ── AI 选区处理 ──

  /// 将编辑器选中文本发送到 AI 聊天
  void _sendSelectionToAi() {
    final selection = _contentCtrl.selection;
    if (!selection.isValid || selection.start == selection.end) {
      _showToast('请先选中一段文字');
      return;
    }
    final selectedText = selection.textInside(_contentCtrl.text);
    if (selectedText.isEmpty) {
      _showToast('选中的文字为空');
      return;
    }
    _openRightDrawer(RightDrawerTab.aiChat);
    Future.delayed(const Duration(milliseconds: 300), () {
      _aiPromptToSend = '请对以下文字进行润色优化：\n\n$selectedText';
    });
    _showToast('已发送选中文字(${selectedText.length}字符)到 AI');
  }

  /// 将编辑器全文发送到 AI 聊天
  void _sendFullToAi() {
    final text = _contentCtrl.text;
    if (text.trim().isEmpty) {
      _showToast('文章内容为空');
      return;
    }
    _openRightDrawer(RightDrawerTab.aiChat);
    Future.delayed(const Duration(milliseconds: 300), () {
      _aiPromptToSend = '请对以下文章进行润色优化：\n\n$text';
    });
    _showToast('已发送全文到 AI');
  }

  // ── AI 输出对比 ──

  /// 显示 AI 修改内容 diff 预览，选择性接受改动
  void _showAiDiffPreview(String original, String modified) {
    final diffLines = _computeDiff(original, modified);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.compare_arrows, size: 22),
            SizedBox(width: 8),
            Text('AI 修改对比', style: TextStyle(fontSize: 17)),
          ]),
          content: SizedBox(
            width: 800,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildDiffLegend(),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.done_all, size: 16),
                      label: const Text('全部接受'),
                      onPressed: () {
                        _contentCtrl.text = modified;
                        _hasUnsavedChanges = true;
                        setState(() => _editorStatus = '已接受AI修改');
                        Navigator.pop(ctx);
                        _showToast('已全部接受AI修改');
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('全部拒绝'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showToast('已拒绝AI修改');
                      },
                    ),
                  ],
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: diffLines.length,
                    itemBuilder: (_, i) {
                      final line = diffLines[i];
                      Color bgColor;
                      Color textColor;
                      IconData? icon;
                      switch (line.type) {
                        case _DiffType.added:
                          bgColor = Colors.green.withOpacity(0.1);
                          textColor = Colors.green.shade700;
                          icon = Icons.add;
                          break;
                        case _DiffType.removed:
                          bgColor = Colors.red.withOpacity(0.1);
                          textColor = Colors.red.shade700;
                          icon = Icons.remove;
                          break;
                        default:
                          bgColor = Colors.transparent;
                          textColor = Colors.grey.shade700;
                          icon = null;
                      }
                      return Container(
                        color: bgColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (icon != null) Icon(icon, size: 14, color: textColor),
                            if (icon != null) const SizedBox(width: 4),
                            Text(
                              '${line.lineNum.toString().padLeft(3)}',
                              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line.text.isEmpty ? ' ' : line.text,
                                style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: textColor),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('关闭'),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('接受修改'),
                        onPressed: () {
                          _contentCtrl.text = modified;
                          _hasUnsavedChanges = true;
                          setState(() => _editorStatus = '已接受AI修改');
                          Navigator.pop(ctx);
                          _showToast('已接受AI修改，请保存');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiffLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: Colors.green.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        const Text('新增', style: TextStyle(fontSize: 11)),
        const SizedBox(width: 12),
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        const Text('删除', style: TextStyle(fontSize: 11)),
        const SizedBox(width: 12),
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        const Text('不变', style: TextStyle(fontSize: 11)),
      ],
    );
  }

  // ── 发布增强 ──

  /// 发布变更日志：对比本地与线上版本，展示改动内容
  void _showPublishChangeLog(String remoteContentParam) async {
    final localContent = _contentCtrl.text;
    var remoteContent = remoteContentParam;

    // 如果未提供远程内容，尝试从当前发布目标获取
    if (remoteContent.isEmpty && siteManager.isDynamicSite) {
      try {
        final adapter = siteManager.currentAdapter;
        if (adapter != null) {
          final mapping = syncService.findByLocalId(siteManager.currentSiteConfig?.id ?? '', _currentArticle.id);
          if (mapping != null) {
            final remotePost = await adapter.getPostById(mapping.remotePostId);
            if (remotePost != null) {
              remoteContent = remotePost.contentMd ?? '';
            }
          }
        }
      } catch (_) {
        // 无法获取远程内容
      }
    }

    if (remoteContent.isEmpty) {
      _showToast('未找到已发布的线上版本，无法对比变更');
      return;
    }

    if (remoteContent == localContent) {
      _showToast('内容无变化，无需发布');
      return;
    }
    final diffLines = _computeDiff(remoteContent, localContent);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.change_circle_outlined, size: 22),
          SizedBox(width: 8),
          Text('发布变更日志', style: TextStyle(fontSize: 17)),
        ]),
        content: SizedBox(
          width: 800,
          height: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 4),
                  const Text('新增内容', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 12),
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 4),
                  const Text('删除内容', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 12),
                  const Text('共 ${diffLines.where((l) => l.type != _DiffType.equal).length} 处变更', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: diffLines.length,
                  itemBuilder: (_, i) {
                    final line = diffLines[i];
                    Color bgColor;
                    Color textColor;
                    final prefix = line.type == _DiffType.added ? '+' : line.type == _DiffType.removed ? '-' : ' ';
                    switch (line.type) {
                      case _DiffType.added:
                        bgColor = Colors.green.withOpacity(0.08);
                        textColor = Colors.green.shade700;
                        break;
                      case _DiffType.removed:
                        bgColor = Colors.red.withOpacity(0.08);
                        textColor = Colors.red.shade600;
                        break;
                      default:
                        bgColor = Colors.transparent;
                        textColor = Colors.grey.shade500;
                    }
                    return Container(
                      color: bgColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(prefix, style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: textColor, fontWeight: FontWeight.bold)),
                          Text(
                            line.text.isEmpty ? ' ' : line.text,
                            style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: textColor),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          FilledButton.icon(
            icon: const Icon(Icons.cloud_upload_outlined, size: 16),
            label: const Text('确认发布'),
            onPressed: () {
              Navigator.pop(ctx);
              _executePublish();
            },
          ),
        ],
      ),
    );
  }

  /// 定时发布：设置延迟时间推送到 CMS
  Timer? _scheduledPublishTimer;
  DateTime? _scheduledPublishTime;

  void _schedulePublish() {
    final dateCtrl = TextEditingController();
    final timeCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.schedule_send, size: 22),
            SizedBox(width: 8),
            Text('定时发布', style: TextStyle(fontSize: 17)),
          ]),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('设置发布时间，到时自动发布到当前站点', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dateCtrl,
                        decoration: const InputDecoration(
                          labelText: '日期',
                          hintText: '2026-08-03',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: timeCtrl,
                        decoration: const InputDecoration(
                          labelText: '时间',
                          hintText: '20:00',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_scheduledPublishTime != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '已有定时发布: ${_scheduledPublishTime!.toString().substring(0, 16)}',
                            style: const TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _scheduledPublishTimer?.cancel();
                            _scheduledPublishTimer = null;
                            _scheduledPublishTime = null;
                            setDialogState(() {});
                            _showToast('已取消定时发布');
                          },
                          child: const Text('取消', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton.icon(
              icon: const Icon(Icons.schedule, size: 16),
              label: const Text('设置定时发布'),
              onPressed: () {
                final dateStr = dateCtrl.text.trim();
                final timeStr = timeCtrl.text.trim();
                if (dateStr.isEmpty || timeStr.isEmpty) {
                  _showToast('请填写日期和时间');
                  return;
                }
                final scheduledTime = DateTime.tryParse('${dateStr}T${timeStr}:00');
                if (scheduledTime == null) {
                  _showToast('日期时间格式无效');
                  return;
                }
                if (scheduledTime.isBefore(DateTime.now())) {
                  _showToast('发布时间不能早于当前时间');
                  return;
                }
                final delay = scheduledTime.difference(DateTime.now());
                _scheduledPublishTimer?.cancel();
                _scheduledPublishTimer = Timer(delay, () {
                  _scheduledPublishTime = null;
                  _scheduledPublishTimer = null;
                  if (mounted) {
                    _showToast('定时发布开始执行...');
                    _executePublish();
                  }
                });
                _scheduledPublishTime = scheduledTime;
                Navigator.pop(ctx);
                _showToast('已设置定时发布: ${scheduledTime.toString().substring(0, 16)}');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 执行发布（不显示确认对话框）
  Future<void> _executePublish() async {
    if (siteManager.isDynamicSite) {
      await _publishToCms();
    } else {
      final repo = _resolvedRepo;
      if (repo == null || repo.token.isEmpty) {
        _showToast('请先配置仓库与 Token');
        return;
      }
      setState(() { _editorBusy = true; _editorStatus = '正在发布...'; });
      try {
        final a = _collect(draft: false);
        final pub = await github.upsertArticle(repo, a);
        setState(() { _currentArticle = pub; _editorStatus = '已发布'; });
        _lastSavedContent = pub.content;
        _hasUnsavedChanges = false;
        await _saveDraft(pub.copyWith(isDraft: false, published: true));
        await _refreshRemote();
        logService.add('发布成功', '已发布到 ${repo.fullName}: ${pub.title}');
        if (mounted) _showToast('已发布到 ${repo.fullName}');
      } catch (e) {
        setState(() => _editorStatus = '发布失败');
        logService.add('发布失败', '$e', success: false);
        if (mounted) _showToast('发布失败: $e');
      } finally {
        if (mounted) setState(() => _editorBusy = false);
      }
    }
  }

  void _importHtmlFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['html', 'htm'],
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.first.path;
      if (filePath == null) return;
      final file = File(filePath);
      final html = await file.readAsString();
      final markdown = HtmlToMarkdown.convert(html);
      final fileName = result.files.first.name.replaceAll(RegExp(r'\.html?$', ignoreCase: true), '');
      final article = Article(
        id: 'import_${DateTime.now().millisecondsSinceEpoch}',
        title: fileName,
        content: markdown,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isDraft: true,
      );
      _openExistingArticle(article);
      _showToast('已导入 HTML: $fileName');
    } catch (e) {
      _showToast('导入失败: $e');
    }
  }

  void _importDocxFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.first.path;
      if (filePath == null) return;

      // DOCX 是 ZIP 格式，提取 document.xml 并转换
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      // 简单处理：读取 DOCX 中的文本
      // 实际实现需要解压 ZIP 并解析 XML
      final fileName = result.files.first.name.replaceAll('.docx', '');
      final markdown = await _extractDocxText(bytes);

      final article = Article(
        id: 'import_${DateTime.now().millisecondsSinceEpoch}',
        title: fileName,
        content: markdown,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isDraft: true,
      );
      _openExistingArticle(article);
      _showToast('已导入 DOCX: $fileName');
    } catch (e) {
      _showToast('DOCX 导入失败: $e\n请确保文件格式正确');
    }
  }

  Future<String> _extractDocxText(Uint8List bytes) async {
    // 简单文本提取：搜索 ZIP 中 document.xml 的文本内容
    // 使用正则从原始字节中提取 XML 文本节点
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      // 提取 XML 标签之间的文本
      final textRegex = RegExp(r'<w:t[^>]*>([^<]*)</w:t>');
      final matches = textRegex.allMatches(text);
      final paragraphs = <String>[];
      String currentParagraph = '';
      String? lastParaEnd;

      for (final match in matches) {
        final t = match.group(1) ?? '';
        currentParagraph += t;
        // 检查是否在段落结束附近
        final matchEnd = match.end;
        final afterMatch = text.substring(matchEnd, (matchEnd + 200) > text.length ? text.length : matchEnd + 200);
        if (afterMatch.contains('</w:p>')) {
          if (currentParagraph.trim().isNotEmpty) {
            paragraphs.add(currentParagraph.trim());
          }
          currentParagraph = '';
        }
      }
      if (currentParagraph.trim().isNotEmpty) {
        paragraphs.add(currentParagraph.trim());
      }
      return paragraphs.join('\n\n');
    } catch (_) {
      return '*无法解析 DOCX 文件内容，请尝试使用 HTML 格式导入*';
    }
  }

  void _openGlobalSearch() {
    final searchCtrl = TextEditingController();
    String query = '';
    String filterStatus = 'all'; // all, draft, published
    List<({String articleId, String title, String snippet, String matchLine, bool isDraft, DateTime createdAt})> results = [];

    void doSearch() {
      final q = query.toLowerCase();
      if (q.length < 2) {
        results = [];
        return;
      }
      results = [];
      for (final draft in drafts) {
        // 状态筛选
        if (filterStatus == 'draft' && draft.published) continue;
        if (filterStatus == 'published' && !draft.published) continue;

        final titleMatch = draft.title.toLowerCase().contains(q);
        final contentIdx = draft.content.toLowerCase().indexOf(q);
        if (titleMatch || contentIdx >= 0) {
          String snippet = '';
          String matchLine = '';
          if (contentIdx >= 0) {
            final start = contentIdx > 50 ? contentIdx - 50 : 0;
            final end = (contentIdx + q.length + 100) < draft.content.length
                ? contentIdx + q.length + 100
                : draft.content.length;
            snippet = draft.content.substring(start, end);
            matchLine = '...${snippet.replaceAll('\n', ' ')}...';
          }
          results.add((
            articleId: draft.id,
            title: draft.title.isEmpty ? '(无标题)' : draft.title,
            snippet: snippet,
            matchLine: matchLine,
            isDraft: !draft.published,
            createdAt: draft.createdAt,
          ));
        }
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.manage_search, size: 22),
            SizedBox(width: 8),
            Text('全局搜索', style: TextStyle(fontSize: 17)),
          ]),
          content: SizedBox(
            width: 620,
            height: 480,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: '搜索文章标题或正文...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: query.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    setDialogState(() { query = ''; results = []; });
                                  },
                                )
                              : null,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          setDialogState(() { query = v; doSearch(); });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 状态筛选器
                    DropdownButton<String>(
                      value: filterStatus,
                      isDense: true,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('全部', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'draft', child: Text('草稿', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'published', child: Text('已发布', style: TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) {
                        setDialogState(() { filterStatus = v ?? 'all'; doSearch(); });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (results.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${results.length} 个结果', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ),
                const SizedBox(height: 4),
                if (query.length < 2 && query.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('请输入至少2个字符进行搜索', style: TextStyle(color: Colors.grey)),
                  )
                else if (query.isNotEmpty && results.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('未找到匹配结果', style: TextStyle(color: Colors.grey)),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final r = results[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            r.isDraft ? Icons.drafts_outlined : Icons.article_outlined,
                            size: 18,
                            color: r.isDraft ? Colors.orange : Colors.green,
                          ),
                          title: Text(r.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: r.matchLine.isNotEmpty
                              ? Text(r.matchLine, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))
                              : null,
                          trailing: Text(
                            r.isDraft ? '草稿' : '已发布',
                            style: TextStyle(fontSize: 10, color: r.isDraft ? Colors.orange : Colors.green),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            final article = drafts.firstWhere((a) => a.id == r.articleId, orElse: () => _currentArticle);
                            _openExistingArticle(article);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ],
        ),
      ),
    );
  }

  void _showTemplateManager() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => TemplateManagerScreen(storage: storage, aiService: aiService, settings: settings),
    ));
    final t = await storage.loadAllTemplates();
    if (mounted) {
      var reposChanged = false;
      for (int i = 0; i < repos.length; i++) {
        final updated = TemplateResolver.ensureTemplateFallback(repos[i], t);
        if (updated != repos[i]) { repos[i] = updated; reposChanged = true; }
      }
      if (reposChanged) await _persistRepos();
      setState(() => templates = t);
    }
  }

  void _showSnippetManager() {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String category = '自定义';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('片段素材库'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                              IconButton(icon: const Icon(Icons.content_copy, size: 16), onPressed: () { _insertText(sn.content); Navigator.pop(ctx); }, constraints: const BoxConstraints(), padding: EdgeInsets.zero),
                              IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), onPressed: () async { snippets.removeAt(i); await storage.saveSnippets(snippets); setDialogState(() {}); if (mounted) setState(() => this.snippets = List.from(snippets)); }, constraints: const BoxConstraints(), padding: EdgeInsets.zero),
                            ],
                          ),
                          onTap: () { _insertText(sn.content); Navigator.pop(ctx); },
                        );
                      },
                    ),
                  ),
                  const Divider(),
                ],
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '片段名称', isDense: true)),
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
                  onChanged: (v) { if (v != null) category = v; },
                ),
                const SizedBox(height: 8),
                TextField(controller: contentCtrl, maxLines: 4, decoration: const InputDecoration(labelText: '片段内容', border: OutlineInputBorder(), isDense: true), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            FilledButton(onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final now = DateTime.now();
              snippets.add(SnippetItem(id: now.millisecondsSinceEpoch.toString(), name: nameCtrl.text.trim(), content: contentCtrl.text, category: category, createdAt: now));
              await storage.saveSnippets(snippets);
              if (mounted) setState(() => this.snippets = List.from(snippets));
              Navigator.pop(ctx);
            }, child: const Text('保存片段')),
          ],
        ),
      ),
    );
  }

  void _showConfigEditor() async {
    final repo = effectiveRepo;
    if (repo == null) { _showToast('请先配置仓库'); return; }
    try {
      final configPath = repo.frameworkId == 'hugo' ? 'config.toml' : '_config.yml';
      final result = await github.getRawFile(repo, configPath);
      String content = result?['content'] ?? '';
      String sha = result?['sha'] ?? '';
      if (!mounted) return;
      final ctrl = TextEditingController(text: content);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${repo.frameworkId} 配置编辑'),
          content: SizedBox(width: 600, height: 400, child: TextField(controller: ctrl, maxLines: null, expands: true, style: const TextStyle(fontFamily: 'monospace', fontSize: 13), decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '# 站点配置文件'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () async {
              try {
                await github.putRawFile(repo, configPath, ctrl.text, sha: sha, commitMessage: 'chore: update $configPath');
                _showToast('配置已保存');
                Navigator.pop(ctx, true);
              } catch (e) { _showToast('保存失败: $e'); }
            }, child: const Text('保存到 GitHub')),
          ],
        ),
      );
    } catch (e) { _showToast('操作失败: $e'); }
  }

  void _showSiteEditor() async {
    final repo = effectiveRepo;
    if (repo == null) { _showToast('请先配置仓库'); return; }
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => SiteEditorScreen(repo: repo, github: github, onSaved: () => _showToast('站点内容已同步到 GitHub')),
    ));
    if (mounted) setState(() {});
  }

  void _showBlogSiteManager() async {
    await Navigator.of(context).push<BlogSiteConfig?>(MaterialPageRoute(
      builder: (_) => BlogSiteEditorScreen(appSettings: settings, onSaved: _handleBlogSiteSaved),
    ));
  }

  Future<void> _handleBlogSiteSaved(BlogSiteConfig config) async {
    final existing = List<BlogSiteConfig>.from(settings.blogSiteConfigs);
    final idx = existing.indexWhere((s) => s.id == config.id);
    if (idx >= 0) { existing[idx] = config; } else { existing.add(config); }
    await _updateSettings(settings.copyWith(blogSiteConfigs: existing));
  }

  void _showAiManager() async {
    final baseUrlCtrl = TextEditingController();
    final apiKeyCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final profiles = List<AiProfile>.from(settings.aiProfiles);
          return AlertDialog(
            title: Row(children: [
              const Expanded(child: Text('AI 中转站配置', style: TextStyle(fontSize: 17))),
              TextButton.icon(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final baseUrl = baseUrlCtrl.text.trim();
                  final apiKey = apiKeyCtrl.text.trim();
                  final model = modelCtrl.text.trim();
                  if (name.isEmpty || baseUrl.isEmpty || apiKey.isEmpty) { _showToast('名称、Base URL 和 API Key 不能为空'); return; }
                  final profile = AiProfile(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, baseUrl: baseUrl, apiKey: apiKey, model: model);
                  profiles.add(profile);
                  await _updateSettings(settings.copyWith(aiProfiles: profiles, activeAiProfileId: profile.id, aiBaseUrl: baseUrl, aiApiKey: apiKey, aiModel: model, aiProvider: name));
                  nameCtrl.clear(); baseUrlCtrl.clear(); apiKeyCtrl.clear(); modelCtrl.clear();
                  setDialogState(() {});
                  _showToast('已保存 AI 配置: $name');
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新增'),
              ),
            ]),
            content: SizedBox(
              width: 550,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (profiles.isNotEmpty) ...[
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: profiles.length,
                        itemBuilder: (_, i) {
                          final p = profiles[i];
                          final isActive = settings.activeAiProfileId == p.id;
                          return ListTile(
                            dense: true,
                            leading: Icon(isActive ? Icons.check_circle : Icons.smart_toy_outlined, size: 18, color: isActive ? Theme.of(ctx).colorScheme.primary : null),
                            title: Text(p.displayLabel, style: const TextStyle(fontSize: 13)),
                            subtitle: Text('${p.baseUrl}\n模型: ${p.model.isEmpty ? "未选" : p.model}', style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isActive)
                                  TextButton(onPressed: () async { await _updateSettings(settings.copyWith(activeAiProfileId: p.id, aiBaseUrl: p.baseUrl, aiApiKey: p.apiKey, aiModel: p.model, aiProvider: p.name)); setDialogState(() {}); }, child: const Text('启用', style: TextStyle(fontSize: 11))),
                                IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), onPressed: () async { profiles.removeAt(i); await _updateSettings(settings.copyWith(aiProfiles: profiles)); setDialogState(() {}); }, constraints: const BoxConstraints(), padding: EdgeInsets.zero),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(),
                  ],
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '配置名称', isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: baseUrlCtrl, decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://api.openai.com/v1', isDense: true), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(controller: apiKeyCtrl, decoration: const InputDecoration(labelText: 'API Key', isDense: true), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: '模型名称（可选）', hintText: 'gpt-4o', isDense: true)),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
          );
        },
      ),
    );
  }

  void _showThemeColorPicker() async {
    const colors = [
      Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFF43F5E),
      Color(0xFF10B981), Color(0xFF14B8A6), Color(0xFFF59E0B), Color(0xFF64748B), Color(0xFF1E293B),
    ];
    const names = ['天蓝', '靛蓝', '紫色', '粉色', '玫瑰红', '翡翠绿', '青绿', '琥珀', '石板灰', '深灰'];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择主题颜色'),
        content: SizedBox(
          width: 300,
          child: Wrap(
            spacing: 12, runSpacing: 12,
            children: List.generate(colors.length, (i) {
              return GestureDetector(
                onTap: () async {
                  settings = settings.copyWith(themeColor: colors[i].value);
                  await _persistSettings();
                  _showToast('主题色已切换为${names[i]}');
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 48, height: 48, decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(14), border: settings.themeColor == colors[i].value ? Border.all(color: Colors.black, width: 2.5) : null)),
                    const SizedBox(height: 4),
                    Text(names[i], style: const TextStyle(fontSize: 11)),
                  ],
                ),
              );
            }),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
  }

  void _showGithubTokenManager() async {
    final tokens = List<GithubTokenProfile>.from(settings.githubTokens);
    final nameCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(children: [
            const Expanded(child: Text('GitHub 登录令牌', style: TextStyle(fontSize: 17))),
            TextButton.icon(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final token = tokenCtrl.text.trim();
                if (name.isEmpty || token.isEmpty) { _showToast('名称和令牌不能为空'); return; }
                final profile = GithubTokenProfile(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, token: token);
                tokens.add(profile);
                await _updateSettings(settings.copyWith(githubTokens: tokens, activeGithubTokenId: profile.id));
                nameCtrl.clear();
                tokenCtrl.clear();
                setDialogState(() {});
                _showToast('已添加令牌: $name');
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加'),
            ),
          ]),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tokens.isNotEmpty) ...[
                  SizedBox(
                    height: 160,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: tokens.length,
                      itemBuilder: (_, i) {
                        final t = tokens[i];
                        final isActive = settings.activeGithubTokenId == t.id;
                        return ListTile(
                          dense: true,
                          leading: Icon(isActive ? Icons.check_circle : Icons.key, size: 18, color: isActive ? Theme.of(ctx).colorScheme.primary : null),
                          title: Text(t.name, style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${t.token.substring(0, 8)}...', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isActive)
                                TextButton(onPressed: () async { await _updateSettings(settings.copyWith(activeGithubTokenId: t.id)); setDialogState(() {}); }, child: const Text('启用', style: TextStyle(fontSize: 11))),
                              IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), onPressed: () async { tokens.removeAt(i); await _updateSettings(settings.copyWith(githubTokens: tokens)); setDialogState(() {}); }, constraints: const BoxConstraints(), padding: EdgeInsets.zero),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                ],
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '令牌名称', isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: tokenCtrl, decoration: const InputDecoration(labelText: 'GitHub Token', isDense: true), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
        ),
      ),
    );
  }

  void _showRepoManager() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => SiteManagementScreen(
        siteManager: siteManager,
        repos: repos,
        onChanged: () async {
          await _updateSettings(settings);
          setState(() {});
        },
      ),
    ));
  }

  void _showWebDavDialog() async {
    final c = TextEditingController(text: settings.webdavUrl);
    final u = TextEditingController(text: settings.webdavUsername);
    final pw = TextEditingController(text: settings.webdavPassword);
    final f = TextEditingController(text: settings.webdavFolder);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WebDAV 备份'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: c, decoration: const InputDecoration(labelText: 'WebDAV 网址', hintText: 'https://dav.jianguoyun.com/dav')),
            const SizedBox(height: 12),
            TextField(controller: u, decoration: const InputDecoration(labelText: '账号')),
            const SizedBox(height: 12),
            TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: '密码')),
            const SizedBox(height: 12),
            TextField(controller: f, decoration: const InputDecoration(labelText: '文件夹')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () {
            settings = settings.copyWith(webdavUrl: c.text.trim(), webdavUsername: u.text.trim(), webdavPassword: pw.text, webdavFolder: f.text.trim().isEmpty ? 'hexo-backup' : f.text.trim());
            _persistSettings();
            Navigator.pop(ctx);
          }, child: const Text('保存')),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _syncWebDavToLocal() async {
    if (settings.webdavUrl.isEmpty) { await _showWebDavDialog(); if (mounted && settings.webdavUrl.isEmpty) return; }
    try {
      loading = true; if (mounted) setState(() {});
      final svc = WebDavService();
      final drafts = await storage.loadDrafts();
      final folder = settings.webdavFolder.endsWith('/') ? settings.webdavFolder : '${settings.webdavFolder}/';
      final remote = await svc.list(settings.webdavUrl, settings.webdavUsername, settings.webdavPassword, folder);
      final localIds = drafts.map((a) => '${a.id}.md').toSet();
      int count = 0;
      for (final item in remote) {
        if (!item.isDir && item.name.endsWith('.md') && !localIds.contains(item.name)) {
          final bytes = await svc.downloadFile(settings.webdavUrl, settings.webdavUsername, settings.webdavPassword, folder, item.name);
          final md = utf8.decode(bytes);
          final article = Article.fromMarkdown(md, id: item.name.replaceAll(RegExp(r'\.md$'), ''));
          drafts.add(article);
          count++;
        }
      }
      await storage.saveDrafts(drafts);
      if (mounted) { setState(() { loading = false; this.drafts = drafts..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); }); _showToast('已从云端同步 $count 篇草稿到本地'); }
    } catch (e) { if (mounted) { setState(() => loading = false); _showToast('WebDAV 同步失败: $e'); } }
  }

  Future<void> _syncDraftsToWebDav() async {
    if (settings.webdavUrl.isEmpty) { await _showWebDavDialog(); if (mounted && settings.webdavUrl.isEmpty) return; }
    try {
      loading = true; if (mounted) setState(() {});
      final svc = WebDavService();
      final drafts = await storage.loadDrafts();
      final folder = settings.webdavFolder.endsWith('/') ? settings.webdavFolder : '${settings.webdavFolder}/';
      await svc.createFolder(settings.webdavUrl, settings.webdavUsername, settings.webdavPassword, folder);
      final remote = await svc.list(settings.webdavUrl, settings.webdavUsername, settings.webdavPassword, folder);
      final names = remote.where((e) => e.name.endsWith('.md')).map((e) => e.name).toSet();
      int count = 0;
      for (final a in drafts) {
        if (!names.contains('${a.id}.md')) {
          await svc.putFile(settings.webdavUrl, settings.webdavUsername, settings.webdavPassword, '$folder${a.id}.md', a.toMarkdownWithFrontMatter());
          count++;
        }
      }
      if (mounted) { setState(() => loading = false); _showToast('已上传 $count 篇草稿'); }
    } catch (e) { if (mounted) { setState(() => loading = false); _showToast('WebDAV 失败: $e'); } }
  }

  // ============================================================
  // AI 功能入口
  // ============================================================

  void _showAiArticleChat() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AiArticleChatScreen(
        settings: settings, activeRepo: effectiveRepo, aiService: aiService,
        modelManager: aiModelManager, dispatcher: aiDispatcher, selfChecker: aiSelfChecker,
        isPage: false, onSettingsChanged: _updateSettings, gitHubService: github, storageService: storage,
      ),
    ));
  }

  void _showAiPageChat() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AiArticleChatScreen(
        settings: settings, activeRepo: effectiveRepo, aiService: aiService,
        modelManager: aiModelManager, dispatcher: aiDispatcher, selfChecker: aiSelfChecker,
        isPage: true, onSettingsChanged: _updateSettings, gitHubService: github, storageService: storage,
      ),
    ));
  }

  void _showAiThemeChat() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AiThemeChatScreen(
        settings: settings, activeRepo: effectiveRepo, aiService: aiService,
        modelManager: aiModelManager, dispatcher: aiDispatcher, selfChecker: aiSelfChecker,
        onSettingsChanged: _updateSettings, gitHubService: github, storageService: storage,
      ),
    ));
  }

  void _showAiAudit() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AiAuditScreen(
        settings: settings, activeRepo: effectiveRepo, aiService: aiService,
        modelManager: aiModelManager, dispatcher: aiDispatcher, selfChecker: aiSelfChecker,
        onSettingsChanged: _updateSettings, gitHubService: github, storageService: storage,
      ),
    ));
  }

  void _showAiModelManager() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AiModelManagerScreen(
        modelManager: aiModelManager, aiService: aiService, settings: settings,
        onSettingsChanged: _updateSettings,
      ),
    ));
  }

  void _showToolLibrary() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ToolLibraryScreen(skillManager: skillManager),
    ));
  }

  // ============================================================
  // 工具方法
  // ============================================================

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2),
    ));
  }

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认'), content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    return ok == true;
  }

  // ============================================================
  // 全局操作入口（由 desktop_main 快捷键/托盘/拖拽调用）
  // ============================================================

  /// GlobalKey 调用的统一入口
  void handleGlobalAction(String action) {
    switch (action) {
      case 'save':       _saveLocal(); break;
      case 'publish':    _handlePublish(); break;
      case 'new':        _newArticle(); break;
      case 'openFile':   _openFileDialog(); break;
      case 'bold':       _wrapSelection('**', '**'); break;
      case 'italic':     _wrapSelection('*', '*'); break;
      case 'strikethrough': _wrapSelection('~~', '~~'); break;
      case 'link':       _insertLink(); break;
      case 'h1':         _prefixLine('# '); break;
      case 'h2':         _prefixLine('## '); break;
      case 'h3':         _prefixLine('### '); break;
      case 'focus':      _switchWorkMode(WorkMode.focus); break;
      case 'toggleLeft': _toggleLeftPanel(); break;
      case 'preview':    _openRightDrawer(RightDrawerTab.outline); break;
      case 'pasteImage': _pasteImageFromClipboard(); break;
      case 'commandPalette': _showCommandPalette(); break;
      case 'saveAs':     _saveAsToLocal(); break;
      case 'findReplace': _showFindReplace(); break;
      case 'insertToc':  _insertToc(); break;
      case 'insertTable': _insertTable(); break;
      case 'addTableRow': _addTableRow(); break;
      case 'addTableCol': _addTableCol(); break;
      case 'toggleImagePath': _toggleImagePathMode(); break;
      case 'formatDocument': _formatDocument(); break;
      case 'repairPaths': _repairPublishPaths(); break;
      case 'batchOps':   _showBatchOperations(); break;
      // 导出功能
      case 'exportHtml':  _exportHtml(); break;
      case 'exportPdf':   _exportPdf(); break;
      case 'exportDocx':  _exportDocx(); break;
      case 'exportEpub':  _exportEpub(); break;
      // 文件管理
      case 'openFolder':  _openFolderWorkspace(); break;
      case 'renameFile':  _renameCurrentFile(); break;
      case 'moveFile':    _moveCurrentFile(); break;
      // 编辑器自定义功能
      case 'fontSettings': _showFontSettings(); break;
      case 'themePicker':  _showThemePicker(); break;
      case 'customCss':    _showCustomCssEditor(); break;
      case 'shortcutEditor': _showShortcutEditor(); break;
      case 'help':          _showHelpDialog(); break;
      case 'recycleBin':    _openRecycleBin(); break;
      case 'imageBed':      _openImageBedManager(); break;
      case 'versionHistory': _openVersionHistory(); break;
      case 'proxySettings': _openProxySettings(); break;
      case 'globalSearch':  _openGlobalSearch(); break;
      case 'cacheCleanup': _openCacheCleanup(); break;
      case 'exportLogs':   _exportLogs(); break;
      case 'fixEncoding':  _fixEncoding(); break;
      case 'offlineMode':  _toggleOfflineMode(); break;
      case 'nightEye':     _toggleNightEyeProtection(); break;
      case 'linkChecker':  _openLinkChecker(); break;
      case 'batchTools':   _openBatchTools(); break;
      case 'aiTemplates':  _openAiPromptTemplates(); break;
      case 'importHtml':   _importHtmlFile(); break;
      case 'importDocx':   _importDocxFile(); break;
      case 'conflictResolve': _checkAndResolveConflicts(); break;
      case 'aiSelection':  _sendSelectionToAi(); break;
      case 'aiFullText':   _sendFullToAi(); break;
      case 'schedulePublish': _schedulePublish(); break;
      case 'publishChangeLog': _showPublishChangeLog(''); break;
      case 'aiDiffPreview': _showAiDiffPreview(_contentCtrl.text, ''); break;
    }
  }

  /// 打开外部 .md 文件加载到编辑器
  void openExternalFile(String fileName, String content, String filePath) {
    _addRecentFile(filePath, fileName);
    final article = Article(
      id: 'external_${DateTime.now().millisecondsSinceEpoch}',
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
  void _addRecentFile(String path, String name) {
    _recentFiles.removeWhere((f) => f.path == path);
    _recentFiles.insert(0, RecentFile(path: path, name: name, openedAt: DateTime.now()));
    if (_recentFiles.length > _maxRecentFiles) {
      _recentFiles.removeRange(_maxRecentFiles, _recentFiles.length);
    }
    _persistRecentFiles();
  }

  Future<void> _persistRecentFiles() async {
    try {
      final rootDir = await storage.root;
      final file = File('${rootDir.path}/recent_files.json');
      await file.writeAsString(jsonEncode(
        _recentFiles.map((f) => {'path': f.path, 'name': f.name, 'openedAt': f.openedAt.toIso8601String()}).toList(),
      ));
    } catch (_) {}
  }

  Future<void> _loadRecentFiles() async {
    try {
      final rootDir = await storage.root;
      final file = File('${rootDir.path}/recent_files.json');
      if (await file.exists()) {
        final list = jsonDecode(await file.readAsString()) as List;
        _recentFiles.clear();
        for (final item in list) {
          _recentFiles.add(RecentFile(
            path: item['path'] as String,
            name: item['name'] as String,
            openedAt: DateTime.tryParse(item['openedAt']?.toString() ?? '') ?? DateTime.now(),
          ));
        }
      }
    } catch (_) {}
  }

  /// 从最近文件中打开
  void _openRecentFile(RecentFile rf) async {
    try {
      final file = File(rf.path);
      if (!await file.exists()) {
        _showToast('文件不存在: ${rf.path}');
        _recentFiles.removeWhere((f) => f.path == rf.path);
        _persistRecentFiles();
        return;
      }
      final content = await file.readAsString();
      openExternalFile(rf.name, content, rf.path);
    } catch (e) {
      _showToast('打开文件失败: $e');
    }
  }

  /// 文件打开对话框
  Future<void> _openFileDialog() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      final file = File(path);
      final content = await file.readAsString();
      final fileName = path.split('/').last.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');
      openExternalFile(fileName, content, path);
    } catch (e) {
      _showToast('打开文件失败: $e');
    }
  }

  // ============================================================
  // 剪贴板图片粘贴（桌面版：粘贴截图 → 上传图床 → 插入 Markdown）
  // ============================================================

  Future<void> _pasteImageFromClipboard() async {
    try {
      // 1) 检查剪贴板是否为图片 URL
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null) {
        final text = data!.text!.trim();
        if (text.startsWith('http') && RegExp(r'\.(png|jpg|jpeg|gif|webp|svg)(\?.*)?$', caseSensitive: false).hasMatch(text)) {
          _insertText(imageService.markdownImage(text));
          _showToast('图片链接已插入');
          return;
        }
      }

      // 2) 尝试获取剪贴板图片字节（桌面平台支持）
      Uint8List? imgBytes;
      try {
        final imgData = await Clipboard.getData('image/png');
        if (imgData != null) {
          if (imgData is Uint8List) {
            imgBytes = imgData;
          } else if (imgData.text != null) {
            imgBytes = Uint8List.fromList(imgData.text!.codeUnits);
          }
        }
      } catch (_) {}

      if (imgBytes != null && imgBytes.isNotEmpty) {
        setState(() { _editorBusy = true; _editorStatus = '正在上传剪贴板图片...'; });
        try {
          final url = await imageService.uploadToImageBed(imgBytes, settings);
          _insertText(imageService.markdownImage(url));
          _showToast('图片已粘贴并上传');
        } catch (e) {
          _showToast('图片上传失败: $e');
        } finally {
          if (mounted) setState(() => _editorBusy = false);
        }
        return;
      }

      // 3) 兜底：打开文件选择器选图片
      _showToast('剪贴板无图片，请选择图片文件');
      _insertImage();
    } catch (e) {
      _showToast('粘贴图片失败: $e');
    }
  }

  // ============================================================
  // IDE 风格 Markdown 快捷键助手
  // ============================================================

  /// 用前后缀包裹选中文本
  void _wrapSelection(String prefix, String suffix) {
    final sel = _contentCtrl.selection;
    final txt = _contentCtrl.text;
    if (!sel.isValid || sel.start == sel.end) {
      // 无选中：插入标记并放置光标在中间
      final s = sel.isValid ? sel.start : txt.length;
      _contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(s, s, '$prefix$suffix'),
        selection: TextSelection.collapsed(offset: s + prefix.length),
      );
    } else {
      // 选中文本：包裹
      final selected = txt.substring(sel.start, sel.end);
      _contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(sel.start, sel.end, '$prefix$selected$suffix'),
        selection: TextSelection.collapsed(offset: sel.start + prefix.length + selected.length + suffix.length),
      );
    }
    _contentFocus.requestFocus();
    _onContentChanged();
  }

  /// 在当前行首添加前缀
  void _prefixLine(String prefix) {
    final txt = _contentCtrl.text;
    final sel = _contentCtrl.selection;
    final lineStart = sel.isValid ? txt.lastIndexOf('\n', sel.start - 1) + 1 : 0;
    _contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: lineStart + prefix.length),
    );
    _contentFocus.requestFocus();
    _onContentChanged();
  }

  /// 插入 Markdown 链接
  void _insertLink() {
    final sel = _contentCtrl.selection;
    final txt = _contentCtrl.text;
    final selected = (sel.isValid && sel.start != sel.end) ? txt.substring(sel.start, sel.end) : '链接文本';
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    final md = '[$selected](url)';
    _contentCtrl.value = TextEditingValue(
      text: txt.replaceRange(s, e, md),
      selection: TextSelection(baseOffset: s + md.length - 4, extentOffset: s + md.length - 1),
    );
    _contentFocus.requestFocus();
    _onContentChanged();
  }

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

  /// 获取当前编辑器主题
  EditorTheme get _currentEditorTheme => getEditorTheme(_editorTheme);

  // ──────────────────────────────────────────────
  // 1. 字体设置对话框
  // ──────────────────────────────────────────────

  void _showFontSettings() {
    double localFontSize = _editorFontSize;
    double localLineHeight = _editorLineHeight;
    String localFontFamily = _editorFontFamily;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.text_fields, size: 20),
            SizedBox(width: 8),
            Text('字体设置', style: TextStyle(fontSize: 17)),
          ]),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 字体大小
                Row(children: [
                  const Icon(Icons.format_size, size: 16),
                  const SizedBox(width: 8),
                  const Text('字体大小', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Text('${localFontSize.toInt()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
                Slider(
                  value: localFontSize,
                  min: 12,
                  max: 28,
                  divisions: 16,
                  label: '${localFontSize.toInt()}',
                  onChanged: (v) => setDialogState(() => localFontSize = v),
                ),
                const SizedBox(height: 12),
                // 行高
                Row(children: [
                  const Icon(Icons.format_line_spacing, size: 16),
                  const SizedBox(width: 8),
                  const Text('行高', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Text(localLineHeight.toStringAsFixed(1), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
                Slider(
                  value: localLineHeight,
                  min: 1.2,
                  max: 2.5,
                  divisions: 13,
                  label: localLineHeight.toStringAsFixed(1),
                  onChanged: (v) => setDialogState(() => localLineHeight = v),
                ),
                const SizedBox(height: 12),
                // 字体族
                Row(children: [
                  const Icon(Icons.font_download_outlined, size: 16),
                  const SizedBox(width: 8),
                  const Text('字体族', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: localFontFamily,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'System', child: Text('System（系统默认）')),
                    DropdownMenuItem(value: 'monospace', child: Text('monospace（等宽）')),
                    DropdownMenuItem(value: 'serif', child: Text('serif（衬线）')),
                    DropdownMenuItem(value: 'sans-serif', child: Text('sans-serif（无衬线）')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => localFontFamily = v);
                  },
                ),
                const SizedBox(height: 16),
                // 预览
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'AaBbCc 中文预览 123',
                    style: TextStyle(
                      fontSize: localFontSize,
                      height: localLineHeight,
                      fontFamily: _resolveFontFamily(localFontFamily),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (mounted) {
                  setState(() {
                    _editorFontSize = localFontSize;
                    _editorLineHeight = localLineHeight;
                    _editorFontFamily = localFontFamily;
                  });
                }
                await _saveEditorSettings();
                _showToast('字体设置已保存');
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // 2. 代码语法高亮
  // ──────────────────────────────────────────────

  /// 根据主题名称获取对应的 highlight 主题
  Map<String, TextStyle> _getHighlightTheme() {
    switch (_editorTheme) {
      case 'monokai':
        return highlight_monokai.monokaiSublimeTheme;
      case 'dracula':
        return highlight_dracula.draculaTheme;
      case 'nord':
        return highlight_nord.nordTheme;
      case 'solarized-dark':
        return highlight_monokai.monokaiSublimeTheme;
      default:
        return highlight_github.githubTheme;
    }
  }

  /// 构建带语法高亮的代码块
  Widget _buildHighlightedCode(String code, String? language) {
    try {
      return HighlightView(
        code.trim(),
        language: (language != null && language.isNotEmpty) ? language : 'plaintext',
        theme: _getHighlightTheme(),
        padding: const EdgeInsets.all(12),
        textStyle: TextStyle(
          fontFamily: 'monospace',
          fontSize: _editorFontSize - 2,
          height: _editorLineHeight * 0.85,
        ),
      );
    } catch (_) {
      // 如果高亮失败，使用普通样式显示
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _currentEditorTheme.codeBlockBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          code.trim(),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: _editorFontSize - 2,
            height: _editorLineHeight * 0.85,
            color: _currentEditorTheme.codeBlockTextColor,
          ),
        ),
      );
    }
  }

  /// 构建增强的 Markdown 预览（支持代码高亮、Mermaid 和 LaTeX）
  Widget _buildMarkdownPreview(String markdown) {
    if (markdown.isEmpty) {
      return Center(
        child: Text(
          '*暂无内容*',
          style: TextStyle(
            color: _currentEditorTheme.textColor.withOpacity(0.4),
            fontSize: _editorFontSize,
          ),
        ),
      );
    }

    // 解析 Mermaid 代码块
    final mermaidPattern = RegExp(r'```mermaid\n([\s\S]*?)```');
    // 解析 LaTeX 块级公式 $$...$$
    final latexBlockPattern = RegExp(r'\$\$([\s\S]*?)\$\$');
    // 解析普通代码块
    final codeBlockPattern = RegExp(r'```(\w*)\n([\s\S]*?)```');

    final parts = <Widget>[];
    int lastEnd = 0;

    // 同时匹配所有特殊块
    final allMatches = <_SpecialBlock>[];
    for (final m in mermaidPattern.allMatches(markdown)) {
      allMatches.add(_SpecialBlock(m.start, m.end, 'mermaid', m.group(1) ?? ''));
    }
    for (final m in latexBlockPattern.allMatches(markdown)) {
      // 避免与 mermaid 块重叠
      if (!allMatches.any((b) => m.start >= b.start && m.start < b.end)) {
        allMatches.add(_SpecialBlock(m.start, m.end, 'latex', m.group(1) ?? ''));
      }
    }
    for (final m in codeBlockPattern.allMatches(markdown)) {
      final lang = m.group(1) ?? '';
      if (lang.toLowerCase() == 'mermaid') continue; // 已由 mermaid 处理
      if (!allMatches.any((b) => m.start >= b.start && m.start < b.end)) {
        allMatches.add(_SpecialBlock(m.start, m.end, 'code', m.group(2) ?? '',
            lang: lang.isNotEmpty ? lang : null));
      }
    }
    allMatches.sort((a, b) => a.start.compareTo(b.start));

    for (final block in allMatches) {
      // 添加前面的普通 Markdown
      if (block.start > lastEnd) {
        final before = markdown.substring(lastEnd, block.start);
        parts.add(_renderPlainMarkdown(before));
      }

      // 根据类型渲染特殊块
      switch (block.type) {
        case 'mermaid':
          parts.add(_buildMermaidPreview(block.content));
          break;
        case 'latex':
          parts.add(_buildLatexPreview(block.content));
          break;
        case 'code':
          parts.add(_buildHighlightedCode(block.content, block.lang));
          break;
      }
      lastEnd = block.end;
    }

    // 添加剩余的普通 Markdown
    if (lastEnd < markdown.length) {
      parts.add(_renderPlainMarkdown(markdown.substring(lastEnd)));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: parts,
      ),
    );
  }

  /// 渲染普通 Markdown 文本（不含代码块）
  Widget _renderPlainMarkdown(String text) {
    final theme = _currentEditorTheme;
    final cssStyle = _buildCustomMarkdownStyleSheet();

    // 处理内联 LaTeX $...$
    if (text.contains(RegExp(r'(?<!\$)\$(?!\$)[^$]+\$(?!\$)')) && text.length < 5000) {
      return _buildInlineLatexMarkdown(text, cssStyle);
    }

    return Markdown(
      data: text,
      selectable: true,
      styleSheet: cssStyle,
    );
  }

  /// 构建含内联 LaTeX 的 Markdown 渲染
  Widget _buildInlineLatexMarkdown(String text, MarkdownStyleSheet styleSheet) {
    final inlinePattern = RegExp(r'(?<!\$)\$(?!\$)([^$]+)\$(?!\$)');
    final parts = <Widget>[];
    int lastEnd = 0;

    for (final m in inlinePattern.allMatches(text)) {
      if (m.start > lastEnd) {
        final before = text.substring(lastEnd, m.start);
        if (before.isNotEmpty) {
          parts.add(Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Markdown(data: before, selectable: true, styleSheet: styleSheet),
          ));
        }
      }
      final latex = m.group(1) ?? '';
      try {
        parts.add(
          Math.tex(
            latex,
            mathStyle: MathStyle.text,
            textStyle: TextStyle(
              fontSize: _editorFontSize,
              color: _currentEditorTheme.textColor,
            ),
          ),
        );
      } catch (_) {
        parts.add(Text('\$$latex\$', style: TextStyle(fontSize: _editorFontSize)));
      }
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      final remaining = text.substring(lastEnd);
      if (remaining.isNotEmpty) {
        parts.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Markdown(data: remaining, selectable: true, styleSheet: styleSheet),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts,
    );
  }

  /// 根据自定义 CSS 构建 MarkdownStyleSheet
  MarkdownStyleSheet _buildCustomMarkdownStyleSheet() {
    final theme = _currentEditorTheme;

    // 基础样式
    double? h1Size, h2Size, h3Size;
    Color? h1Color, h2Color, h3Color;
    Color? codeBg, codeText;
    Color? linkColor;

    h1Size = _editorFontSize * 1.5;
    h2Size = _editorFontSize * 1.3;
    h3Size = _editorFontSize * 1.15;
    h1Color = theme.headingColor;
    h2Color = theme.heading2Color;
    h3Color = theme.heading3Color;
    codeBg = theme.codeBlockBackground;
    codeText = theme.codeBlockTextColor;
    linkColor = theme.linkColor;

    // 如果有自定义 CSS，尝试解析
    if (_customCss.isNotEmpty) {
      try {
        final cssMap = _parseSimpleCss(_customCss);
        if (cssMap.containsKey('h1-size')) h1Size = double.tryParse(cssMap['h1-size']!);
        if (cssMap.containsKey('h2-size')) h2Size = double.tryParse(cssMap['h2-size']!);
        if (cssMap.containsKey('h3-size')) h3Size = double.tryParse(cssMap['h3-size']!);
        if (cssMap.containsKey('code-bg')) codeBg = _parseColor(cssMap['code-bg']!);
        if (cssMap.containsKey('code-color')) codeText = _parseColor(cssMap['code-color']!);
        if (cssMap.containsKey('link-color')) linkColor = _parseColor(cssMap['link-color']!);
      } catch (_) {}
    }

    return MarkdownStyleSheet(
      p: TextStyle(
        fontSize: _editorFontSize,
        height: _editorLineHeight,
        color: theme.textColor,
        fontFamily: _resolveFontFamily(_editorFontFamily),
      ),
      h1: TextStyle(
        fontSize: h1Size,
        fontWeight: FontWeight.w700,
        color: h1Color,
        fontFamily: _resolveFontFamily(_editorFontFamily),
      ),
      h2: TextStyle(
        fontSize: h2Size,
        fontWeight: FontWeight.w600,
        color: h2Color,
        fontFamily: _resolveFontFamily(_editorFontFamily),
      ),
      h3: TextStyle(
        fontSize: h3Size,
        fontWeight: FontWeight.w600,
        color: h3Color,
        fontFamily: _resolveFontFamily(_editorFontFamily),
      ),
      code: TextStyle(
        fontSize: _editorFontSize - 2,
        fontFamily: 'monospace',
        color: codeText,
        backgroundColor: codeBg,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(8),
      ),
      a: TextStyle(
        color: linkColor,
        fontSize: _editorFontSize,
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.blockquoteBackground,
        border: Border(left: BorderSide(color: theme.blockquoteBorderColor, width: 3)),
      ),
    );
  }

  /// 简单 CSS 解析器（将 CSS 属性映射为 key-value）
  Map<String, String> _parseSimpleCss(String css) {
    final result = <String, String>{};
    final rules = css.split(';');
    for (final rule in rules) {
      final parts = rule.split(':');
      if (parts.length == 2) {
        final key = parts[0].trim().toLowerCase();
        final value = parts[1].trim();
        result[key] = value;
      }
    }
    return result;
  }

  /// 解析颜色字符串
  Color? _parseColor(String colorStr) {
    try {
      if (colorStr.startsWith('#')) {
        final hex = colorStr.substring(1);
        if (hex.length == 6) {
          return Color(int.parse('FF$hex', radix: 16));
        } else if (hex.length == 8) {
          return Color(int.parse(hex, radix: 16));
        }
      }
      // 简单颜色名称映射
      const colorNames = {
        'red': 0xFFFF0000, 'blue': 0xFF0000FF, 'green': 0xFF008000,
        'black': 0xFF000000, 'white': 0xFFFFFFFF, 'gray': 0xFF808080,
        'grey': 0xFF808080, 'orange': 0xFFFFA500, 'purple': 0xFF800080,
        'yellow': 0xFFFFFF00, 'cyan': 0xFF00FFFF, 'magenta': 0xFFFF00FF,
      };
      if (colorNames.containsKey(colorStr.toLowerCase())) {
        return Color(colorNames[colorStr.toLowerCase()]!);
      }
    } catch (_) {}
    return null;
  }

  // ──────────────────────────────────────────────
  // 3. 编辑器主题选择器
  // ──────────────────────────────────────────────

  void _showThemePicker() {
    final themeKeys = editorThemes.keys.toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          String selectedTheme = _editorTheme;
          return AlertDialog(
            title: const Row(children: [
              Icon(Icons.palette_outlined, size: 20),
              SizedBox(width: 8),
              Text('编辑器主题', style: TextStyle(fontSize: 17)),
            ]),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 当前主题预览
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: getEditorTheme(selectedTheme).backgroundColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '标题预览',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: getEditorTheme(selectedTheme).headingColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '这是正文预览文本，展示当前主题的文字颜色效果。',
                          style: TextStyle(
                            fontSize: 13,
                            color: getEditorTheme(selectedTheme).textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: getEditorTheme(selectedTheme).codeBlockBackground,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'code block preview',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: getEditorTheme(selectedTheme).codeBlockTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 主题网格
                  SizedBox(
                    height: 200,
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.3,
                      ),
                      itemCount: themeKeys.length,
                      itemBuilder: (_, i) {
                        final key = themeKeys[i];
                        final theme = editorThemes[key]!;
                        final isSelected = selectedTheme == key;
                        return GestureDetector(
                          onTap: () => setDialogState(() => selectedTheme = key),
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.backgroundColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? Theme.of(ctx).colorScheme.primary : Colors.grey.shade300,
                                width: isSelected ? 2.5 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  theme.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: theme.textColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: 30,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: theme.headingColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: 40,
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color: theme.textColor.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  if (mounted) {
                    setState(() => _editorTheme = selectedTheme);
                  }
                  await _saveEditorSettings();
                  _showToast('主题已切换为: ${getEditorTheme(selectedTheme).name}');
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('应用'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────
  // 4. 自定义 CSS 编辑器
  // ──────────────────────────────────────────────

  void _showCustomCssEditor() {
    final cssCtrl = TextEditingController(text: _customCss);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.css, size: 20),
          SizedBox(width: 8),
          Text('自定义 CSS', style: TextStyle(fontSize: 17)),
        ]),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '支持简化的 CSS 属性映射，如：\n'
                'h1-size: 28; h2-size: 22; h3-size: 18;\n'
                'code-bg: #f5f5f5; code-color: #333;\n'
                'link-color: #0366d6;',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cssCtrl,
                maxLines: 10,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  hintText: '在此输入自定义 CSS 规则...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cssCtrl.text = '';
              if (mounted) {
                setState(() => _customCss = '');
              }
              _saveEditorSettings();
              _showToast('CSS 已重置');
              Navigator.pop(ctx);
            },
            child: const Text('重置'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (mounted) {
                setState(() => _customCss = cssCtrl.text);
              }
              await _saveEditorSettings();
              _showToast('自定义 CSS 已应用');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('应用'),
          ),
        ],
      ),
    );
  }

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
    'focus': 'Ctrl+F',
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

  void _showShortcutEditor() {
    // 合并默认快捷键和自定义快捷键
    final shortcuts = Map<String, String>.from(_defaultShortcuts);
    shortcuts.addAll(_customShortcuts);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(children: [
              Icon(Icons.keyboard, size: 20),
              SizedBox(width: 8),
              Text('快捷键设置', style: TextStyle(fontSize: 17)),
            ]),
            content: SizedBox(
              width: 500,
              height: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '提示: 点击快捷键值可编辑，修改后点击空白处保存。\n'
                      '格式: Ctrl+X / Ctrl+Shift+X / Alt+X',
                      style: TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: shortcuts.entries.map((entry) {
                        final action = entry.key;
                        final shortcut = entry.value;
                        final label = _actionLabels[action] ?? action;
                        final ctrl = TextEditingController(text: shortcut);

                        return ListTile(
                          dense: true,
                          title: Text(label, style: const TextStyle(fontSize: 13)),
                          trailing: SizedBox(
                            width: 140,
                            child: TextField(
                              controller: ctrl,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: shortcut.isEmpty ? Colors.grey : null,
                              ),
                              decoration: InputDecoration(
                                hintText: '未设置',
                                hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              onSubmitted: (value) {
                                _customShortcuts[action] = value.trim();
                                _saveEditorSettings();
                                setDialogState(() {});
                              },
                              onTapOutside: (_) {
                                _customShortcuts[action] = ctrl.text.trim();
                                _saveEditorSettings();
                                setDialogState(() {});
                              },
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _customShortcuts.clear();
                  _saveEditorSettings();
                  _showToast('快捷键已重置为默认值');
                  Navigator.pop(ctx);
                },
                child: const Text('恢复默认'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────
  // 6. Mermaid 图表渲染
  // ──────────────────────────────────────────────

  Widget _buildMermaidPreview(String mermaidCode) {
    const htmlTemplate = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
  <script>
    mermaid.initialize({ startOnLoad: true, theme: 'default' });
  </script>
  <style>
    body { margin: 0; padding: 16px; background: transparent; }
    .mermaid { display: flex; justify-content: center; }
  </style>
</head>
<body>
  <div class="mermaid">
PLACEHOLDER
  </div>
</body>
</html>
''';

    final html = htmlTemplate.replaceFirst('PLACEHOLDER', mermaidCode.trim());

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      height: 300,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: WebViewWidget(
          controller: WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..loadHtmlString(html),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // 7. LaTeX 数学公式渲染
  // ──────────────────────────────────────────────

  Widget _buildLatexPreview(String latexCode) {
    try {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _currentEditorTheme.codeBlockBackground.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300.withOpacity(0.5)),
        ),
        child: Center(
          child: Math.tex(
            latexCode.trim(),
            mathStyle: MathStyle.display,
            textStyle: TextStyle(
              fontSize: _editorFontSize + 2,
              color: _currentEditorTheme.textColor,
            ),
          ),
        ),
      );
    } catch (e) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'LaTeX 渲染错误: $latexCode',
          style: TextStyle(fontSize: 12, color: Colors.red.shade700),
        ),
      );
    }
  }

  // ============================================================
  // 帮助 / 快捷键速查 (F1)
  // ============================================================

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.help_outline, size: 22),
          SizedBox(width: 8),
          Text('帮助 · 快捷键速查', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
        content: SizedBox(
          width: 700,
          height: 520,
          child: DefaultTabController(
            length: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TabBar(
                  labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: TextStyle(fontSize: 13),
                  tabs: [
                    Tab(text: '快捷键'),
                    Tab(text: '功能概览'),
                    Tab(text: '模式与布局'),
                    Tab(text: '使用技巧'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 420,
                  child: TabBarView(
                    children: [
                      // ── 快捷键 ──
                      _buildHelpShortcuts(),
                      // ── 功能概览 ──
                      _buildHelpFeatures(),
                      // ── 模式与布局 ──
                      _buildHelpLayout(),
                      // ── 使用技巧 ──
                      _buildHelpTips(),
                    ],
                  ),
                ),
              ],
            ),
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

  Widget _buildHelpShortcuts() {
    final shortcuts = <(String, String)>[
      ('Ctrl+S', '保存草稿'),
      ('Ctrl+P', '一键发布'),
      ('Ctrl+N', '新建文章'),
      ('Ctrl+O', '打开 .md 文件'),
      ('Ctrl+Shift+S', '另存为到本地'),
      ('Ctrl+Shift+P', '命令面板'),
      ('F1', '打开帮助'),
      ('Ctrl+B', '加粗'),
      ('Ctrl+I', '斜体'),
      ('Ctrl+D', '删除线'),
      ('Ctrl+K', '插入链接'),
      ('Ctrl+1', '一级标题'),
      ('Ctrl+2', '二级标题'),
      ('Ctrl+3', '三级标题'),
      ('Ctrl+Shift+V', '粘贴剪贴板图片'),
      ('Ctrl+F', '专注模式'),
      ('Ctrl+L', '切换左侧面板'),
      ('Ctrl+E', '打开大纲'),
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: shortcuts.map((e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(
            width: 130,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(e.$1, style: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(e.$2, style: const TextStyle(fontSize: 13))),
        ]),
      )).toList(),
    );
  }

  Widget _buildHelpFeatures() {
    final features = [
      ('写作编辑', ['Markdown 实时预览', '代码语法高亮（flutter_highlight）', 'LaTeX 数学公式（块级+内联）', 'Mermaid 图表渲染', '查找替换（支持正则）', 'TOC 自动生成', '可视化表格编辑', '全文格式化', '打字机模式（光标居中）']),
      ('图片处理', ['剪贴板截图粘贴上传', '本地图片选择上传', '批量插图+预处理压缩', '图片尺寸快捷设置', '图片路径相对/绝对切换', '发布前路径自动修复', '图床管理面板', '图片死链检测']),
      ('多格式导出', ['HTML（完整模板）', 'PDF（printing 包）', 'DOCX（OOXML）', 'EPUB（电子书）', '另存为到本地']),
      ('AI 能力', ['AI 润色/续写', 'AI 博文/页面创作', 'AI 主题迁移', 'AI 站点巡检', 'AI 选区改写', 'AI 全文润色', 'AI 输出对比（diff 预览）', 'AI 提示词模板库']),
      ('编辑器自定义', ['7 种编辑器主题', '自定义字体/字号/行高', '自定义 CSS', '自定义快捷键', '夜间护眼滤镜']),
      ('文件管理', ['最近打开文件（10条）', '文件夹工作区', '文件重命名/移动', '拖拽 .md 文件导入', '回收站（防误删）', '版本历史快照', '编码修复工具']),
      ('同步与发布', ['GitHub / WebDAV 云同步', '同步冲突可视化对比', '冲突策略（本地/云端优先）', '一键发布到 GitHub/CMS', '发布前预检测', '定时发布', '发布变更日志']),
      ('导入', ['HTML 转 Markdown', 'DOCX 转 Markdown', '.md / .txt 打开']),
      ('搜索', ['全局工作区搜索', '草稿/已发布筛选', '编辑器内查找替换']),
      ('系统', ['网络代理设置', '离线模式', '缓存清理', '日志导出', '命令面板（Ctrl+Shift+P）']),
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: features.map((group) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group.$1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ...group.$2.map((item) => Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Row(children: [
              const Text('  •  ', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Expanded(child: Text(item, style: const TextStyle(fontSize: 12.5))),
            ]),
          )),
        ]),
      )).toList(),
    );
  }

  Widget _buildHelpLayout() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: const [
        Text('🎯 三种工作模式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        _HelpModeCard('工作台', '完整三栏布局：左侧导航 + 中央编辑器 + 右侧抽屉', '适合日常写作、管理文章'),
        _HelpModeCard('专注模式', '极简顶栏，隐藏面板，全宽编辑器 + 实时预览', '适合沉浸式写作，打字机滚动'),
        _HelpModeCard('源码模式', '等宽字体纯文本编辑，隐藏预览', '适合直接编辑 Markdown 源码'),
        SizedBox(height: 16),
        Text('📐 布局说明', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        _HelpLayoutItem('顶栏', '站点切换下拉框 + 功能按钮（同步/发布/AI/主题/文件/新建）'),
        _HelpLayoutItem('左侧面板', '可折叠、可拖拽宽度。包含全部导航入口'),
        _HelpLayoutItem('中央编辑器', '多标签页，支持切换和关闭'),
        _HelpLayoutItem('右侧抽屉', '悬浮式，4 个标签：大纲 | 属性 | AI 聊天 | 同步日志'),
        _HelpLayoutItem('底部状态栏', '工作模式切换 | 编辑器状态 | 行列位置 | 字数统计'),
        SizedBox(height: 16),
        Text('⌨️ 命令面板', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('  Ctrl+Shift+P 打开命令面板，搜索 48 条命令，覆盖全部功能。\n  无需记忆快捷键，输入关键词即可快速执行。', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
      ],
    );
  }

  Widget _buildHelpTips() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        _HelpTipCard('💡 快速发布', '写完文章后，按 Ctrl+P 直接发布。\n发布前会自动检查图片路径，可在确认框中勾选"同时保存 MD 备份"。'),
        _HelpTipCard('🖼️ 截图粘贴', '截屏后按 Ctrl+Shift+V，图片自动上传到 GitHub 图床并插入 Markdown。\n也可以在编辑器中右键粘贴。'),
        _HelpTipCard('📝 自动保存', '开启自动保存后，每隔 N 秒自动保存草稿到本地。\n切后台/关闭窗口前也会自动保存，不用担心丢失。'),
        _HelpTipCard('☁️ 云同步', '配置 WebDAV 后，启动时自动拉取，定时推送，切后台推送，切前台拉取。\n多设备间无缝同步草稿。'),
        _HelpTipCard('🔍 查找替换', '支持正则表达式和区分大小写。\n全部替换会一次性替换所有匹配项。'),
        _HelpTipCard('📊 表格编辑', '插入表格后，光标放在表格内可使用"添加行/列"功能。\n支持动态扩展表格。'),
        _HelpTipCard('🎨 主题切换', '7 种编辑器主题可随时切换，预览区同步生效。\nGitHub 主题适合亮色环境，Monokai/Dracula/Nord 适合暗色。'),
        _HelpTipCard('📦 批量操作', '在草稿箱中可多选草稿，批量导出、格式化或发布。\n适合需要一次性处理多篇文章的场景。'),
        _HelpTipCard('🔄 图片路径', '使用相对路径写作，发布前用"修复发布路径"一键转为绝对路径。\n切换图片路径模式可批量转换。'),
        _HelpTipCard('📂 文件管理', '打开文件夹工作区可浏览整个目录的 .md 文件。\n最近打开文件列表记录最近 10 个文件，方便快速切换。'),
        _HelpTipCard('⚠️ 冲突处理', '多设备同步时若出现冲突，会自动弹出双栏对比界面。\n可选择保留本地版本、云端版本，或全部本地/云端优先。'),
        _HelpTipCard('🤖 AI 选区', '选中一段文字后按 Ctrl+Shift+I，只将选中文字发送给 AI 改写。\nAI 修改完成后会显示 diff 对比，可选择接受或拒绝。'),
        _HelpTipCard('⏰ 定时发布', '在命令面板中搜索"定时发布"，设置时间后自动发布。\n适合在节假日或特定时间点自动推送文章。'),
        _HelpTipCard('🔍 全局搜索', 'Ctrl+Shift+F 搜索所有文章的标题和正文。\n可筛选草稿/已发布状态，快速定位目标文章。'),
        _HelpTipCard('🛡️ 发布预检', '发布前自动检查空标题、空内容、图片链接等。\n确保发布质量，避免推送不完整文章。'),
      ],
    );
  }

  // ============================================================
  // 命令面板 (Ctrl+Shift+P)
  // ============================================================

  void _showCommandPalette() {
    final commands = <_CommandItem>[
      _CommandItem('保存草稿', 'Ctrl+S', Icons.save, () => _saveLocal()),
      _CommandItem('一键发布', 'Ctrl+P', Icons.send, () => _handlePublish()),
      _CommandItem('新建文章', 'Ctrl+N', Icons.add, () => _newArticle()),
      _CommandItem('打开文件', 'Ctrl+O', Icons.folder_open, () => _openFileDialog()),
      _CommandItem('另存为...', 'Ctrl+Shift+S', Icons.save_as, () => _saveAsToLocal()),
      _CommandItem('查找替换', 'Ctrl+F', Icons.find_replace, () => _showFindReplace()),
      _CommandItem('插入目录', '', Icons.toc, () => _insertToc()),
      _CommandItem('插入表格', '', Icons.table_chart, () => _insertTable()),
      _CommandItem('添加表格行', '', Icons.add_row, () => _addTableRow()),
      _CommandItem('添加表格列', '', Icons.add_column, () => _addTableCol()),
      _CommandItem('切换图片路径模式', '', Icons.swap_horiz, () => _toggleImagePathMode()),
      _CommandItem('图片尺寸-小', '', Icons.photo_size_select_small, () => _setImageSize('small')),
      _CommandItem('图片尺寸-中', '', Icons.photo_size_select_large, () => _setImageSize('medium')),
      _CommandItem('图片尺寸-大', '', Icons.photo_library, () => _setImageSize('large')),
      _CommandItem('图片尺寸-全宽', '', Icons.photo, () => _setImageSize('full')),
      _CommandItem('文档格式化', '', Icons.cleaning_services, () => _formatDocument()),
      _CommandItem('修复发布路径', '', Icons.healing, () => _repairPublishPaths()),
      _CommandItem('批量操作', '', Icons.playlist_add_check, () => _showBatchOperations()),
      _CommandItem('专注模式', 'Ctrl+Shift+F', Icons.auto_awesome, () => _switchWorkMode(WorkMode.focus)),
      _CommandItem('工作台模式', '', Icons.dashboard, () => _switchWorkMode(WorkMode.workspace)),
      _CommandItem('源码模式', '', Icons.code, () => _switchWorkMode(WorkMode.source)),
      _CommandItem('切换左侧面板', 'Ctrl+L', Icons.menu_open, () => _toggleLeftPanel()),
      _CommandItem('打开大纲', 'Ctrl+E', Icons.list_alt, () => _openRightDrawer(RightDrawerTab.outline)),
      _CommandItem('粘贴图片', 'Ctrl+Shift+V', Icons.image, () => _pasteImageFromClipboard()),
      _CommandItem('云同步', '', Icons.cloud_sync, () => _openSyncSettings()),
      _CommandItem('设置', '', Icons.settings_outlined, () => _openSettings()),
      _CommandItem('草稿箱', '', Icons.drafts_outlined, () => _openDrafts()),
      _CommandItem('远程文章', '', Icons.cloud_outlined, () => _openRemote()),
      _CommandItem('仪表盘', '', Icons.dashboard_outlined, () => _openDashboard()),
      _CommandItem('AI 博文创作', '', Icons.article_outlined, () => _showAiArticleChat()),
      _CommandItem('AI 站点巡检', '', Icons.fact_check_outlined, () => _showAiAudit()),
      _CommandItem('模板管理', '', Icons.view_quilt_outlined, () => _showTemplateManager()),
      _CommandItem('操作日志', '', Icons.history, () => _openLogs()),
      // 导出功能
      _CommandItem('导出 HTML', '', Icons.html, () => _exportHtml()),
      _CommandItem('导出 PDF', '', Icons.picture_as_pdf, () => _exportPdf()),
      _CommandItem('导出 DOCX', '', Icons.description, () => _exportDocx()),
      _CommandItem('导出 EPUB', '', Icons.book, () => _exportEpub()),
      // 文件管理
      _CommandItem('打开文件夹工作区', '', Icons.folder_copy, () => _openFolderWorkspace()),
      _CommandItem('重命名当前文件', '', Icons.drive_file_rename_outline, () => _renameCurrentFile()),
      _CommandItem('移动当前文件', '', Icons.drive_file_move, () => _moveCurrentFile()),
      // 编辑器自定义功能
      _CommandItem('字体设置', '', Icons.text_fields, () => _showFontSettings()),
      _CommandItem('编辑器主题', '', Icons.palette_outlined, () => _showThemePicker()),
      _CommandItem('自定义 CSS', '', Icons.css, () => _showCustomCssEditor()),
      _CommandItem('快捷键设置', '', Icons.keyboard, () => _showShortcutEditor()),
      _CommandItem('帮助 / 快捷键速查', 'F1', Icons.help_outline, () => _showHelpDialog()),
      _CommandItem('回收站', '', Icons.delete_outline, () => _openRecycleBin()),
      _CommandItem('图床管理', '', Icons.photo_library_outlined, () => _openImageBedManager()),
      _CommandItem('版本历史', '', Icons.history, () => _openVersionHistory()),
      _CommandItem('代理设置', '', Icons.vpn_lock_outlined, () => _openProxySettings()),
      _CommandItem('全局搜索', '', Icons.manage_search, () => _openGlobalSearch()),
      _CommandItem('缓存清理', '', Icons.cleaning_services_outlined, () => _openCacheCleanup()),
      _CommandItem('导出日志', '', Icons.bug_report_outlined, () => _exportLogs()),
      _CommandItem('编码修复', '', Icons.text_fields, () => _fixEncoding()),
      _CommandItem('离线模式', '', Icons.airplane_ticket_outlined, () => _toggleOfflineMode()),
      _CommandItem('护眼滤镜', '', Icons.nightlight_round, () => _toggleNightEyeProtection()),
      _CommandItem('链接检测', '', Icons.link_off, () => _openLinkChecker()),
      _CommandItem('批量工具箱', '', Icons.build_circle, () => _openBatchTools()),
      _CommandItem('AI 提示词模板', '', Icons.text_snippet_outlined, () => _openAiPromptTemplates()),
      _CommandItem('导入 HTML', '', Icons.html, () => _importHtmlFile()),
      _CommandItem('导入 DOCX', '', Icons.description, () => _importDocxFile()),
      _CommandItem('AI 选区改写', '', Icons.short_text, () => _sendSelectionToAi()),
      _CommandItem('AI 全文润色', '', Icons.auto_awesome, () => _sendFullToAi()),
      _CommandItem('同步冲突解决', '', Icons.compare_arrows, () => _checkAndResolveConflicts()),
      _CommandItem('定时发布', '', Icons.schedule_send, () => _schedulePublish()),
      _CommandItem('发布变更日志', '', Icons.change_circle_outlined, () => _showPublishChangeLog('')),
      _CommandItem('AI 输出对比', '', Icons.compare_arrows, () => _showAiDiffPreview(_contentCtrl.text, '')),
    ];

    final searchCtrl = TextEditingController();
    String filter = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = filter.isEmpty
              ? commands
              : commands.where((c) => c.label.contains(filter) || c.shortcut.contains(filter)).toList();
          return AlertDialog(
            title: const Text('命令面板', style: TextStyle(fontSize: 16)),
            titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '搜索命令...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setDialogState(() => filter = v.toLowerCase()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final cmd = filtered[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(cmd.icon, size: 18),
                          title: Text(cmd.label, style: const TextStyle(fontSize: 13)),
                          trailing: cmd.shortcut.isNotEmpty
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(cmd.shortcut, style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey.shade700)),
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(ctx);
                            cmd.action();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // 另存为到本地目录
  // ============================================================

  Future<void> _saveAsToLocal() async {
    try {
      final title = _titleCtrl.text.isNotEmpty ? _titleCtrl.text : 'untitled';
      final safeTitle = _safeTitle(title);
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '另存为 Markdown 文件',
        fileName: '$safeTitle.md',
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
      );
      if (result == null) return;
      final file = File(result);
      final a = _collect(draft: true);
      await file.writeAsString(a.toMarkdownWithFrontMatter());
      _addRecentFile(result, safeTitle);
      if (mounted) _showToast('已保存到: $result');
    } catch (e) {
      if (mounted) _showToast('保存失败: $e');
    }
  }

  // ============================================================
  // 导出功能
  // ============================================================

  /// 安全的文件名（去除非法字符）
  String _safeTitle(String title) {
    return title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  /// 将 Markdown 内容转换为 HTML 字符串
  String _mdToHtml(String markdown, String title) {
    final body = md.markdownToHtml(
      markdown.isEmpty ? '*暂无内容*' : markdown,
    );
    // 包装为完整的 HTML 模板
    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_escapeHtml(title)}</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      max-width: 800px;
      margin: 40px auto;
      padding: 0 20px;
      line-height: 1.8;
      font-size: 16px;
      color: #333;
    }
    h1 { font-size: 2em; margin-top: 0.5em; }
    h2 { font-size: 1.5em; margin-top: 1em; }
    h3 { font-size: 1.2em; margin-top: 0.8em; }
    pre { background: #f5f5f5; padding: 16px; border-radius: 6px; overflow-x: auto; }
    code { background: #f0f0f0; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
    pre code { background: none; padding: 0; }
    blockquote { border-left: 4px solid #ddd; margin: 0; padding: 0 16px; color: #666; }
    img { max-width: 100%; height: auto; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
    th { background: #f5f5f5; }
  </style>
</head>
<body>
$body
</body>
</html>''';
  }

  /// 对 HTML 特殊字符进行转义
  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// 导出 HTML 文件
  Future<void> _exportHtml() async {
    try {
      final title = _titleCtrl.text.isNotEmpty ? _titleCtrl.text : 'untitled';
      final safeTitle = _safeTitle(title);
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出 HTML 文件',
        fileName: '$safeTitle.html',
        type: FileType.custom,
        allowedExtensions: ['html', 'htm'],
      );
      if (result == null) return;
      final html = _mdToHtml(_contentCtrl.text, title);
      final file = File(result);
      await file.writeAsString(html);
      if (mounted) _showToast('HTML 已导出到: $result');
    } catch (e) {
      if (mounted) _showToast('HTML 导出失败: $e');
    }
  }

  /// 导出 PDF 文件
  Future<void> _exportPdf() async {
    try {
      final title = _titleCtrl.text.isNotEmpty ? _titleCtrl.text : 'untitled';
      final safeTitle = _safeTitle(title);
      final html = _mdToHtml(_contentCtrl.text, title);

      try {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: '导出 PDF 文件',
          fileName: '$safeTitle.pdf',
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (result == null) return;

        // 使用 Printing 包将 HTML 直接转换为 PDF 字节
        final pdfBytes = await Printing.convertHtml(
          format: PdfPageFormat.a4,
          html: html,
        );
        final file = File(result);
        await file.writeAsBytes(pdfBytes);
        if (mounted) _showToast('PDF 已导出到: $result');
      } catch (_) {
        // printing 包不可用时，回退到保存 HTML
        final result = await FilePicker.platform.saveFile(
          dialogTitle: '导出 PDF 文件（回退 HTML）',
          fileName: '$safeTitle.html',
          type: FileType.custom,
          allowedExtensions: ['html'],
        );
        if (result == null) return;
        final file = File(result);
        await file.writeAsString(html);
        if (mounted) _showToast('PDF 导出回退为 HTML: $result');
      }
    } catch (e) {
      if (mounted) _showToast('PDF 导出失败: $e');
    }
  }

  /// 导出 DOCX 文件（基于 Office Open XML 格式）
  Future<void> _exportDocx() async {
    try {
      final title = _titleCtrl.text.isNotEmpty ? _titleCtrl.text : 'untitled';
      final safeTitle = _safeTitle(title);
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出 DOCX 文件',
        fileName: '$safeTitle.docx',
        type: FileType.custom,
        allowedExtensions: ['docx'],
      );
      if (result == null) return;

      final htmlContent = _mdToHtml(_contentCtrl.text, title);

      // 构建基本的 Office Open XML 结构
      final docxBytes = _buildDocxZip(title, htmlContent);
      final file = File(result);
      await file.writeAsBytes(docxBytes);
      if (mounted) _showToast('DOCX 已导出到: $result');
    } catch (e) {
      if (mounted) _showToast('DOCX 导出失败: $e');
    }
  }

  /// 构建 DOCX ZIP 文件
  Uint8List _buildDocxZip(String title, String htmlContent) {
    final escapedTitle = _escapeXml(title);
    final escapedHtml = _escapeXmlBody(htmlContent);

    // [Content_Types].xml
    const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    // _rels/.rels
    const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    // word/_rels/document.xml.rels
    const wordRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>''';

    // word/document.xml - 将 HTML 内容转换为基本的 OOXML 段落
    final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    <w:p>
      <w:pPr>
        <w:pStyle w:val="Title"/>
      </w:pPr>
      <w:r>
        <w:rPr/>
        <w:t>$escapedTitle</w:t>
      </w:r>
    </w:p>
    <w:p>
      <w:r>
        <w:rPr/>
        <w:t xml:space="preserve">$escapedHtml</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>''';

    // 构建 ZIP 文件
    final entries = <String, List<int>>{
      '[Content_Types].xml': utf8.encode(contentTypes),
      '_rels/.rels': utf8.encode(rels),
      'word/_rels/document.xml.rels': utf8.encode(wordRels),
      'word/document.xml': utf8.encode(documentXml),
    };

    return _createZip(entries);
  }

  /// 导出 EPUB 电子书
  Future<void> _exportEpub() async {
    try {
      final title = _titleCtrl.text.isNotEmpty ? _titleCtrl.text : 'untitled';
      final safeTitle = _safeTitle(title);
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出 EPUB 文件',
        fileName: '$safeTitle.epub',
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );
      if (result == null) return;

      final epubBytes = _buildEpubZip(title);
      final file = File(result);
      await file.writeAsBytes(epubBytes);
      if (mounted) _showToast('EPUB 已导出到: $result');
    } catch (e) {
      if (mounted) _showToast('EPUB 导出失败: $e');
    }
  }

  /// 构建 EPUB ZIP 文件
  Uint8List _buildEpubZip(String title) {
    final escapedTitle = _escapeXml(title);
    final fullHtml = _mdToHtml(_contentCtrl.text, title);
    // 提取 body 中的内容（去掉外层 HTML 模板）
    final bodyMatch = RegExp(r'<body>\n?(.*)\n?</body>', dotAll: true).firstMatch(fullHtml);
    final htmlContent = bodyMatch?.group(1) ?? fullHtml;
    final now = DateTime.now().toUtc().toIso8601String();
    final uuid = DateTime.now().millisecondsSinceEpoch.toRadixString(16);

    // mimetype 文件（必须无压缩，且是 ZIP 的第一个条目）
    const mimetype = 'application/epub+zip';

    // META-INF/container.xml
    const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

    // OEBPS/content.opf
    final contentOpf = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">urn:uuid:$uuid</dc:identifier>
    <dc:title>$escapedTitle</dc:title>
    <dc:creator>Hexo Editor</dc:creator>
    <dc:language>zh-CN</dc:language>
    <dc:date>$now</dc:date>
    <meta property="dcterms:modified">$now</meta>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="chapter1"/>
  </spine>
</package>''';

    // OEBPS/toc.ncx
    final tocNcx = '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="urn:uuid:$uuid"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>$escapedTitle</text>
  </docTitle>
  <navMap>
    <navPoint id="navpoint-1" playOrder="1">
      <navLabel>
        <text>$escapedTitle</text>
      </navLabel>
      <content src="chapter1.xhtml"/>
    </navPoint>
  </navMap>
</ncx>''';

    // OEBPS/chapter1.xhtml
    final chapterXhtml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN">
<head>
  <meta charset="UTF-8"/>
  <title>$escapedTitle</title>
  <style>
    body { font-family: serif; max-width: 100%; margin: 0; padding: 1em; line-height: 1.8; }
    h1 { font-size: 2em; }
    h2 { font-size: 1.5em; }
    h3 { font-size: 1.2em; }
    pre { background: #f5f5f5; padding: 1em; white-space: pre-wrap; }
    code { font-family: monospace; }
    blockquote { border-left: 4px solid #ddd; margin: 0; padding: 0 1em; color: #666; }
    img { max-width: 100%; height: auto; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 8px; }
  </style>
</head>
<body>
<h1>$escapedTitle</h1>
$htmlContent
</body>
</html>''';

    // 构建 ZIP（mimetype 必须是第一个且不压缩）
    final entries = <String, List<int>>{
      'mimetype': utf8.encode(mimetype),
      'META-INF/container.xml': utf8.encode(containerXml),
      'OEBPS/content.opf': utf8.encode(contentOpf),
      'OEBPS/toc.ncx': utf8.encode(tocNcx),
      'OEBPS/chapter1.xhtml': utf8.encode(chapterXhtml),
    };

    return _createZip(entries);
  }

  /// 转义 XML 特殊字符
  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// 转义 XML body 中的特殊字符（在纯文本片段中）
  String _escapeXmlBody(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// 创建一个简单的 ZIP 文件（存储模式，无压缩）
  /// 用于生成 DOCX / EPUB 等基于 ZIP 的格式
  Uint8List _createZip(Map<String, List<int>> entries) {
    final buffer = BytesBuilder();
    final localHeaders = <int>[];
    final centralDir = BytesBuilder();

    int offset = 0;

    for (final entry in entries.entries) {
      final name = entry.key;
      final data = entry.value;
      final nameBytes = utf8.encode(name);
      final crc = _crc32(data);
      final compressedSize = data.length;
      final uncompressedSize = data.length;

      // 本地文件头
      localHeaders.add(offset);
      final localHeader = _buildLocalFileHeader(
        nameBytes, crc, compressedSize, uncompressedSize,
      );
      buffer.add(localHeader);
      buffer.add(data);
      offset += localHeader.length + data.length;

      // 中央目录条目
      final cdEntry = _buildCentralDirectoryEntry(
        nameBytes, crc, compressedSize, uncompressedSize, localHeaders.last,
      );
      centralDir.add(cdEntry);
    }

    final centralDirBytes = centralDir.takeBytes();
    final centralDirOffset = buffer.length;
    buffer.add(centralDirBytes);

    // EOCD 记录
    final eocd = _buildEocd(
      entries.length, centralDirBytes.length, centralDirOffset,
    );
    buffer.add(eocd);

    return buffer.takeBytes().buffer.asUint8List();
  }

  List<int> _buildLocalFileHeader(
    List<int> nameBytes, int crc, int compSize, int uncompSize,
  ) {
    final buffer = BytesBuilder();
    buffer.add(_u32(0x04034b50)); // 签名
    buffer.add(_u16(20)); // 提取版本
    buffer.add(_u16(0)); // 通用标志（无压缩）
    buffer.add(_u16(0)); // 压缩方法（存储）
    buffer.add(_u16(0)); // 最后修改时间
    buffer.add(_u16(0)); // 最后修改日期
    buffer.add(_u32(crc)); // CRC-32
    buffer.add(_u32(compSize)); // 压缩后大小
    buffer.add(_u32(uncompSize)); // 原始大小
    buffer.add(_u16(nameBytes.length)); // 文件名长度
    buffer.add(_u16(0)); // 额外字段长度
    buffer.add(nameBytes);
    return buffer.takeBytes();
  }

  List<int> _buildCentralDirectoryEntry(
    List<int> nameBytes, int crc, int compSize, int uncompSize, int localOffset,
  ) {
    final buffer = BytesBuilder();
    buffer.add(_u32(0x02014b50)); // 签名
    buffer.add(_u16(20)); // 创建版本
    buffer.add(_u16(20)); // 提取版本
    buffer.add(_u16(0)); // 通用标志
    buffer.add(_u16(0)); // 压缩方法
    buffer.add(_u16(0)); // 最后修改时间
    buffer.add(_u16(0)); // 最后修改日期
    buffer.add(_u32(crc)); // CRC-32
    buffer.add(_u32(compSize)); // 压缩后大小
    buffer.add(_u32(uncompSize)); // 原始大小
    buffer.add(_u16(nameBytes.length)); // 文件名长度
    buffer.add(_u16(0)); // 额外字段长度
    buffer.add(_u16(0)); // 文件注释长度
    buffer.add(_u16(0)); // 磁盘号起始
    buffer.add(_u16(0)); // 内部文件属性
    buffer.add(_u32(0)); // 外部文件属性
    buffer.add(_u32(localOffset)); // 本地文件头偏移
    buffer.add(nameBytes);
    return buffer.takeBytes();
  }

  List<int> _buildEocd(int entryCount, int cdSize, int cdOffset) {
    final buffer = BytesBuilder();
    buffer.add(_u32(0x06054b50)); // 签名
    buffer.add(_u16(0)); // 当前磁盘号
    buffer.add(_u16(0)); // 中央目录起始磁盘号
    buffer.add(_u16(entryCount)); // 当前磁盘条目数
    buffer.add(_u16(entryCount)); // 总条目数
    buffer.add(_u32(cdSize)); // 中央目录大小
    buffer.add(_u32(cdOffset)); // 中央目录偏移
    buffer.add(_u16(0)); // 注释长度
    return buffer.takeBytes();
  }

  List<int> _u16(int value) {
    return [(value) & 0xFF, (value >> 8) & 0xFF];
  }

  List<int> _u32(int value) {
    return [(value) & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF, (value >> 24) & 0xFF];
  }

  /// 简单的 CRC-32 计算
  int _crc32(List<int> data) {
    int crc = 0xFFFFFFFF;
    // CRC-32 查找表
    const table = [
      0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
      0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
      0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
      0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
      0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
      0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
      0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
      0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
      0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
      0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
      0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
      0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
      0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
      0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
      0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
      0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
      0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
      0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
      0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
      0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
      0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
      0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
      0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
      0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB30A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
      0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
      0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
      0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
      0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
      0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
      0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
      0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
      0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D,
    ];
    for (final byte in data) {
      crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

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
          title: Row(children: [
            const Icon(Icons.folder_open, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('工作区: ${folderPath.split('/').last}', style: const TextStyle(fontSize: 15))),
          ]),
          content: SizedBox(
            width: 500,
            height: 400,
            child: mdFiles.isEmpty
                ? const Center(child: Text('该文件夹中没有找到 .md 文件', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: mdFiles.length,
                    itemBuilder: (_, i) {
                      final file = mdFiles[i] as File;
                      final relativePath = file.path.substring(folderPath.length + 1);
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.article_outlined, size: 18),
                        title: Text(relativePath.replaceAll('.md', ''), style: const TextStyle(fontSize: 13)),
                        subtitle: Text(relativePath, style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
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
      final currentPath = _currentArticle.remotePath;
      if (currentPath == null || currentPath.isEmpty) {
        if (mounted) _showToast('当前文章未关联文件，无法重命名');
        return;
      }

      final currentFile = File(currentPath);
      if (!await currentFile.exists()) {
        if (mounted) _showToast('文件不存在，无法重命名');
        return;
      }

      final oldName = currentPath.split('/').last.replaceAll(RegExp(r'\.md$'), '');
      final nameCtrl = TextEditingController(text: oldName);

      if (!mounted) return;
      final newName = await showDialog<String>(
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              child: const Text('重命名'),
            ),
          ],
        ),
      );

      if (newName == null || newName.isEmpty || newName == oldName) return;

      // 清理文件名
      final safeName = newName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final dirPath = currentPath.substring(0, currentPath.lastIndexOf('/'));
      final newPath = '$dirPath/$safeName.md';

      // 检查目标文件是否已存在
      if (File(newPath).existsSync()) {
        if (mounted) _showToast('目标文件已存在，请使用其他名称');
        return;
      }

      await currentFile.rename(newPath);

      // 更新当前文章路径
      _currentArticle = _currentArticle.copyWith(remotePath: newPath);
      if (mounted) {
        setState(() {});
        _showToast('文件已重命名为: $safeName.md');
      }
    } catch (e) {
      if (mounted) _showToast('重命名失败: $e');
    }
  }

  /// 移动当前文件到指定目录
  Future<void> _moveCurrentFile() async {
    try {
      final currentPath = _currentArticle.remotePath;
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
      _currentArticle = _currentArticle.copyWith(remotePath: newPath);
      if (mounted) {
        setState(() {});
        _showToast('文件已移动到: $newPath');
      }
    } catch (e) {
      if (mounted) _showToast('移动文件失败: $e');
    }
  }

  // ============================================================
  // 站点切换
  // ============================================================

  void _switchSite(RepoConfig repo) async {
    await _updateSettings(settings.copyWith(activeRepoId: repo.id));
    _editorRepo = repo;
    if (mounted) {
      setState(() {});
      _showToast('已切换到: ${repo.name}');
    }
  }

  // ============================================================
  // 布局交互
  // ============================================================

  void _toggleLeftPanel() {
    setState(() {
      _leftPanelExpanded = !_leftPanelExpanded;
      if (_leftPanelExpanded && _workMode == WorkMode.focus) _workMode = WorkMode.workspace;
    });
  }

  void _toggleRightDrawer() => setState(() => _rightDrawerOpen = !_rightDrawerOpen);

  void _openRightDrawer(RightDrawerTab tab) {
    setState(() { _activeDrawerTab = tab; _rightDrawerOpen = true; });
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : _themeMode == ThemeMode.dark ? ThemeMode.system : ThemeMode.light;
    });
  }

  void _switchWorkMode(WorkMode mode) {
    setState(() {
      _workMode = mode;
      switch (mode) {
        case WorkMode.workspace:
          _leftPanelExpanded = true;
          _rightDrawerOpen = false;
          break;
        case WorkMode.focus:
          _leftPanelExpanded = false;
          _rightDrawerOpen = false;
          break;
        case WorkMode.source:
          break;
      }
    });
  }

  void _handleSync() async {
    _syncLogs.add('[${DateTime.now().toString().substring(11, 19)}] 开始同步...');
    setState(() {});
    await _autoSyncToCloud();
    _syncLogs.add('[${DateTime.now().toString().substring(11, 19)}] 同步完成');
    setState(() {});
    _showToast('同步完成');
  }

  // ============================================================
  // 构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return DragToMoveArea(
      child: Stack(
        children: [
          Column(
        children: [
          // ── 顶部标题栏（专注模式下极简） ──
          if (_workMode != WorkMode.focus)
            DesktopTitleBar(
              onToggleLeftPanel: _toggleLeftPanel,
              onToggleRightDrawer: _toggleRightDrawer,
              onThemeToggle: _toggleTheme,
              onSync: _handleSync,
              onPublish: _handlePublish,
              onAi: () => _openRightDrawer(RightDrawerTab.aiChat),
              onOpenFile: _openFileDialog,
              onNewArticle: _newArticle,
              siteName: activeRepo?.name ?? settings.siteName,
              repos: repos,
              onSiteChange: _switchSite,
              hasUnsavedChanges: _hasUnsavedChanges,
            )
          else
            _focusModeTitleBar(),

          // ── 主体三栏 ──
          Expanded(
            child: _workMode == WorkMode.focus ? _buildFocusEditor() : Row(
              children: [
                // 左侧导航面板（可折叠）
                if (_leftPanelExpanded)
                  DesktopLeftPanel(
                    width: _leftPanelWidth,
                    onResize: (w) => setState(() => _leftPanelWidth = w),
                    onOpenDraft: (id) {
                      final article = drafts.firstWhere((a) => a.id == id, orElse: () => _currentArticle);
                      _openExistingArticle(article);
                    },
                    onCollapse: _toggleLeftPanel,
                    repos: repos,
                    drafts: drafts,
                    siteManager: siteManager,
                    onNewArticle: _newArticle,
                    onOpenDrafts: _openDrafts,
                    onOpenRemote: _openRemote,
                    onOpenSync: _openSyncStatus,
                    onOpenDashboard: _openDashboard,
                    onOpenHistory: _openHistory,
                    onOpenRss: _openRss,
                    onOpenBatchUpload: _openBatchUpload,
                    onOpenPreview: _openPreview,
                    onOpenSettings: _openSettings,
                    onOpenSyncSettings: _openSyncSettings,
                    onOpenLogs: _openLogs,
                    onOpenThemeMigration: _openThemeMigration,
                    onShowTemplateManager: _showTemplateManager,
                    onShowSnippetManager: _showSnippetManager,
                    onShowConfigEditor: _showConfigEditor,
                    onShowAiArticleChat: _showAiArticleChat,
                    onShowAiPageChat: _showAiPageChat,
                    onShowAiThemeChat: _showAiThemeChat,
                    onShowAiAudit: _showAiAudit,
                    onShowAiModelManager: _showAiModelManager,
                    onShowToolLibrary: _showToolLibrary,
                    onShowBlogSiteManager: _showBlogSiteManager,
                    onShowSiteEditor: _showSiteEditor,
                    onSiteChange: _switchSite,
                    onShowHelp: _showHelpDialog,
                    onOpenRecycleBin: _openRecycleBin,
                    onOpenImageBedManager: _openImageBedManager,
                    onOpenProxySettings: _openProxySettings,
                    onOpenCacheCleanup: _openCacheCleanup,
                    onExportLogs: _exportLogs,
                    onFixEncoding: _fixEncoding,
                    onToggleOfflineMode: _toggleOfflineMode,
                    onToggleNightEye: _toggleNightEyeProtection,
                    onOpenLinkChecker: _openLinkChecker,
                    onOpenBatchTools: _openBatchTools,
                    onOpenAiPromptTemplates: _openAiPromptTemplates,
                  ),

                if (!_leftPanelExpanded) _collapseToggle(),

                // 中央编辑区域
                Expanded(
                  child: DesktopEditorArea(
                    tabs: _openTabs,
                    activeIndex: _activeTabIndex,
                    workMode: _workMode,
                    onTabChange: (i) => setState(() => _activeTabIndex = i),
                    onTabClose: _closeTab,
                  ),
                ),

                // 右侧悬浮抽屉
                if (_rightDrawerOpen)
                  DesktopRightDrawer(
                    activeTab: _activeDrawerTab,
                    onTabChange: (t) => setState(() => _activeDrawerTab = t),
                    onClose: () => setState(() => _rightDrawerOpen = false),
                    outlineItems: parseOutline(_contentCtrl.text),
                    titleCtrl: _titleCtrl,
                    tagsCtrl: _tagsCtrl,
                    categoriesCtrl: _categoriesCtrl,
                    coverCtrl: _coverCtrl,
                    syncLogs: _syncLogs,
                  ),
              ],
            ),
          ),

          // ── 底部状态栏（专注模式下隐藏） ──
          if (_workMode != WorkMode.focus)
            DesktopStatusBar(
              workMode: _workMode,
              onModeChange: _switchWorkMode,
              editorStatus: _editorStatus,
              cursorPosition: _cursorPos,
              wordCount: _wordCount,
              charCount: _charCount,
              siteName: activeRepo?.name ?? settings.siteName,
              isSyncing: false,
            ),
        ],
      ),
      // 夜间护眼滤镜
      if (settings.nightEyeProtection)
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: Color.fromRGBO(255, 200, 100, settings.nightEyeIntensity * 0.3),
            ),
          ),
        ),
        ],
      ),
    );
  }

  // ============================================================
  // 专注模式（写字模式）
  // ============================================================

  Widget _focusModeTitleBar() {
    return Container(
      height: 32,
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Text(
            _titleCtrl.text.isNotEmpty ? _titleCtrl.text : '未命名文章',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.save, size: 16),
            onPressed: _saveLocal,
            tooltip: '保存',
          ),
          IconButton(
            icon: const Icon(Icons.publish, size: 16),
            onPressed: _handlePublish,
            tooltip: '发布',
          ),
          IconButton(
            icon: const Icon(Icons.close_fullscreen, size: 16),
            onPressed: () => _switchWorkMode(WorkMode.workspace),
            tooltip: '退出专注模式',
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildFocusEditor() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            // 标题输入
            TextField(
              controller: _titleCtrl,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: _currentEditorTheme.headingColor,
                fontFamily: _resolveFontFamily(_editorFontFamily),
              ),
              decoration: const InputDecoration(
                hintText: '在此输入标题...',
                border: InputBorder.none,
              ),
              onChanged: (_) => _onContentChanged(),
            ),
            const SizedBox(height: 24),
            // 内容编辑区（专注模式：左侧编辑 + 右侧实时预览）
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Scrollbar(
                      controller: _focusScrollCtrl,
                      child: SingleChildScrollView(
                        controller: _focusScrollCtrl,
                        child: SizedBox(
                          height: _contentCtrl.text.split('\n').length * (_editorFontSize * _editorLineHeight) + 400,
                          child: TextField(
                            controller: _contentCtrl,
                            maxLines: null,
                            expands: true,
                            style: TextStyle(
                              fontSize: _editorFontSize,
                              height: _editorLineHeight,
                              color: _currentEditorTheme.textColor,
                              fontFamily: _resolveFontFamily(_editorFontFamily),
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: '开始写作...',
                            ),
                            onChanged: (_) => _onContentChanged(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, color: Colors.grey.shade200),
                  Expanded(
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: _buildMarkdownPreview(_contentCtrl.text),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collapseToggle() {
    return GestureDetector(
      onTap: _toggleLeftPanel,
      child: Container(
        width: 4,
        color: Colors.grey.shade300,
        child: Center(child: Icon(Icons.chevron_right, size: 12, color: Colors.grey.shade500)),
      ),
    );
  }
}

// ============================================================
// 辅助数据类
// ============================================================

/// 命令面板条目
class _CommandItem {
  final String label;
  final String shortcut;
  final IconData icon;
  final VoidCallback action;

  const _CommandItem(this.label, this.shortcut, this.icon, this.action);
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

/// Markdown 特殊块（代码块、Mermaid、LaTeX）
class _SpecialBlock {
  final int start;
  final int end;
  final String type; // 'code', 'mermaid', 'latex'
  final String content;
  final String? lang;

  const _SpecialBlock(this.start, this.end, this.type, this.content, {this.lang});
}

// ============================================================
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 2),
          Text(tip, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
        ]),
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 80,
          child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        ),
        Expanded(child: Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
      ]),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(content, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5)),
        ]),
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
    final snapshots = await widget.versionSnapshotService.getSnapshots(widget.articleId);
    if (mounted) setState(() { _snapshots = snapshots.reversed.toList(); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.history, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text('版本历史 — ${widget.articleTitle}', style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis)),
      ]),
      content: SizedBox(
        width: 700,
        height: 500,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _snapshots == null || _snapshots!.isEmpty
                ? const Center(child: Text('暂无版本快照', style: TextStyle(color: Colors.grey)))
                : Row(
                    children: [
                      SizedBox(
                        width: 220,
                        child: ListView.builder(
                          itemCount: _snapshots!.length,
                          itemBuilder: (_, i) {
                            final s = _snapshots![i];
                            final isSelected = _previewId == s.id;
                            final time = '${s.createdAt.month.toString().padLeft(2, '0')}-${s.createdAt.day.toString().padLeft(2, '0')} ${s.createdAt.hour.toString().padLeft(2, '0')}:${s.createdAt.minute.toString().padLeft(2, '0')}';
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              title: Text(time, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                              subtitle: Text('${s.contentLength} 字符', style: const TextStyle(fontSize: 11)),
                              onTap: () async {
                                final content = await widget.versionSnapshotService.getSnapshotContent(widget.articleId, s.id);
                                if (mounted) setState(() { _previewId = s.id; _previewContent = content ?? ''; });
                              },
                            );
                          },
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _previewContent == null
                            ? const Center(child: Text('点击左侧快照预览', style: TextStyle(color: Colors.grey)))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        _previewContent!,
                                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.5),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
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

  const _DiffLine({required this.type, required this.text, required this.lineNum});
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
  State<_ConflictResolutionDialog> createState() => _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState extends State<_ConflictResolutionDialog> {
  final Map<String, String> _resolutions = {}; // articleId -> 'local' | 'remote'
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
      title: Row(children: [
        const Icon(Icons.compare_arrows, size: 22, color: Colors.orange),
        const SizedBox(width: 8),
        Text('同步冲突 (${_currentIndex + 1}/${widget.conflicts.length})', style: const TextStyle(fontSize: 17)),
      ]),
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
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 18, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '冲突文章: ${currentConflict.title}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
              if (c.localArticleId != null && !_resolutions.containsKey(c.localArticleId)) {
                _resolutions[c.localArticleId!] = 'skip';
              }
            }
            widget.onResolved(_resolutions);
          },
        ),
      ],
    );
  }

  Widget _strategyChip(String value, String label, IconData icon, ColorScheme cs) {
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

  Widget _buildDiffPane(String title, IconData icon, Color color, String content, bool isSelected) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? color : Colors.grey.withOpacity(0.2),
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 14, color: isSelected ? color : Colors.grey),
                const SizedBox(width: 6),
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? color : Colors.grey)),
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
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}