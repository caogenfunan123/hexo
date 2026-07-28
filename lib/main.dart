import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_settings.dart';
import 'models/article.dart';
import 'models/article_template.dart';
import 'models/github_token_profile.dart';
import 'models/repo_config.dart';
import 'screens/dashboard_screen.dart';
import 'screens/editor_page_inline.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/preview_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/rss_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/upload_screen.dart';
import 'services/ai_service.dart';
import 'services/github_service.dart';
import 'services/image_service.dart';
import 'services/rss_service.dart';
import 'services/storage_service.dart';
import 'services/webdav_service.dart';
import 'theme/app_theme.dart';
import 'widgets/common_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HexoApp());
}

class HexoApp extends StatefulWidget {
  const HexoApp({super.key});
  @override
  State<HexoApp> createState() => _HexoAppState();
}

class _HexoAppState extends State<HexoApp> {
  late AppSettings _settings = const AppSettings();

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.fromJson({});
  }

  void _updateTheme(Color c) {
    setState(() => _settings = _settings.copyWith(themeColor: c.value));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hexo 写作',
      theme: AppTheme.light(seedColor: _settings.themeColor),
      home: AppShell(onThemeChanged: _updateTheme),
    );
  }
}

class AppShell extends StatefulWidget {
  final void Function(Color) onThemeChanged;
  const AppShell({super.key, required this.onThemeChanged});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
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
  List<ArticleTemplate> templates = [];
  List<GitHubFileItem> remotePosts = [];
  List<RssItem> rssItems = [];
  List<GitCommitItem> commits = [];

  int _selectedNav = 0;
  bool loading = true;
  bool busy = false;

  RepoConfig? get activeRepo {
    if (repos.isEmpty) return null;
    for (final r in repos) { if (r.id == settings.activeRepoId) return r; }
    for (final r in repos) { if (r.isDefault) return r; }
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

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => loading = true);
    try {
      var s = await storage.loadSettings();
      var r = await storage.loadRepos();
      final d = await storage.loadDrafts();
      var t = await storage.loadTemplates();
      s = _ensureGithubTokens(s, r);
      await storage.saveSettings(s);
      if (r.isEmpty) {
        r = [
          RepoConfig(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: '小子的博客', owner: 'caogenfunan123', repo: 'xiamend',
            token: s.effectiveGithubToken, isDefault: true,
            siteUrl: 'https://caogenfunan.me/',
          ),
        ];
        await storage.saveRepos(r);
        s = s.copyWith(activeRepoId: r.first.id, imageBedOwner: 'caogenfunan123', imageBedRepo: 'xiamend');
        await storage.saveSettings(s);
      } else {
        final eff = s.effectiveGithubToken;
        if (eff.isNotEmpty) {
          bool changed = false;
          r = r.map((repo) { if (repo.token.isEmpty) { changed = true; return repo.copyWith(token: eff); } return repo; }).toList();
          if (changed) await storage.saveRepos(r);
        }
      }
      if (t.isEmpty) { t = PresetTemplates.build(); await storage.saveTemplates(t); }
      setState(() { settings = s; repos = r; drafts = d..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); templates = t; loading = false; });
    } catch (e) { setState(() => loading = false); }
  }

  AppSettings _ensureGithubTokens(AppSettings s, List<RepoConfig> repos) {
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

  Future<void> _saveDraft(Article a) async {
    final i = drafts.indexWhere((e) => e.id == a.id);
    if (i >= 0) drafts[i] = a; else drafts.insert(0, a);
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
    if (repo == null || repo.token.isEmpty) { showToast(context, '请先配置仓库 Token'); return; }
    setState(() => busy = true);
    try { remotePosts = await github.listPosts(repo); } catch (_) {}
    if (mounted) setState(() => busy = false);
  }

  Future<void> _refreshRss() async {
    final url = activeRepo?.siteUrl.isNotEmpty == true ? activeRepo!.siteUrl : 'https://caogenfunan.me/';
    try { rssItems = await rssService.fetch(url); if (mounted) setState(() {}); } catch (_) {}
  }

  Future<void> _refreshCommits() async {
    final repo = effectiveRepo; if (repo == null || repo.token.isEmpty) return;
    try { commits = await github.listCommits(repo); if (mounted) setState(() {}); } catch (_) {}
  }

  Future<void> _openRemote(GitHubFileItem item) async {
    final repo = effectiveRepo; if (repo == null) return;
    try { final a = await github.getArticle(repo, item); _openEditor(article: a); } catch (e) { showToast(context, '打开失败: $e'); }
  }

  void _openEditor({Article? article, String? templateContent}) {
    final a = article ?? Article(id: DateTime.now().millisecondsSinceEpoch.toString(), title: '', content: templateContent ?? '', createdAt: DateTime.now(), updatedAt: DateTime.now(), isDraft: true, repoId: activeRepo?.id);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorPageInline(
      repos: repos, activeRepo: activeRepo, settings: settings, storage: storage, github: github,
      imageService: imageService, aiService: aiService,
      onSaveLocal: _saveDraft,
      onPublished: (p) async { await _saveDraft(p.copyWith(isDraft: false, published: true)); await _refreshRemote(); },
      templates: templates, onTemplatesChanged: _updateTemplates,
    )));
  }

  Future<void> _deleteRemotePost(GitHubFileItem item) async {
    final repo = effectiveRepo; if (repo == null) return;
    final ok = await showConfirm(context, title: '删除远程', message: '确认删除「${item.name}」？', confirmColor: Colors.red);
    if (!ok) return;
    try {
      final a = Article.fromMarkdown('', id: '', remotePath: item.path, remoteSha: item.sha, repoId: repo.id);
      await github.deleteArticle(repo, a); showToast(context, '已删除'); await _refreshRemote();
    } catch (e) { showToast(context, '删除失败: $e'); }
  }

  Future<void> _rollbackFile(String path) async {
    final repo = effectiveRepo; if (repo == null) return;
    await _refreshCommits();
    final sha = await showDialog<String>(context: context, builder: (ctx) => SimpleDialog(
      title: const Text('选择回滚版本'),
      children: commits.take(10).map((c) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, c.sha), child: Text('${c.sha.substring(0,7)} — ${c.message.split("\n").first}', maxLines: 1))).toList(),
    ));
    if (sha == null) return;
    try { await github.rollbackFile(repo, path, sha); showToast(context, '已回滚'); await _refreshRemote(); } catch (e) { showToast(context, '回滚失败: $e'); }
  }

  Future<void> _importLocalMd() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('pickMarkdownFile');
      String? content;
      if (result is String) content = result;
      else if (result is Map) content = result['content']?.toString();
      if (content == null || content.isEmpty) { showToast(context, '文件为空'); return; }
      final a = Article.fromMarkdown(content, repoId: activeRepo?.id);
      await _saveDraft(a); _openEditor(article: a);
    } catch (e) { showToast(context, '导入失败: $e'); }
  }

  Future<void> _updateSettings(AppSettings s) async {
    setState(() => settings = s); await storage.saveSettings(s);
    widget.onThemeChanged(Color(s.themeColor));
  }

  Future<void> _updateRepos(List<RepoConfig> r) async {
    setState(() => repos = r); await storage.saveRepos(r);
  }

  Future<void> _updateTemplates(List<ArticleTemplate> t) async {
    setState(() => templates = t); await storage.saveTemplates(t);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final collapsed = MediaQuery.of(context).size.width < 600;
    final w = collapsed ? 64.0 : 200.0;

    return Scaffold(
      body: Row(children: [
        AnimatedContainer(duration: const Duration(milliseconds: 200), width: w,
          child: Column(children: [
            _sidebarHeader(collapsed),
            if (collapsed)
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: IconButton.filled(icon: const Icon(Icons.add, size: 22), onPressed: () => setState(() => _selectedNav = 0), style: IconButton.styleFrom(backgroundColor: const Color(0xFF0EA5E9))))
            else
              Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: () => setState(() => _selectedNav = 0), icon: const Icon(Icons.add, size: 18), label: const Text('写文章'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
            Expanded(child: ListView(padding: EdgeInsets.zero, children: [
              _nav(0, Icons.edit, '写文章', collapsed),
              _nav(1, Icons.drafts_outlined, '草稿', collapsed, badge: drafts.where((d) => !d.published).length),
              _nav(2, Icons.cloud_outlined, '远程', collapsed),
              _nav(3, Icons.dashboard_outlined, '仪表盘', collapsed),
              _nav(4, Icons.rss_feed_outlined, 'RSS', collapsed),
              _nav(5, Icons.history_outlined, '历史', collapsed),
              _nav(6, Icons.upload_file, '批量上传', collapsed),
              _nav(7, Icons.preview_outlined, '预览', collapsed),
              const Divider(height: 1),
              _nav(8, Icons.settings_outlined, '设置', collapsed),
            ])),
            _sidebarFooter(collapsed),
          ]),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: Column(children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildPage()),
        ])),
      ]),
    );
  }

  Widget _sidebarHeader(bool collapsed) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
    child: collapsed ? const Icon(Icons.edit_note, color: Color(0xFF0EA5E9), size: 28)
        : Row(children: [
            const Icon(Icons.edit_note, color: Color(0xFF0EA5E9), size: 24), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(settings.siteName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(settings.siteBio, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
          ]),
  );

  Widget _sidebarFooter(bool collapsed) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
    child: collapsed ? const Icon(Icons.storage_outlined, size: 20, color: Color(0xFF64748B))
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(activeRepo?.name ?? '无仓库', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text(activeRepo?.fullName ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ]),
  );

  Widget _nav(int i, IconData icon, String label, bool collapsed, {int badge = 0}) {
    final sel = _selectedNav == i;
    return Material(color: sel ? const Color(0xFFE0F2FE) : Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _selectedNav = i);
          if (i == 2 && remotePosts.isEmpty) _refreshRemote();
          if (i == 4 && rssItems.isEmpty) _refreshRss();
          if (i == 5 && commits.isEmpty) _refreshCommits();
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 16, vertical: collapsed ? 6 : 10),
          child: collapsed
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Badge('$badge', color: sel ? const Color(0xFF0EA5E9) : Colors.grey),
                  const SizedBox(height: 2),
                  Text(label, style: TextStyle(fontSize: 9, color: sel ? const Color(0xFF0EA5E9) : Colors.grey.shade600)),
                ])
              : Row(children: [
                  Icon(icon, size: 20, color: sel ? const Color(0xFF0EA5E9) : Colors.grey.shade600), const SizedBox(width: 12),
                  Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.normal, color: sel ? const Color(0xFF0EA5E9) : Colors.grey.shade700))),
                  if (badge > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: sel ? const Color(0xFF0EA5E9) : Colors.grey.shade300, borderRadius: BorderRadius.circular(10)), child: Text('$badge', style: TextStyle(fontSize: 10, color: sel ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w600))),
                ]),
        ),
      ),
    );
  }

  Widget _buildPage() {
    switch (_selectedNav) {
      case 0: return EditorPageInline(repos: repos, activeRepo: activeRepo, settings: settings, storage: storage, github: github, imageService: imageService, aiService: aiService, onSaveLocal: _saveDraft, onPublished: (p) async { await _saveDraft(p.copyWith(isDraft: false, published: true)); await _refreshRemote(); }, templates: templates, onTemplatesChanged: _updateTemplates);
      case 1: return HomeScreen(drafts: drafts, templates: templates, onOpen: (a) => _openEditor(article: a), onDelete: _deleteDraft, onNew: () => setState(() => _selectedNav = 0), onNewFromTemplate: (t) => _openEditor(templateContent: t.content), onImport: _importLocalMd);
      case 2: return RemoteScreen(posts: remotePosts, activeRepo: activeRepo, effectiveRepo: effectiveRepo, github: github, onRefresh: _refreshRemote, onOpen: _openRemote, onDelete: _deleteRemotePost, onRollback: _rollbackFile, onNew: () => setState(() => _selectedNav = 0));
      case 3: return DashboardScreen(drafts: drafts, remotePosts: remotePosts, commits: commits, settings: settings, activeRepo: activeRepo, onNewPost: () => setState(() => _selectedNav = 0));
      case 4: return RssScreen(items: rssItems, activeRepo: activeRepo, onRefresh: _refreshRss, onOpenAsDraft: (it) { final now = DateTime.now(); _openEditor(article: Article(id: now.millisecondsSinceEpoch.toString(), title: it.title, content: '来源: ${it.link}\n\n${it.description}', createdAt: now, updatedAt: now, isDraft: true, repoId: activeRepo?.id)); });
      case 5: return HistoryScreen(commits: commits, github: github, effectiveRepo: effectiveRepo, onRefresh: _refreshCommits, onRollback: _rollbackFile);
      case 6: return UploadScreen(repos: repos, github: github);
      case 7: return PreviewScreen(repos: repos, github: github);
      case 8: return SettingsScreen(settings: settings, repos: repos, templates: templates, github: github, storage: storage, webdavService: webdavService, onSettingsChanged: _updateSettings, onReposChanged: _updateRepos, onTemplatesChanged: _updateTemplates);
      default: return const SizedBox();
    }
  }
}
