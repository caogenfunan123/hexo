import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'models/ai_profile.dart';
import 'models/app_settings.dart';
import 'models/article.dart';
import 'models/github_token_profile.dart';
import 'models/repo_config.dart';
import 'screens/drafts_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/rss_screen.dart';
import 'screens/history_screen.dart';
import 'screens/folder_upload_screen.dart';
import 'screens/preview_screen.dart';
import 'screens/settings_screen.dart';
import 'services/ai_service.dart';
import 'services/github_service.dart';
import 'services/image_service.dart';
import 'services/rss_service.dart';
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

  AppSettings settings = const AppSettings();
  List<RepoConfig> repos = [];
  List<Article> drafts = [];
  List<GitHubFileItem> remotePosts = [];
  List<RssItem> rssItems = [];
  List<GitCommitItem> commits = [];

  int _currentPage = 0;
  bool loading = true;
  bool busy = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
    setState(() => _currentPage = page);
    Navigator.pop(context); // close drawer
    if (page == 2 && remotePosts.isEmpty) _refreshRemote();
    if (page == 4 && rssItems.isEmpty) _refreshRss();
    if (page == 5 && commits.isEmpty) _refreshCommits();
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

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

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2)));
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

  // ============ UI BUILD ============

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.bg,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: _buildPage(),
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
            });
      case 3:
        return DashboardScreen(
            drafts: drafts,
            remotePosts: remotePosts,
            commits: commits,
            settings: settings,
            activeRepo: activeRepo,
            onNewPost: () => _navigateTo(0));
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
            onRefresh: _refreshCommits);
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
            onReposChanged: _updateRepos);
      default:
        return const SizedBox();
    }
  }

  void _openExistingArticle(Article a) {
    // 先关闭抽屉，再切换页面——确保每个页面点击进入时侧边栏完全收回
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
    setState(() {
      _currentArticle = a;
      _titleCtrl.text = a.title;
      _contentCtrl.text = a.content;
      _tagsCtrl.text = a.tags.join(', ');
      _categoriesCtrl.text = a.categories.join(', ');
      _coverCtrl.text = a.cover ?? '';
      _editorRepo = repos
              .where((r) => r.id == a.repoId)
              .firstOrNull ??
          activeRepo;
      _currentPage = 0;
    });
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