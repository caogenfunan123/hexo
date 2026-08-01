import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'models/ai_profile.dart';
import 'models/app_settings.dart';
import 'models/article.dart';
import 'models/github_token_profile.dart';
import 'models/repo_config.dart';
import 'models/session_state.dart';
import 'screens/article_reader_screen.dart';
import 'screens/drafts_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/rss_screen.dart';
import 'screens/history_screen.dart';
import 'screens/folder_upload_screen.dart';
import 'screens/preview_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/site_editor_screen.dart';
import 'services/ai_service.dart';
import 'services/github_service.dart';
import 'services/image_service.dart';
import 'services/rss_service.dart';
import 'services/session_service.dart';
import 'services/storage_service.dart';
import 'services/webdav_service.dart';
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

class _RootShellState extends State<RootShell> {
  static const _channel = MethodChannel('hexo/native');
  final storage = StorageService();
  final github = GitHubService();
  late final imageService = ImageService(github);
  final aiService = AiService();
  final rssService = RssService();
  final webdavService = WebDavService();
  final sessionService = SessionService();

  AppSettings settings = const AppSettings();
  List<RepoConfig> repos = [];
  List<Article> drafts = [];
  List<GitHubFileItem> remotePosts = [];
  List<RssItem> rssItems = [];
  List<GitCommitItem> commits = [];

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
  String _lastSavedContent = '';
  bool _hasUnsavedChanges = false;

  // Editor state
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  late TextEditingController _tagsCtrl;
  late TextEditingController _categoriesCtrl;
  late TextEditingController _coverCtrl;
  late Article _currentArticle;
  RepoConfig? _editorRepo;
  bool _editorBusy = false;
  String? _editorStatus;
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

  String get _pageTitle {
    switch (_currentPage) {
      case 0:
        return '写文章';
      case 1:
        return '草稿';
      case 2:
        return '远程';
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
      default:
        return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _contentCtrl = TextEditingController();
    _tagsCtrl = TextEditingController();
    _categoriesCtrl = TextEditingController();
    _coverCtrl = TextEditingController();
    _currentArticle = Article(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: '',
      content: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDraft: true,
      repoId: activeRepo?.id,
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _stopAutoSave();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _tagsCtrl.dispose();
    _categoriesCtrl.dispose();
    _coverCtrl.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => loading = true);
    try {
      var s = await storage.loadSettings();
      var r = await storage.loadRepos();
      final d = await storage.loadDrafts();
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
      setState(() {
        settings = s;
        repos = r;
        drafts = d..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        loading = false;
      });
      // 会话恢复
      if (s.restoreSession) {
        await _restoreSession();
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
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
    Navigator.pop(context); // close drawer
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
    _currentArticle = Article(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: '',
      content: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDraft: true,
      repoId: activeRepo?.id,
    );
    _titleCtrl.text = '';
    _contentCtrl.text = '';
    _tagsCtrl.text = '';
    _categoriesCtrl.text = '';
    _coverCtrl.text = '';
    _lastSavedContent = '';
    _hasUnsavedChanges = false;
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
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      categories: _categoriesCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      cover: cover.isEmpty ? null : cover,
      updatedAt: DateTime.now(),
      isDraft: draft,
      published: draft ? false : true,
      repoId: _editorRepo?.id ?? _currentArticle.repoId,
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
    _lastSavedContent = a.content;
    _hasUnsavedChanges = false;
    if (mounted) _showToast('草稿已保存到本地');
  }

  Future<void> _publish() async {
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
      if (mounted) _showToast('已发布到 ${repo.fullName}');
    } catch (e) {
      setState(() => _editorStatus = '发布失败');
      if (mounted) _showToast('发布失败: $e');
    } finally {
      if (mounted) setState(() => _editorBusy = false);
    }
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
      _editorStatus = '上传图片...';
    });
    try {
      final bytes = await imageService.pickImageBytes();
      if (bytes == null) {
        setState(() => _editorStatus = '已取消');
        return;
      }
      final url = await imageService.uploadToImageBed(bytes, settings);
      _insertText(imageService.markdownImage(url));
      setState(() => _editorStatus = '图片已插入');
    } catch (e) {
      if (mounted) _showToast('上传失败: $e');
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
    await storage.saveSettings(s);
    widget.onThemeChanged(Color(s.themeColor));
  }

  Future<void> _updateRepos(List<RepoConfig> r) async {
    setState(() => repos = r);
    await storage.saveRepos(r);
  }

  Future<void> _persistSettings() => storage.saveSettings(settings);
  Future<void> _persistRepos() => storage.saveRepos(repos);
  Future<void> _persistDrafts() => storage.saveDrafts(drafts);

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
                                '${r.fullName} @ ${r.branch}\n${r.postsPath}',
                              ),
                              isThreeLine: true,
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
    final site = TextEditingController(
        text: existing?.siteUrl ??
            'https://caogenfunan.me/');
    final token = TextEditingController(
        text: existing?.token.isNotEmpty == true
            ? existing!.token
            : settings.effectiveGithubToken);
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
                    TextField(
                        controller: posts,
                        decoration: const InputDecoration(
                            labelText: '文章目录')),
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
      siteUrl: site.text.trim(),
      token: tokenValue,
      isDefault: existing?.isDefault ?? repos.isEmpty,
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
        } else {
          if (mounted) Navigator.of(context).maybePop();
        }
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
                  _drawerItem(3, Icons.dashboard_outlined, '仪表盘'),
                  _drawerItem(5, Icons.history_outlined, '提交历史'),
                  const SizedBox(height: 8),
                  _drawerSection('工具'),
                  _drawerItem(6, Icons.drive_folder_upload, '批量上传'),
                  _drawerItem(7, Icons.language, '网站预览'),
                  _drawerItem(4, Icons.rss_feed_outlined, 'RSS 订阅'),
                  const SizedBox(height: 8),
                  _drawerSection('系统'),
                  _drawerItem(8, Icons.settings_outlined, '设置'),
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

  // ============ PAGES ============

  Widget _buildPage() {
    switch (_currentPage) {
      case 0:
        return _buildEditorPage();
      case 1:
        return DraftsScreen(
            drafts: drafts,
            onOpen: (a) {
              _openExistingArticle(a);
            },
            onDelete: _deleteDraft);
      case 2:
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
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
            children: [
              // ── 仓库选择器 ──
              if (repos.isNotEmpty)
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
                      _toolChip(Icons.image_outlined, '图床',
                          _editorBusy ? null : _insertImage),
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
                  child: Text(_editorStatus!,
                      style: TextStyle(color: cs.primary, fontSize: 12)),
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
                label: Text(_editorBusy ? '发布中...' : '发布到 GitHub'),
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
}