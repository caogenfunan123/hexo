import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'models/ai_profile.dart';
import 'models/app_settings.dart';
import 'models/article.dart';
import 'models/blog_framework.dart';
import 'models/blog_site_config.dart';
import 'models/blog_post.dart';
import 'models/github_token_profile.dart';
import 'models/repo_config.dart';
import 'models/session_state.dart';
import 'models/template_item.dart';
import 'core/ai/ai_model_entity.dart';
import 'core/ai/ai_model_manager.dart';
import 'core/ai/ai_request_dispatcher.dart';
import 'core/ai/ai_self_checker.dart';
import 'core/ai/ai_session_manager.dart';
import 'core/ai/theme_migration_service.dart';
import 'core/template_engine/template_resolver.dart';
import 'screens/ai_article_chat_screen.dart';
import 'screens/ai_audit_screen.dart';
import 'screens/ai_model_manager_screen.dart';
import 'screens/ai_theme_chat_screen.dart';
import 'screens/article_reader_screen.dart';
import 'screens/drafts_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/remote_posts_screen.dart';
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
import 'core/site_manager.dart';
import 'core/repository/blog_repository.dart';
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
import 'services/html_to_markdown.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(HexoApp(initialSettings: loadInitialSettings()));
}

AppSettings loadInitialSettings() {
  try {
    return AppSettings.fromJson({});
  } catch (_) {
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

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  void updateTheme(Color c) {
    setState(() => _settings = _settings.copyWith(themeColor: c.value));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hexo 写作',
      theme: AppTheme.light(seedColor: _settings.themeColor),
      home: RootShell(
          onThemeChanged: updateTheme, initialSettings: _settings),
    );
  }
}

class RootShell extends StatefulWidget {
  final void Function(Color) onThemeChanged;
  final AppSettings initialSettings;
  const RootShell(
      {super.key,
      required this.onThemeChanged,
      required this.initialSettings});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  static const _channel = MethodChannel('hexo/native');
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

  /// 站点管理器：统一管理静态仓库和动态 CMS 站点
  late SiteManager siteManager;

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
  String searchQuery = '';
  List<GitHubSearchHit> githubSearchHits = [];
  bool githubSearchLoading = false;
  String? error;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ── 会话记忆 ──
  SessionState _lastSession = SessionState.empty;
  bool _sessionRestored = false;

  // ── 自动保存 ──
  Timer? _autoSaveTimer;
  Timer? _debounceTimer;
  Timer? _autoSyncTimer; // 云端自动同步
  String _lastSavedContent = '';
  bool _hasUnsavedChanges = false;

  // Editor state
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
  Uint8List? _failedImageBytes; // 缓存上传失败的图片字节

  final FocusNode _contentFocus = FocusNode();

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
    final activeId = settings.effectiveActiveSiteId;
    siteManager = SiteManager(
      staticRepos: repos,
      dynamicSites: settings.blogSiteConfigs,
      appSettings: settings,
      activeSiteId: activeId.isNotEmpty ? activeId : (activeRepo?.id ?? ''),
    );
    // 将站点管理器注入到工具系统
    RemoteCmsTools.siteManager = siteManager;
  }

  String get _pageTitle {
    switch (_currentPage) {
      case 0:
        return '写文章';
      case 1:
        return '草稿';
      case 2:
        return siteManager.isDynamicSite ? '远程文章' : '远程';
      case 3:
        return '仪表盘';
      case 4:
        return 'RSS';
      case 5:
        return '历史';
      case 6:
        return '批量上传';
      case 7:
        return '网站预览';
      case 8:
        return '设置';
      case 9:
        return '阅读';
      case 10:
        return 'AI 主题迁移';
      case 11:
        return '操作日志';
      case 12:
        return '同步状态';
      case 13:
        return '云同步';
      default:
        return '';
    }
  }

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
    siteManager.disposeAll();
    cmsDraftService.close();
    super.dispose();
  }

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
      // 自动解析编辑器默认模板
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
      // 初始化站点管理器（统一管理静态仓库和动态 CMS 站点）
      _updateSiteManager();
      // 会话恢复
      if (s.restoreSession) {
        await _restoreSession();
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
    // 初始化工具系统
    try {
      await skillManager.init(await storage.root);
    } catch (_) {}
    // 初始化云同步后端
    _initCloudSync();
  }

  /// 初始化云同步后端
  void _initCloudSync() async {
    // 初始化设备密钥
    final deviceKey = await storage.loadDeviceKey();
    cloudSyncService.initDeviceKey(deviceKey);

    // 注册 GitHub 后端
    final githubBackend = GitHubSyncBackend(github);
    cloudSyncService.registerBackend(githubBackend);
    // 如果有活跃仓库，自动配置
    if (effectiveRepo != null) {
      githubBackend.configureRepo(effectiveRepo!);
    }

    // 注册 WebDAV 后端
    final webdavBackend = WebDavSyncBackend();
    webdavBackend.configureFromSettings(settings);
    cloudSyncService.registerBackend(webdavBackend);

    // 启动自动同步
    _startAutoSync();

    // 如果后端已配置，启动后自动拉取一次
    if (cloudSyncService.hasConfiguredBackend) {
      _autoPullFromCloud();
    }
  }

  /// 启动云端自动同步定时器
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

  // ── 生命周期感知同步 ──

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // 进入后台：推送当前数据
      _autoSyncToCloud();
    } else if (state == AppLifecycleState.resumed) {
      // 回到前台：拉取最新数据
      _autoPullFromCloud();
    }
  }

  /// 自动同步到云端（推送）
  Future<void> _autoSyncToCloud() async {
    if (busy) return;
    final backend = cloudSyncService.configuredBackends.firstOrNull;
    if (backend == null) return;

    try {
      await cloudSyncService.pushDrafts(backend, drafts);
      await cloudSyncService.pushSyncMappings(backend, syncService);
    } catch (_) {}
  }

  /// 自动从云端拉取（后台静默，不弹 toast）
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

  AppSettings _ensureGithubTokensFromLegacy(
      AppSettings s, List<RepoConfig> repos) {
    var tokens = List<GithubTokenProfile>.from(s.githubTokens);
    bool changed = false;
    if (s.defaultToken.isNotEmpty &&
        !tokens.any((t) => t.token == s.defaultToken)) {
      tokens.add(GithubTokenProfile(
          id: 'legacy_token', name: '默认 Token', token: s.defaultToken));
      changed = true;
    }
    for (final r in repos) {
      if (r.token.isNotEmpty && !tokens.any((t) => t.token == r.token)) {
        tokens.add(GithubTokenProfile(
            id: 'repo_${r.id}', name: r.name, token: r.token));
        changed = true;
      }
    }
    if (changed) {
      final seen = <String>{};
      tokens = tokens.where((t) => seen.add(t.token.trim())).toList();
      return s.copyWith(
          githubTokens: tokens, activeGithubTokenId: tokens.first.id);
    }
    return s;
  }

  void _navigateTo(int page) {
    // 离开编辑器时停止自动保存
    if (_currentPage == 0 && page != 0) {
      _stopAutoSave();
    }
    setState(() => _currentPage = page);
    // 仅在抽屉打开时才关闭抽屉，避免对根路由执行无意义的 pop
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
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
      _lastSession = session;

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
    } catch (_) {}
  }

  Future<void> _saveSession(SessionPageType pageType) async {
    if (!settings.restoreSession) return;
    final state = SessionState(
      pageType: pageType,
      articleId: _currentArticle.id,
      articleSource: ArticleSource.local,
      articleTitle: _titleCtrl.text,
      articleContent: _contentCtrl.text,
      articleTags: _tagsCtrl.text,
      articleCategories: _categoriesCtrl.text,
      articleCover: _coverCtrl.text,
      articleRepoId: _currentArticle.repoId ?? '',
      articleRemotePath: _currentArticle.remotePath ?? '',
      articleRemoteSha: _currentArticle.remoteSha ?? '',
    );
    _lastSession = state;
    await sessionService.saveSession(state);
  }

  Future<void> _clearSession() async {
    _lastSession = SessionState.empty;
    await sessionService.clearSession();
  }

  // ============ 退出弹窗 ============

  Future<bool> _showExitDialog() async {
    final hasChanges = _hasUnsavedChanges;
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
    _articleType = 'post';
    // 自动解析仓库默认模板（重置后默认文章类型）
    String? autoTemplateId;
    if (repo != null) {
      autoTemplateId = TemplateResolver.resolvePostTemplateId(repo, templates);
    }
    _currentArticle = Article(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: '',
      content: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDraft: true,
      repoId: repo?.id,
      articleType: _articleType,
      templateId: autoTemplateId,
    );
    _titleCtrl.text = '';
    _contentCtrl.text = '';
    _tagsCtrl.text = '';
    _categoriesCtrl.text = '';
    _coverCtrl.text = '';
    _lastSavedContent = '';
    _hasUnsavedChanges = false;
    _selectedTemplateId = autoTemplateId;
  }

  /// 根据当前文章类型和仓库配置自动选择模板
  void _autoSelectTemplate() {
    final repo = _editorRepo;
    if (repo == null) return;
    _selectedTemplateId = _articleType == 'post'
        ? TemplateResolver.resolvePostTemplateId(repo, templates)
        : TemplateResolver.resolvePageTemplateId(repo, templates);
  }

  // ============ 自动保存 ============

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
    // 防抖：停止输入后延时保存
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      _autoSaveSnapshot();
    });
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
      // 同时保存草稿到 storage
      await _saveDraft(_collect(draft: true));
      if (mounted) {
        _showToast('草稿已自动保存');
      }
    } catch (_) {}
  }

  // ============ 阅读页 / 编辑器切换 ============

  void _openReader(Article article) {
    _currentArticle = article;
    _titleCtrl.text = article.title;
    _contentCtrl.text = article.content;
    _tagsCtrl.text = article.tags.join(', ');
    _categoriesCtrl.text = article.categories.join(', ');
    _coverCtrl.text = article.cover ?? '';
    _lastSavedContent = article.content;
    _hasUnsavedChanges = false;
    _saveSession(SessionPageType.reader);
    setState(() => _currentPage = 9); // 阅读页
  }

  void _enterEditorFromReader(Article article) {
    _currentArticle = article;
    _titleCtrl.text = article.title;
    _contentCtrl.text = article.content;
    _tagsCtrl.text = article.tags.join(', ');
    _categoriesCtrl.text = article.categories.join(', ');
    _coverCtrl.text = article.cover ?? '';
    _editorRepo = repos
            .where((r) => r.id == article.repoId)
            .firstOrNull ??
        activeRepo;
    _lastSavedContent = article.content;
    _hasUnsavedChanges = false;
    _startAutoSave();
    _saveSession(SessionPageType.editor);
    setState(() => _currentPage = 0); // 回到编辑器
  }

  // --- Editor methods ---
  Article _collect({bool draft = true}) {
    final cover = _coverCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    return _currentArticle.copyWith(
      title: title.isEmpty ? '未命名' : title,
      content: _contentCtrl.text,
      tags: _tagsCtrl.text
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      categories: _categoriesCtrl.text
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
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

  Future<void> _saveLocal() async {
    final a = _collect(draft: true);
    setState(() {
      _currentArticle = a;
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
    _lastSavedContent = a.content;
    _hasUnsavedChanges = false;
    logService.add('保存草稿', '标题: ${a.title.isNotEmpty ? a.title : "(无标题)"}');
    if (mounted) _showToast('草稿已保存到本地');
  }

  Future<void> _publish() async {
    // ── 发布确认对话框 ──
    final publishTarget = siteManager.isDynamicSite
        ? siteManager.currentBlogType.displayName
        : (_resolvedRepo?.fullName ?? 'GitHub');
    bool saveMdBackup = false;

    final confirmed = await showDialog<bool>(
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
                '标题: ${_titleCtrl.text.isNotEmpty ? _titleCtrl.text : "(无标题)"}',
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
            ],
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
      ),
    );

    if (confirmed != true || !mounted) return;

    // ── 保存 MD 备份 ──
    if (saveMdBackup) {
      await _saveMdBackup();
    }

    // 动态 CMS 站点：推送到远程 CMS
    if (siteManager.isDynamicSite) {
      await _publishToCms();
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
      final pub = await github.upsertArticle(repo, a);
      setState(() {
        _currentArticle = pub;
        _editorStatus = '已发布';
      });
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
      final isUpdate = _currentArticle.remoteSha != null;
      _editorStatus = isUpdate
          ? '正在更新到 ${adapter.config.type.displayName}...'
          : '正在发布到 ${adapter.config.type.displayName}...';
    });
    try {
      // 从 remoteSha 中提取远程文章 ID（加载远程文章时记录）
      final remoteId = _currentArticle.remoteSha != null
          ? int.tryParse(_currentArticle.remoteSha!)
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
        try {
          if (attempts > 1) {
            final action = remoteId != null ? '更新' : '发布';
            setState(() => _editorStatus = '正在重试$action (第 $attempts 次)...');
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
          setState(() => _editorStatus = '发布失败，${2 * attempts}s 后重试...');
          await Future.delayed(Duration(seconds: 2 * attempts));
          _publishCancelToken.throwIfCancelled();
        } catch (e) {
          if (e is CancelledException) rethrow;
          // 网络错误等其他异常，也尝试重试
          if (attempts >= maxRetries) rethrow;
          setState(() => _editorStatus = '网络异常，${2 * attempts}s 后重试...');
          await Future.delayed(Duration(seconds: 2 * attempts));
          _publishCancelToken.throwIfCancelled();
        }
      }
      final finalResult = result!;
      final isUpdate = remoteId != null;
      // 更新本地文章状态，记录远程 ID
      final pub = a.copyWith(
        isDraft: false,
        published: true,
        remotePath: finalResult.link,
        remoteSha: finalResult.id?.toString(),
      );
      setState(() {
        _currentArticle = pub;
        _editorStatus = isUpdate
            ? '已更新到 ${adapter.config.type.displayName}'
            : '已发布到 ${adapter.config.type.displayName}';
      });
      _lastSavedContent = a.content;
      _hasUnsavedChanges = false;
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
      setState(() => _editorStatus = '发布失败');
      logService.add('CMS发布失败', e.message, success: false);
      if (mounted) _showToast('发布失败: ${e.message}');
    } on CancelledException {
      setState(() => _editorStatus = '已取消发布');
      logService.add('发布已取消', '用户取消了发布操作');
      if (mounted) _showToast('发布已取消');
    } catch (e) {
      setState(() => _editorStatus = '发布失败');
      logService.add('CMS发布失败', '$e', success: false);
      if (mounted) _showToast('发布失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
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

  void _insertText(String t) {
    final sel = _contentCtrl.selection;
    final txt = _contentCtrl.text;
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(s, e, t),
        selection: TextSelection.collapsed(offset: s + t.length));
    _contentFocus.requestFocus();
  }

  void _wrap(String l, String r, {String p = ''}) {
    final sel = _contentCtrl.selection;
    final txt = _contentCtrl.text;
    if (!sel.isValid || sel.start == sel.end) {
      final body = p.isEmpty ? '' : p;
      final ins = '$l$body$r';
      final s = sel.isValid ? sel.start : txt.length;
      _contentCtrl.value = TextEditingValue(
          text: txt.replaceRange(s, s, ins),
          selection:
              TextSelection.collapsed(offset: s + l.length + body.length));
      _contentFocus.requestFocus();
      return;
    }
    final sel2 = txt.substring(sel.start, sel.end);
    _contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(sel.start, sel.end, '$l$sel2$r'),
        selection: TextSelection.collapsed(
            offset: sel.start + l.length + sel2.length));
    _contentFocus.requestFocus();
  }

  void _insertHeading(int level) {
    final prefix = '${'#' * level} ';
    final txt = _contentCtrl.text;
    final s = _contentCtrl.selection.isValid
        ? _contentCtrl.selection.start
        : txt.length;
    final lineStart = txt.lastIndexOf('\n', s - 1) + 1;
    _contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(lineStart, lineStart, prefix),
        selection: TextSelection.collapsed(offset: s + prefix.length));
    _contentFocus.requestFocus();
  }

  void _insertList(String marker) {
    final sel = _contentCtrl.selection;
    if (sel.isValid && sel.start != sel.end) {
      final selected = _contentCtrl.text.substring(sel.start, sel.end);
      final lines = selected
          .split('\n')
          .map((l) => l.isEmpty ? l : '$marker$l')
          .join('\n');
      final txt = _contentCtrl.text;
      _contentCtrl.value = TextEditingValue(
          text: txt.replaceRange(sel.start, sel.end, lines),
          selection: TextSelection.collapsed(offset: sel.start + lines.length));
      _contentFocus.requestFocus();
      return;
    }
    _insertText('\n$marker');
  }

  void _insertCodeBlock() {
    final sel = _contentCtrl.selection;
    final txt = _contentCtrl.text;
    final selected = (sel.isValid && sel.start != sel.end)
        ? txt.substring(sel.start, sel.end)
        : '';
    final fence = '```\n$selected\n```\n';
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _contentCtrl.value = TextEditingValue(
        text: txt.replaceRange(s, e, fence),
        selection: TextSelection.collapsed(offset: s + 4));
    _contentFocus.requestFocus();
  }

  Future<void> _insertImage() async {
    setState(() {
      _editorBusy = true;
      _editorStatus = '正在选择图片...';
    });
    try {
      final bytes = await imageService.pickImageBytes();
      if (bytes == null) {
        setState(() => _editorStatus = '已取消');
        return;
      }
      _failedImageBytes = bytes; // 缓存以备重试
      final sizeKB = (bytes.length / 1024).toStringAsFixed(1);
      setState(() => _editorStatus = '正在上传图片 ($sizeKB KB)...');
      final url = await imageService.uploadToImageBed(bytes, settings);
      _insertText(imageService.markdownImage(url));
      _failedImageBytes = null; // 清除失败缓存
      setState(() => _editorStatus = '图片已插入');
    } catch (e) {
      // 缓存失败图片字节，插入重试标记
      final retryMark = '\n> ⚠️ 图片上传失败，[点击重试](#retry-upload)\n';
      _insertText(retryMark);
      setState(() => _editorStatus = '上传失败（可点击重试）');
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
        setState(() => _editorStatus = '已取消');
        return;
      }
      final total = bytesList.length;

      // ── 预处理阶段：批量压缩 ──
      setState(() => _editorStatus = '正在预处理 $total 张图片...');
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
        setState(() => _editorStatus = '正在上传图片 ${i + 1}/$total...');
        try {
          final url = await imageService.uploadToImageBed(
            preResult.images[i],
            settings,
            skipCompress: true, // 已预处理，跳过重复压缩
          );
          buf.writeln(imageService.markdownImage(url));
          uploaded++;
        } catch (_) {
          buf.writeln('> ⚠️ 第 ${i + 1} 张图片上传失败');
          failed++;
        }
      }
      _insertText('\n\n${buf.toString()}');
      logService.add('批量上传图片', '成功: $uploaded, 失败: $failed');
      setState(() => _editorStatus = '完成: $uploaded/$total 张上传成功');
    } catch (e) {
      setState(() => _editorStatus = '批量上传失败');
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
    final txt = _contentCtrl.text;
    final retryIdx = txt.indexOf('> ⚠️ 图片上传失败');
    if (retryIdx >= 0) {
      final endIdx = txt.indexOf('\n', txt.indexOf('#retry-upload', retryIdx));
      final removeEnd = endIdx >= 0 ? endIdx + 1 : txt.length;
      _contentCtrl.text = txt.replaceRange(retryIdx, removeEnd, '');
    }

    setState(() {
      _editorBusy = true;
      _editorStatus = '正在重试上传...';
    });
    try {
      final url = await imageService.uploadToImageBed(bytes, settings);
      _insertText(imageService.markdownImage(url));
      _failedImageBytes = null;
      setState(() => _editorStatus = '图片已插入');
    } catch (e) {
      setState(() => _editorStatus = '重试失败');
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
      final text = _contentCtrl.text;
      switch (action) {
        case 'polish':
          result = await aiService.polish(settings, text);
          _contentCtrl.text = result;
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
              _titleCtrl.text.isEmpty ? text : _titleCtrl.text);
          _contentCtrl.text = result;
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
          if (ok != true) break;
          result = await aiService.generateCode(
              settings,
              ctrl.text.trim().isEmpty
                  ? '写一段示例代码'
                  : ctrl.text.trim());
          _insertText('\n\n$result\n');
          break;
        case 'rewrite':
          final sel = _contentCtrl.selection;
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
          if (ok2 != true) break;
          result = await aiService.rewriteSelection(
              settings, selected, instrCtrl.text.trim());
          final txt = _contentCtrl.text;
          _contentCtrl.value = TextEditingValue(
              text: txt.replaceRange(
                  sel.start, sel.end, result),
              selection: TextSelection.collapsed(
                  offset: sel.start + result.length));
          _contentFocus.requestFocus();
          break;
        case 'format':
          result = await aiService.polish(settings,
              '请对以下 Markdown 内容进行排版优化：统一标题层级、规范空行、修正列表缩进、对齐表格格式。\n\n$text');
          _contentCtrl.text = result;
          break;
      }
      setState(() => _editorStatus = 'AI 完成');
    } catch (e) {
      if (mounted) _showToast('AI 失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
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
      remotePosts = await github.listPosts(repo);
    } catch (_) {}
    if (mounted) setState(() => busy = false);
  }

  Future<void> _refreshRss() async {
    final url = activeRepo?.siteUrl.isNotEmpty == true
        ? activeRepo!.siteUrl
        : 'https://caogenfunan.me/';
    try {
      rssItems = await rssService.fetch(url);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _refreshCommits() async {
    final repo = effectiveRepo;
    if (repo == null || repo.token.isEmpty) return;
    try {
      commits = await github.listCommits(repo);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _updateSettings(AppSettings s) async {
    setState(() => settings = s);
    _updateSiteManager();
    _startAutoSync(); // 重启自动同步（间隔/开关可能变化）
    await storage.saveSettings(s);
    widget.onThemeChanged(Color(s.themeColor));
  }

  Future<void> _updateRepos(List<RepoConfig> r) async {
    setState(() => repos = r);
    _updateSiteManager();
    await storage.saveRepos(r);
  }

  Future<void> _persistSettings() => storage.saveSettings(settings);
  Future<void> _persistRepos() => storage.saveRepos(repos);
  Future<void> _persistDrafts() => storage.saveDrafts(drafts);

  /// 保存 MD 备份到本地目录
  Future<void> _saveMdBackup() async {
    try {
      final a = _collect(draft: false);
      final dir = Directory('${await storage.root}/hexo_backups');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
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
      if (mounted) _showToast('MD 备份已保存到 hexo_backups/$fileName');
    } catch (e) {
      if (mounted) _showToast('MD 备份保存失败: $e');
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
              a.toMarkdownWithFrontMatter());
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
    final result = await Navigator.of(context).push<BlogSiteConfig?>(
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
        text: existing?.siteUrl ??
            'https://caogenfunan.me/');
    final token = TextEditingController(
        text: existing?.token.isNotEmpty == true
            ? existing!.token
            : settings.effectiveGithubToken);
    String frameworkId = existing?.frameworkId ?? 'hexo';
    final String originalFrameworkId = existing?.frameworkId ?? 'hexo';
    bool postDatePrefix = existing?.postDatePrefix ?? false;
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

  /// 将 CMS 远程文章加载到编辑器
  void _openRemotePostInEditor(BlogPost post) {
    // 关闭抽屉
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
    // 将 BlogPost 转为 Article 加载到编辑器
    _currentArticle = Article(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: post.title,
      content: post.contentMd,
      tags: post.tags,
      categories: post.categories,
      createdAt: post.date,
      updatedAt: post.modifiedDate,
      isDraft: false,
      published: true,
      articleType: 'post',
      remotePath: post.link,
      remoteSha: post.id?.toString(),
    );
    _titleCtrl.text = post.title;
    _contentCtrl.text = post.contentMd;
    _tagsCtrl.text = post.tags.join(', ');
    _categoriesCtrl.text = post.categories.join(', ');
    _coverCtrl.text = '';
    _editorRepo = null; // CMS 文章不使用 Git 仓库
    _lastSavedContent = post.contentMd;
    _hasUnsavedChanges = false;
    _startAutoSave();
    _saveSession(SessionPageType.editor);
    setState(() => _currentPage = 0);
    logService.add('加载远程文章', '标题: ${post.title}');
    if (mounted) _showToast('已加载远程文章: ${post.title}');
  }

  /// 删除 CMS 远程文章
  Future<void> _deleteRemoteCmsPost(BlogPost post) async {
    final adapter = siteManager.currentAdapter;
    if (adapter == null || post.id == null) return;
    try {
      await adapter.deletePost(post.id!);
      logService.add('删除远程文章', '已从 ${adapter.config.type.displayName} 删除: ${post.title}');
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
      } catch (_) {
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

  // ============ Search ============

  Future<void> _showSearch() async {
    final controller =
        TextEditingController(text: searchQuery);
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全文搜索'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '标题 / 正文 / 标签 / 文件名 / 仓库全文',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 8),
            const Text(
              '本地草稿会按标题/正文/标签过滤；远程文章会再请求 GitHub Code Search 做仓库全文检索。',
              style: TextStyle(
                  fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('清除')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    if (q == null) return;
    final query = q.trim();
    setState(() {
      searchQuery = query;
      if (query.isEmpty) githubSearchHits = [];
    });
    if (query.isNotEmpty) {
      await _runGithubFullTextSearch(query);
    }
  }

  Future<void> _runGithubFullTextSearch(String query) async {
    final repo = effectiveRepo;
    if (repo == null || repo.token.isEmpty) {
      setState(() => githubSearchHits = []);
      return;
    }
    setState(() => githubSearchLoading = true);
    try {
      final hits = await github.searchCode(repo, query);
      if (!mounted) return;
      setState(() => githubSearchHits = hits);
      if (hits.isEmpty) {
        _showToast('GitHub 全文无匹配');
      } else {
        _showToast('GitHub 全文命中 ${hits.length} 个文件');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => githubSearchHits = []);
      _showToast('GitHub 全文搜索失败: $e');
    } finally {
      if (mounted) setState(() => githubSearchLoading = false);
    }
  }

  // ============ Import & PWA ============

  Future<void> _importLocalMd() async {
    try {
      final result =
          await _channel.invokeMethod<Map>('pickFile');
      if (result == null) return;
      final b64 = result['base64']?.toString() ?? '';
      final name =
          result['name']?.toString() ?? 'untitled.md';
      if (b64.isEmpty) return;
      final content = utf8.decode(base64Decode(b64));
      final article = Article.fromMarkdown(content,
          id: DateTime.now().millisecondsSinceEpoch.toString());
      _openExistingArticle(article);
    } catch (e) {
      _showToast('导入失败: $e');
    }
  }

  Future<void> _showPwaGuide() async {
    final site = activeRepo?.siteUrl.isNotEmpty == true
        ? activeRepo!.siteUrl
        : 'https://caogenfunan.me/';
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
        backgroundColor: AppTheme.bg,
        appBar: _buildAppBar(),
        drawer: _buildDrawer(),
        body: _buildPage(),
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
      title: Text(_pageTitle,
          style: const TextStyle(
              color: AppTheme.text,
              fontWeight: FontWeight.w700,
              fontSize: 18)),
      actions: _currentPage == 0
          ? [
              _appBarAction(
                  icon: Icons.close,
                  tooltip: '关闭',
                  onTap: () => _onCloseEditor()),
              _appBarAction(
                  icon: Icons.visibility_outlined,
                  tooltip: '预览文章',
                  onTap: _editorBusy
                      ? null
                      : () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => Scaffold(
                                    backgroundColor: AppTheme.bg,
                                    appBar: AppBar(
                                        title: Text(_titleCtrl
                                                .text.isEmpty
                                            ? '预览'
                                            : _titleCtrl.text)),
                                    body: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Markdown(
                                          data: _contentCtrl.text.isEmpty
                                              ? '*暂无内容*'
                                              : _contentCtrl.text,
                                          selectable: true),
                                    ),
                                  )));
                        }),
              _appBarAction(
                  icon: Icons.save_outlined,
                  tooltip: '保存草稿',
                  onTap: _editorBusy ? null : _saveLocal),
              _appBarAction(
                  icon: Icons.cloud_upload_outlined,
                  tooltip: '发布',
                  color: cs.primary,
                  onTap: _editorBusy ? null : _publish),
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

  // ============ DRAWER ============

  Widget _buildDrawer() {
    final cs = Theme.of(context).colorScheme;
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
                  _drawerSection('创作'),
                  _drawerItem(0, Icons.edit_square, '写文章',
                      isPrimary: true),
                  _drawerItem(1, Icons.drafts_outlined, '草稿箱',
                      badge: drafts.where((d) => !d.published).length),
                  const SizedBox(height: 8),
                  _drawerSection('管理'),
                  _drawerItem(2, Icons.cloud_outlined, '远程文章'),
                  _drawerItem(12, Icons.sync, '同步状态'),
                  _drawerItem(3, Icons.dashboard_outlined, '仪表盘'),
                  _drawerItem(5, Icons.history_outlined, '提交历史'),
                  const SizedBox(height: 8),
                  _drawerSection('工具'),
                  _drawerItem(6, Icons.drive_folder_upload, '批量上传'),
                  _drawerItem(7, Icons.language, '网站预览'),
                  _drawerItem(4, Icons.rss_feed_outlined, 'RSS 订阅'),
                  _drawerAction(Icons.view_quilt_outlined, '模板管理', _showTemplateManager),
                  _drawerAction(Icons.content_paste, '片段素材库', _showSnippetManager),
                  _drawerAction(Icons.settings_applications, '配置编辑器', _showSiteConfigEditor),
                  _drawerAction(Icons.swap_horiz, 'AI批量迁移', _showMigrationTool),
                  const SizedBox(height: 8),
                  _drawerSection('AI 工具'),
                  _drawerAction(Icons.article_outlined, 'AI 博文创作', _showAiArticleChat),
                  _drawerAction(Icons.web_outlined, 'AI 页面创作', _showAiPageChat),
                  _drawerAction(Icons.palette_outlined, 'AI 主题开发', _showAiThemeChat),
                  _drawerItem(10, Icons.auto_fix_high, 'AI 主题迁移'),
                  _drawerAction(Icons.fact_check_outlined, 'AI 站点巡检', _showAiAudit),
                  _drawerAction(Icons.psychology_outlined, 'AI 模型管理', _showAiModelManager),
                  _drawerAction(Icons.build_outlined, '工具库', _showToolLibrary),
                  const SizedBox(height: 8),
                  _drawerSection('系统'),
                  _drawerItem(13, Icons.cloud_sync, '云同步'),
                  _drawerItem(8, Icons.settings_outlined, '设置'),
                  _drawerItem(11, Icons.history, '操作日志'),
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
        if (siteManager.isDynamicSite) {
          final adapter = siteManager.currentAdapter;
          if (adapter == null) {
            return const Center(child: Text('未配置 CMS 站点'));
          }
          return RemotePostsScreen(
            adapter: adapter,
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
        return PreviewScreen(activeRepo: activeRepo);
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
            onShowGithubTokenManager: _showGithubTokenManager,
            onShowRepoManager: _showRepoManager,
            onShowSiteEditor: _showSiteEditor,
            onShowThemeColorPicker: _showThemeColorPicker,
            onShowPwaGuide: _showPwaGuide,
            onPersistSettings: _persistSettings,
            onShowToast: _showToast);
      case 9:
        return ArticleReaderScreen(
          article: _currentArticle,
          onEnterEdit: () => _enterEditorFromReader(_currentArticle),
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
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
            children: [
              // ── 站点切换器 + 类型指示器 ──
              _buildSiteSwitcher(cs),
              const SizedBox(height: 8),
              // ── 仓库选择器（静态站点时显示） ──
              if (repos.isNotEmpty && !siteManager.isDynamicSite)
                _editorCard(
                  child: DropdownButtonFormField<String>(
                    value: _editorRepo?.id,
                    decoration: const InputDecoration(
                      labelText: '目标仓库',
                      prefixIcon: Icon(Icons.storage_outlined,
                          size: 19),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      isDense: true,
                    ),
                    items: repos
                        .map((r) => DropdownMenuItem(
                            value: r.id,
                            child: Text('${r.name} (${r.fullName})',
                                style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) => setState(() =>
                        _editorRepo =
                            repos.firstWhere((e) => e.id == v)),
                  ),
                ),
              const SizedBox(height: 8),
              // ── 文章类型切换 ──
              Row(
                children: [
                  Expanded(
                    child: _editorTypeToggle(
                      icon: Icons.article_outlined,
                      label: '博文',
                      subtitle: _editorRepo != null
                          ? '${_editorRepo!.postsPath}'
                          : '文章目录',
                      active: _articleType == 'post',
                      onTap: () => setState(() {
                        _articleType = 'post';
                        _autoSelectTemplate();
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _editorTypeToggle(
                      icon: Icons.web_outlined,
                      label: '页面',
                      subtitle: _editorRepo != null
                          ? '${_editorRepo!.pagesPath}'
                          : '页面目录',
                      active: _articleType == 'page',
                      onTap: () => setState(() {
                        _articleType = 'page';
                        _autoSelectTemplate();
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // ── 模板选择器 ──
              if (templates.isNotEmpty)
                _editorCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedTemplateId,
                          decoration: InputDecoration(
                            labelText: '模板 (${_articleType == 'post' ? '博文' : '页面'})',
                            prefixIcon: const Icon(Icons.view_quilt_outlined, size: 18),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('无模板', style: TextStyle(fontSize: 13)),
                            ),
                            ...templates
                                .where((t) => t.isPost == (_articleType == 'post'))
                                .map((t) => DropdownMenuItem<String>(
                                      value: t.id,
                                      child: Text(
                                        '${t.isBuiltin ? "[内置] " : ""}${t.name}',
                                        style: const TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )),
                          ],
                          onChanged: (v) => setState(() => _selectedTemplateId = v),
                        ),
                      ),
                      IconButton(
                        tooltip: '设为本仓库默认模板',
                        onPressed: _editorRepo != null && _selectedTemplateId != null
                            ? () => _setAsRepoDefault(_selectedTemplateId!)
                            : null,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                      IconButton(
                        tooltip: '管理模板',
                        onPressed: () => _showTemplateManager(),
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                    ],
                  ),
                ),
              // ── 框架信息 ──
              if (_editorRepo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBAE6FD)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: Color(0xFF0EA5E9)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '框架: ${BlogFramework.byId(_editorRepo!.frameworkId)?.name ?? _editorRepo!.frameworkId} | '
                            '文件名: ${_articleType == 'page' ? '无日期前缀' : (_editorRepo!.fileNameRule.postDatePrefix ? '自动加日期' : '纯标题')}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF0369A1)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // ── 标题 ──
              _editorCard(
                child: TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '文章标题',
                    prefixIcon:
                        Icon(Icons.title, size: 19),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 8),
              // ── 标签 & 分类 ──
              Row(children: [
                Expanded(
                  child: _editorCard(
                    child: TextField(
                      controller: _tagsCtrl,
                      decoration: const InputDecoration(
                        labelText: '标签',
                        prefixIcon:
                            Icon(Icons.tag, size: 18),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _editorCard(
                    child: TextField(
                      controller: _categoriesCtrl,
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
                ),
              ]),
              const SizedBox(height: 8),
              // ── 封面图 ──
              _editorCard(
                child: TextField(
                  controller: _coverCtrl,
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
              const SizedBox(height: 10),
              // ── 工具栏 ──
              _editorCard(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      _toolChip(Icons.format_bold, '粗体',
                          () => _wrap('**', '**', p: '粗体')),
                      _toolChip(Icons.format_italic, '斜体',
                          () => _wrap('*', '*', p: '斜体')),
                      _toolChip(Icons.code, '行内码',
                          () => _wrap('`', '`', p: 'code')),
                      _toolChip(Icons.code_off, '代码块',
                          _insertCodeBlock),
                      _toolChip(Icons.title, 'H1',
                          () => _insertHeading(1)),
                      _toolChip(Icons.title, 'H2',
                          () => _insertHeading(2)),
                      _toolChip(Icons.format_list_bulleted, '列表',
                          () => _insertList('- ')),
                      _toolChip(Icons.format_quote, '引用',
                          () => _insertList('> ')),
                      _toolChip(Icons.link, '链接',
                          () => _wrap('[', '](https://)', p: '链接文字')),
                      _toolChip(Icons.grid_on, '表格',
                          () => _insertText('\n| 列1 | 列2 |\n| --- | --- |\n| 值1 | 值2 |\n')),
                      _toolChip(Icons.horizontal_rule, '分割线',
                          () => _insertText('\n---\n')),
                      _toolChip(Icons.format_strikethrough, '删除线',
                          () => _wrap('~~', '~~', p: '删除文字')),
                      _toolChip(Icons.checklist, '任务',
                          () => _insertList('- [ ] ')),
                      _toolChip(Icons.more_horiz, 'more',
                          () => _insertText('\n<!--more-->\n')),
                      _toolChip(Icons.image_outlined, '图床',
                          _editorBusy ? null : _insertImage),
                      _toolChip(Icons.collections_outlined, '批量图床',
                          _editorBusy ? null : _batchInsertImages),
                      _toolChip(Icons.auto_awesome, 'AI润色',
                          _editorBusy ? null : () => _aiAction('polish'),
                          color: Colors.purple),
                      _toolChip(Icons.edit_note, 'AI续写',
                          _editorBusy ? null : () => _aiAction('continue'),
                          color: Colors.purple),
                      _toolChip(Icons.summarize_outlined, 'AI摘要',
                          _editorBusy ? null : () => _aiAction('summary'),
                          color: Colors.purple),
                      _toolChip(Icons.developer_mode, 'AI代码',
                          _editorBusy ? null : () => _aiAction('code'),
                          color: Colors.purple),
                      _toolChip(Icons.sync_alt, 'AI改写',
                          _editorBusy ? null : () => _aiAction('rewrite'),
                          color: Colors.purple),
                      _toolChip(Icons.auto_fix_high, 'AI排版',
                          _editorBusy ? null : () => _aiAction('format'),
                          color: Colors.deepPurple),
                      _toolChip(Icons.chat, 'AI对话',
                          () => _showAiArticleChat(),
                          color: Colors.deepPurple),
                    ]),
              ),
              const SizedBox(height: 10),
              // ── 正文编辑区 ──
              _editorCard(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _contentCtrl,
                  focusNode: _contentFocus,
                  minLines: 20,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  onChanged: (_) => _onContentChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Markdown 正文',
                    alignLabelWithHint: true,
                    hintText: '支持 # 标题、**粗体**、代码块、列表...\n编辑完可存草稿或直接发布',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      height: 1.6,
                      fontSize: 14.5),
                ),
              ),
              if (_editorStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      if (_editorBusy)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      Text(_editorStatus!,
                          style: TextStyle(
                            color: _editorBusy ? cs.primary : cs.outline,
                            fontSize: 12,
                          )),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // ── 底部操作栏 ──
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, -2))
            ],
          ),
          child: Row(children: [
            if (_failedImageBytes != null) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _editorBusy ? null : _retryUploadImage,
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.orange),
                  label: const Text('重试上传',
                      style: TextStyle(color: Colors.orange)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: Colors.orange),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _editorBusy ? null : _saveLocal,
                icon: const Icon(Icons.drafts_outlined, size: 18),
                label: const Text('存草稿'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(
                      color: cs.primary.withOpacity(0.25)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _editorBusy ? null : _publish,
                icon: _editorBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(_editorBusy
                    ? '发布中...'
                    : (siteManager.isDynamicSite
                        ? '发布到 ${siteManager.currentBlogType.displayName}'
                        : '发布到 GitHub')),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  /// 站点切换器 + 类型指示器
  Widget _buildSiteSwitcher(ColorScheme cs) {
    final allSites = siteManager.allSites;
    final currentIdentity = siteManager.currentSiteIdentity;
    final isDynamic = siteManager.isDynamicSite;

    return _editorCard(
      child: Row(
        children: [
          // ── 站点类型指示器 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDynamic
                  ? const Color(0xFF7C3AED).withOpacity(0.1)
                  : cs.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDynamic
                    ? const Color(0xFF7C3AED).withOpacity(0.3)
                    : cs.primary.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isDynamic ? Icons.cloud_outlined : Icons.folder_outlined,
                  size: 14,
                  color: isDynamic ? const Color(0xFF7C3AED) : cs.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  isDynamic ? '动态CMS' : '静态博客',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDynamic ? const Color(0xFF7C3AED) : cs.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // ── 站点切换下拉 ──
          Expanded(
            child: DropdownButtonFormField<String>(
              value: siteManager.activeSiteId,
              decoration: InputDecoration(
                labelText: '当前站点',
                prefixIcon: Icon(
                  isDynamic ? Icons.dns_outlined : Icons.storage_outlined,
                  size: 18,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              isExpanded: true,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
              items: allSites.map((site) {
                final typeIcon = site.isDynamic ? Icons.cloud : Icons.folder;
                final typeLabel = site.isDynamic ? 'CMS' : '静态';
                return DropdownMenuItem<String>(
                  value: site.id,
                  child: Row(
                    children: [
                      Icon(typeIcon, size: 16, color: cs.outline),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${site.name}  [$typeLabel]',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: _editorBusy ? null : _onSiteChanged,
            ),
          ),
          // ── 管理按钮 ──
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.settings_outlined, size: 20, color: cs.outline),
            onPressed: _editorBusy ? null : _openSiteManagement,
            tooltip: '管理站点',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
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

  Widget _editorCard(
      {required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 1)),
        ],
      ),
      child: child,
    );
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

  Widget _editorTypeToggle({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0EA5E9).withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? const Color(0xFF0EA5E9) : const Color(0xFFE2E8F0),
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: active ? const Color(0xFF0EA5E9) : const Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: active ? const Color(0xFF0EA5E9) : const Color(0xFF475569),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 新功能导航 ──

  void _showTemplateManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TemplateManagerScreen(
          storage: storage,
          aiService: aiService,
          settings: settings,
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
      final ok = await showDialog<bool>(
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

  void _showAiModelManager() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiModelManagerScreen(
          modelManager: aiModelManager,
          aiService: aiService,
          settings: settings,
          onSettingsChanged: _updateSettings,
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