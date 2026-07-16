import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import 'models/ai_profile.dart';
import 'models/app_settings.dart';
import 'models/article.dart';
import 'models/github_token_profile.dart';
import 'models/repo_config.dart';
import 'screens/editor_screen.dart';
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
      home: RootShell(onThemeChanged: updateTheme, initialSettings: _settings),
    );
  }
}

class RootShell extends StatefulWidget {
  final void Function(Color) onThemeChanged;
  final AppSettings initialSettings;
  const RootShell({super.key, required this.onThemeChanged, required this.initialSettings});

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

  AppSettings settings = const AppSettings();
  List<RepoConfig> repos = [];
  List<Article> drafts = [];
  List<GitHubFileItem> remotePosts = [];
  List<RssItem> rssItems = [];
  List<GitCommitItem> commits = [];

  int tab = 0;
  bool loading = true;
  bool busy = false;
  String searchQuery = '';
  List<GitHubSearchHit> githubSearchHits = [];
  bool githubSearchLoading = false;
  String? error;

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

  /// 当前仓库；若仓库 token 为空则回退到已登录令牌。
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
    setState(() {
      loading = true;
      error = null;
    });
    try {
      var s = await storage.loadSettings();
      var r = await storage.loadRepos();
      final d = await storage.loadDrafts();

      // 从已有 defaultToken / 仓库 token 汇总已登录令牌
      s = _ensureGithubTokensFromLegacy(s, r);
      await storage.saveSettings(s);

      // 首次启动预填用户仓库
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
          ),
        ];
        await storage.saveRepos(r);
        final ns = s.copyWith(
          activeRepoId: r.first.id,
          imageBedOwner: s.imageBedOwner.isEmpty ? 'caogenfunan123' : s.imageBedOwner,
          imageBedRepo: s.imageBedRepo.isEmpty ? 'xiamend' : s.imageBedRepo,
          defaultToken: s.effectiveGithubToken,
        );
        await storage.saveSettings(ns);
        settings = ns;
      } else {
        // 仓库缺 token 时自动填入当前已登录令牌
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
        settings = s;
      }
      repos = r;
      drafts = d..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _persistSettings() => storage.saveSettings(settings);
  Future<void> _persistRepos() => storage.saveRepos(repos);
  Future<void> _persistDrafts() => storage.saveDrafts(drafts);

  Future<void> _saveDraft(Article a) async {
    final i = drafts.indexWhere((e) => e.id == a.id);
    if (i >= 0) {
      drafts[i] = a;
    } else {
      drafts.insert(0, a);
    }
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _persistDrafts();
    await storage.exportDraftMarkdown(a);
    if (mounted) setState(() {});
  }

  Future<void> _deleteDraft(Article a) async {
    drafts.removeWhere((e) => e.id == a.id);
    await _persistDrafts();
    if (mounted) setState(() {});
  }

  Future<void> _refreshRemote() async {
    final repo = effectiveRepo;
    if (repo == null || repo.token.isEmpty) {
      _toast('请先配置仓库 Token');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      remotePosts = await github.listPosts(repo);
      if (mounted) setState(() {});
    } catch (e) {
      error = e.toString();
      _toast('拉取远程文章失败: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _refreshRss() async {
    final repo = activeRepo;
    final url = repo?.siteUrl.isNotEmpty == true
        ? repo!.siteUrl
        : 'https://caogenfunan.me/';
    setState(() => busy = true);
    try {
      rssItems = await rssService.fetch(url);
      if (mounted) setState(() {});
    } catch (e) {
      _toast('RSS 失败: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _refreshCommits() async {
    final repo = effectiveRepo;
    if (repo == null || repo.token.isEmpty) {
      _toast('请先配置仓库 Token');
      return;
    }
    setState(() => busy = true);
    try {
      commits = await github.listCommits(repo);
      if (mounted) setState(() {});
    } catch (e) {
      _toast('提交历史失败: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    final messenger = context.findAncestorStateOfType<ScaffoldMessengerState>();
    messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openEditor({Article? article}) async {
    final a = article ??
        Article(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: '',
          content: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isDraft: true,
          repoId: activeRepo?.id,
        );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          article: a,
          repos: repos,
          activeRepo: activeRepo,
          settings: settings,
          storage: storage,
          github: github,
          imageService: imageService,
          aiService: aiService,
          onSaveLocal: _saveDraft,
          onPublished: (published) async {
            await _saveDraft(published.copyWith(isDraft: false, published: true));
            await _refreshRemote();
          },
          onDeletedRemote: (local) async {
            await _saveDraft(local);
            await _refreshRemote();
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openRemote(GitHubFileItem item) async {
    final repo = effectiveRepo;
    if (repo == null) return;
    setState(() => busy = true);
    try {
      final article = await github.getArticle(repo, item);
      await _openEditor(article: article);
    } catch (e) {
      _toast('打开远程文章失败: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Article> get filteredDrafts {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return drafts;
    return drafts.where((a) {
      return a.title.toLowerCase().contains(q) ||
          a.content.toLowerCase().contains(q) ||
          a.tags.any((t) => t.toLowerCase().contains(q)) ||
          a.categories.any((c) => c.toLowerCase().contains(q));
    }).toList();
  }

  List<GitHubFileItem> get filteredRemote {
    final q = searchQuery.trim().toLowerCase();
    // 有 GitHub 全文搜索结果时优先展示命中文件
    if (q.isNotEmpty && githubSearchHits.isNotEmpty) {
      return githubSearchHits.map((e) => e.toFileItem()).toList();
    }
    if (q.isEmpty) return remotePosts;
    return remotePosts
        .where((e) =>
            e.name.toLowerCase().contains(q) || e.path.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final pages = [
      _buildHome(),
      _buildRemote(),
      _buildRss(),
      _buildHistory(),
      _buildSettings(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForTab(tab)),
        actions: [
          if (tab == 0 || tab == 1)
            IconButton(
              tooltip: '全文搜索',
              onPressed: _showSearch,
              icon: const Icon(Icons.search),
            ),
          if (tab == 1)
            IconButton(
              onPressed: busy ? null : _refreshRemote,
              icon: const Icon(Icons.refresh),
            ),
          if (tab == 2)
            IconButton(
              onPressed: busy ? null : _refreshRss,
              icon: const Icon(Icons.refresh),
            ),
          if (tab == 3)
            IconButton(
              onPressed: busy ? null : _refreshCommits,
              icon: const Icon(Icons.refresh),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'repo') await _showRepoManager();
              if (v == 'pwa') await _showPwaGuide();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'repo', child: Text('多仓库管理')),
              PopupMenuItem(value: 'pwa', child: Text('PWA / 站点快捷方式')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (activeRepo != null)
            Material(
              color: const Color(0xFFE0F2FE),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.cloud_outlined, size: 20),
                title: Text(
                  '${activeRepo!.name} · ${activeRepo!.fullName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  activeRepo!.siteUrl.isEmpty
                      ? activeRepo!.postsPath
                      : activeRepo!.siteUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: _showRepoManager,
                  child: const Text('切换'),
                ),
              ),
            ),
          if (searchQuery.isNotEmpty)
            Material(
              color: const Color(0xFFFEF3C7),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.filter_alt_outlined, size: 18),
                title: Text('搜索: $searchQuery'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => searchQuery = ''),
                ),
              ),
            ),
          Expanded(child: pages[tab]),
        ],
      ),
      floatingActionButton: tab == 0 || tab == 1
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'import_md',
                  onPressed: _importLocalMd,
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  icon: const Icon(Icons.file_open_outlined, size: 20),
                  label: const Text('导入 .md', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  onPressed: () => _openEditor(),
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('写文章'),
                ),
              ],
            )
          : null,
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        elevation: 0,
        selectedIndex: tab,
        onDestinationSelected: (i) {
          setState(() => tab = i);
          if (i == 1 && remotePosts.isEmpty) _refreshRemote();
          if (i == 2 && rssItems.isEmpty) _refreshRss();
          if (i == 3 && commits.isEmpty) _refreshCommits();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.drafts_outlined),
            selectedIcon: Icon(Icons.drafts),
            label: '草稿',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: '远程',
          ),
          NavigationDestination(
            icon: Icon(Icons.rss_feed_outlined),
            selectedIcon: Icon(Icons.rss_feed),
            label: 'RSS',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '历史',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }

  String _titleForTab(int i) {
    switch (i) {
      case 0:
        return '本地草稿';
      case 1:
        return '远程文章';
      case 2:
        return 'RSS 订阅';
      case 3:
        return 'Git 提交历史';
      default:
        return '设置';
    }
  }

  Widget _buildHome() {
    final list = filteredDrafts;
    if (list.isEmpty) {
      return _EmptyState(
        icon: Icons.note_add_outlined,
        title: '还没有草稿',
        subtitle: '支持离线编辑，写完后一键发布到 GitHub source/_posts',
        actionLabel: '新建文章',
        onAction: () => _openEditor(),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final a = list[i];
        return Card(
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(
              a.title.isEmpty ? '未命名' : a.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  a.content.replaceAll(RegExp(r'\s+'), ' ').trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Badge(
                      a.published ? '已发布' : '草稿',
                      color: a.published
                          ? const Color(0xFF059669)
                          : const Color(0xFFD97706),
                    ),
                    Text(
                      _fmt(a.updatedAt),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    ...a.tags.take(3).map((t) => _Badge('#$t')),
                  ],
                ),
              ],
            ),
            onTap: () => _openEditor(article: a),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'delete') {
                  final ok = await _confirm('删除本地草稿「${a.title}」？');
                  if (ok) await _deleteDraft(a);
                } else if (v == 'export') {
                  await storage.exportDraftMarkdown(a);
                  _toast('已导出 Markdown 到本地目录');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'export', child: Text('导出 MD')),
                PopupMenuItem(value: 'delete', child: Text('删除草稿')),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRemote() {
    if (effectiveRepo?.token.isEmpty != false) {
      return _EmptyState(
        icon: Icons.key_outlined,
        title: '需要 GitHub Token',
        subtitle: '在设置里登录并保存 classic/fine-grained token（contents:write）后即可拉取与发布',
        actionLabel: '去设置',
        onAction: () => setState(() => tab = 4),
      );
    }
    final list = filteredRemote;
    if (list.isEmpty) {
      if (searchQuery.isNotEmpty) {
        return _EmptyState(
          icon: Icons.search_off,
          title: '未找到匹配文章',
          subtitle: githubSearchLoading
              ? '正在进行 GitHub 全文搜索...'
              : '本地文件名与 GitHub 全文均无结果: $searchQuery',
          actionLabel: '清除搜索',
          onAction: () => setState(() {
            searchQuery = '';
            githubSearchHits = [];
          }),
        );
      }
      return _EmptyState(
        icon: Icons.cloud_download_outlined,
        title: '暂无远程文章缓存',
        subtitle: '点击刷新从 ${activeRepo?.postsPath ?? "source/_posts"} 拉取 .md',
        actionLabel: '刷新',
        onAction: _refreshRemote,
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshRemote,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length + (searchQuery.isNotEmpty ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (searchQuery.isNotEmpty && i == 0) {
            return Card(
              color: const Color(0xFFEFF6FF),
              child: ListTile(
                leading: githubSearchLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore),
                title: Text(
                  githubSearchHits.isNotEmpty
                      ? 'GitHub 全文: ${githubSearchHits.length} 条 · "$searchQuery"'
                      : '本地文件名过滤 · "$searchQuery"',
                ),
                subtitle: const Text('点此重新搜索 / 清除'),
                onTap: _showSearch,
                trailing: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    searchQuery = '';
                    githubSearchHits = [];
                  }),
                ),
              ),
            );
          }
          final f = list[searchQuery.isNotEmpty ? i - 1 : i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(f.name),
              subtitle: Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _openRemote(f),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    await _openRemote(f);
                  } else if (v == 'delete') {
                    await _deleteRemotePost(f);
                  } else if (v == 'rollback') {
                    await _rollbackFile(f.path);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'rollback', child: Text('回滚历史')),
                  PopupMenuItem(value: 'delete', child: Text('删除远程')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRss() {
    if (rssItems.isEmpty) {
      return _EmptyState(
        icon: Icons.rss_feed,
        title: 'RSS 未加载',
        subtitle: '从站点 atom.xml / rss.xml 读取最新文章',
        actionLabel: '加载 RSS',
        onAction: _refreshRss,
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshRss,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rssItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final it = rssItems[i];
          return Card(
            child: ListTile(
              title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (it.pubDate != null)
                    Text(
                      _fmt(it.pubDate!),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  if (it.description.isNotEmpty)
                    Text(it.description, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ),
              onTap: () {
                Clipboard.setData(ClipboardData(text: it.link));
                _toast('链接已复制: ${it.link}');
              },
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'copy') {
                    Clipboard.setData(ClipboardData(text: it.link));
                    _toast('链接已复制');
                  } else if (v == 'draft') {
                    final now = DateTime.now();
                    final a = Article(
                      id: now.millisecondsSinceEpoch.toString(),
                      title: it.title,
                      content: '来源: ${it.link}\n\n${it.description}',
                      createdAt: now,
                      updatedAt: now,
                      isDraft: true,
                      repoId: activeRepo?.id,
                    );
                    await _openEditor(article: a);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'draft', child: Text('转为草稿编辑')),
                  PopupMenuItem(value: 'copy', child: Text('复制链接')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistory() {
    if (commits.isEmpty) {
      return _EmptyState(
        icon: Icons.history,
        title: '提交历史',
        subtitle: '查看 GitHub 提交记录；可对单文件恢复到历史版本并重新提交',
        actionLabel: '加载历史',
        onAction: _refreshCommits,
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshCommits,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: commits.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final c = commits[i];
          return Card(
            child: ListTile(
              title: Text(
                c.message.split('\n').first,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${c.author} · ${_fmt(c.date)} · ${c.sha.substring(0, 7)}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: c.sha));
                  _toast('已复制 commit sha');
                },
              ),
              onTap: () => _showCommitActions(c),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle('GitHub 登录令牌'),
        _settingsCard([
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key_outlined),
            title: Text(
              settings.activeGithubToken?.displayLabel ??
                  (settings.effectiveGithubToken.isEmpty ? '尚未登录 Token' : '已配置 Token'),
            ),
            subtitle: Text(
              settings.githubTokens.isEmpty
                  ? '保存过的 Token 可复用到多个仓库'
                  : '已保存 ${settings.githubTokens.length} 个 · 点此管理',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showGithubTokenManager,
          ),
          if (settings.githubTokens.isNotEmpty)
            DropdownButtonFormField<String>(
              value: settings.githubTokens.any((e) => e.id == settings.activeGithubTokenId)
                  ? settings.activeGithubTokenId
                  : settings.githubTokens.first.id,
              decoration: const InputDecoration(
                labelText: '当前登录令牌',
                prefixIcon: Icon(Icons.swap_horiz),
              ),
              items: settings.githubTokens
                  .map(
                    (t) => DropdownMenuItem(
                      value: t.id,
                      child: Text(t.displayLabel, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                await _activateGithubToken(v);
              },
            ),
          FilledButton.tonalIcon(
            onPressed: () async {
              final created = await _editGithubToken(null);
              if (created != null) {
                await _upsertGithubToken(created, makeActive: true);
                _toast('已登录并保存 ${created.displayLabel}');
              }
            },
            icon: const Icon(Icons.login),
            label: const Text('添加 / 登录 Token'),
          ),
          FilledButton.tonalIcon(
            onPressed: () async {
              final token = settings.effectiveGithubToken;
              if (token.isEmpty) {
                _toast('请先添加 GitHub Token');
                return;
              }
              try {
                final user = await github.getUser(token);
                final login = user['login']?.toString() ?? '';
                _toast(login.isEmpty ? 'Token 有效' : 'Token 有效 · @$login');
                final active = settings.activeGithubToken;
                if (active != null) {
                  await _upsertGithubToken(
                    active.copyWith(
                      login: login,
                      avatarUrl: user['avatar_url']?.toString() ?? active.avatarUrl,
                      htmlUrl: user['html_url']?.toString() ?? active.htmlUrl,
                      lastVerifiedAt: DateTime.now(),
                      name: active.name.isEmpty || active.name == '默认 Token' || active.name == 'GitHub Token'
                          ? (login.isNotEmpty ? login : active.name)
                          : active.name,
                    ),
                    makeActive: true,
                  );
                }
              } catch (e) {
                _toast('校验失败: $e');
              }
            },
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('验证当前 Token'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('多仓库管理'),
            subtitle: Text('当前 ${repos.length} 个仓库'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showRepoManager,
          ),
          const Text(
            '登录过的 Token 会本地保存，可随时切换；新建/编辑仓库时可一键选用已登录令牌。',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ]),

        const SizedBox(height: 16),
        _SectionTitle('WebDAV 云端备份'),
        _settingsCard([
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('配置坚果云 / WebDAV 网盘'),
            subtitle: Text(settings.webdavUrl.isEmpty ? '填写 WebDAV 地址、账号和密码' : '已配置: ${settings.webdavUrl}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showWebDavDialog(),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('上传草稿到 WebDAV'),
            subtitle: Text(settings.webdavUrl.isEmpty ? '请先配置 WebDAV' : '同步本地草稿到云端'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async => _syncDraftsToWebDav(),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: const Text('从 WebDAV 同步到本地'),
            subtitle: Text(settings.webdavUrl.isEmpty ? '请先配置 WebDAV' : '下载云端草稿到本地'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async => _syncWebDavToLocal(),
          ),
        ]),
                _SectionTitle('图床（GitHub + CDN）'),
        _settingsCard([
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync_alt),
            title: const Text('一键同步当前仓库为图床'),
            subtitle: Text(
              activeRepo == null
                  ? '请先添加仓库'
                  : '使用 ${activeRepo!.fullName} / ${activeRepo!.branch}，Token 回退已登录令牌',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final r = activeRepo;
              if (r == null) {
                _toast('请先添加仓库');
                return;
              }
              settings = settings.copyWith(
                imageBedOwner: r.owner,
                imageBedRepo: r.repo,
                imageBedBranch: r.branch,
                imageBedToken: settings.imageBedToken.isNotEmpty
                    ? settings.imageBedToken
                    : settings.effectiveGithubToken,
                imageBedPath:
                    settings.imageBedPath.isEmpty ? 'images' : settings.imageBedPath,
              );
              await _persistSettings();
              setState(() {});
              _toast('已同步图床仓库为 ${r.fullName}');
            },
          ),
          _field(
            label: '图床 Token（可留空用已登录令牌）',
            value: settings.imageBedToken,
            obscure: true,
            onChanged: (v) async {
              settings = settings.copyWith(imageBedToken: v);
              await _persistSettings();
            },
          ),
          _field(
            label: 'Owner',
            value: settings.imageBedOwner,
            onChanged: (v) async {
              settings = settings.copyWith(imageBedOwner: v);
              await _persistSettings();
            },
          ),
          _field(
            label: 'Repo',
            value: settings.imageBedRepo,
            onChanged: (v) async {
              settings = settings.copyWith(imageBedRepo: v);
              await _persistSettings();
            },
          ),
          _field(
            label: 'Branch',
            value: settings.imageBedBranch,
            onChanged: (v) async {
              settings = settings.copyWith(imageBedBranch: v);
              await _persistSettings();
            },
          ),
          _field(
            label: '目录路径',
            value: settings.imageBedPath,
            onChanged: (v) async {
              settings = settings.copyWith(imageBedPath: v);
              await _persistSettings();
            },
          ),
          _field(
            label: '自定义 CDN 前缀（可选）',
            value: settings.imageBedCdn,
            onChanged: (v) async {
              settings = settings.copyWith(imageBedCdn: v);
              await _persistSettings();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动压缩图片'),
            subtitle: Text(
              '最大宽 ${settings.compressMaxWidth}px / 质量 ${settings.compressQuality}',
            ),
            value: settings.autoCompressImage,
            onChanged: (v) async {
              settings = settings.copyWith(autoCompressImage: v);
              await _persistSettings();
              setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 16),
        _SectionTitle('AI 中转站（可多套切换）'),
        _settingsCard([
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.smart_toy_outlined),
            title: Text(
              settings.activeAiProfile?.displayLabel ?? '尚未配置 AI',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              settings.aiProfiles.isEmpty
                  ? '填写密钥和 URL，获取模型后保存；可添加多套任意切换'
                  : '已保存 ${settings.aiProfiles.length} 套配置 · 点此管理',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showAiManager,
          ),
          if (settings.aiProfiles.isNotEmpty)
            DropdownButtonFormField<String>(
              value: settings.activeAiProfile?.id,
              decoration: const InputDecoration(
                labelText: '当前使用的 AI 配置',
                prefixIcon: Icon(Icons.swap_horiz),
              ),
              items: settings.aiProfiles
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(p.displayLabel, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                final p = settings.aiProfiles.firstWhere((e) => e.id == v);
                settings = settings.copyWith(
                  activeAiProfileId: p.id,
                  aiBaseUrl: p.baseUrl,
                  aiApiKey: p.apiKey,
                  aiModel: p.model,
                  aiProvider: p.name,
                );
                await _persistSettings();
                setState(() {});
                _toast('已切换到 ${p.displayLabel}');
              },
            ),
          const SizedBox(height: 8),
          const Text(
            '兼容各类 OpenAI 中转站：填 Base URL + API Key → 点击获取模型 → 选择模型保存。可同时保存多套配置随时切换。',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ]),
        const SizedBox(height: 16),
        _SectionTitle('站点与 PWA'),
        _settingsCard([
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: const Text('博客地址'),
            subtitle: Text(activeRepo?.siteUrl.isNotEmpty == true
                ? activeRepo!.siteUrl
                : 'https://caogenfunan.me/'),
            trailing: const Icon(Icons.copy),
            onTap: () {
              final u = activeRepo?.siteUrl.isNotEmpty == true
                  ? activeRepo!.siteUrl
                  : 'https://caogenfunan.me/';
              Clipboard.setData(ClipboardData(text: u));
              _toast('已复制站点地址');
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.install_mobile),
            title: const Text('PWA 说明'),
            subtitle: const Text('站点已部署 Cloudflare Pages，可在浏览器“添加到主屏幕”'),
            onTap: _showPwaGuide,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.web),
            title: const Text('网站页面编辑'),
            subtitle: Text('头像 · 名称 · 首页 · 关于 · 留言 · Now · 作品'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showSiteEditor,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.palette),
            title: const Text('主题颜色'),
            subtitle: Text('点击切换主题色'),
            trailing: CircleAvatar(
              backgroundColor: Color(settings.themeColor),
              radius: 14,
            ),
            onTap: _showThemeColorPicker,
          ),
        ]),
        const SizedBox(height: 16),
        _SectionTitle('关于'),
        _settingsCard([
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Hexo 写作管理系统'),
            subtitle: Text(
              '本地草稿 · 离线编辑 · GitHub 发布 · 图床 · AI · RSS · 搜索 · 提交回滚',
            ),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('作者'),
            subtitle: Text('小子'),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('版本'),
            subtitle: Text('1.0.1'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('联系邮箱'),
            subtitle: const Text('1995@139.com'),
            trailing: const Icon(Icons.copy),
            onTap: () {
              Clipboard.setData(const ClipboardData(text: '1995@139.com'));
              _toast('已复制邮箱地址');
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('仓库'),
            subtitle: const Text('github.com/caogenfunan123/xiamend'),
            trailing: const Icon(Icons.copy),
            onTap: () {
              Clipboard.setData(
                const ClipboardData(text: 'https://github.com/caogenfunan123/xiamend'),
              );
              _toast('已复制仓库地址');
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('导出目录'),
            subtitle: const Text('查看本地 drafts_md 导出路径'),
            onTap: () async {
              final dir = await storage.draftsDir();
              Clipboard.setData(ClipboardData(text: dir.path));
              _toast('导出目录已复制: ${dir.path}');
            },
          ),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _settingsCard(List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1) const SizedBox(height: 12),
            ]
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    bool obscure = false,
  }) {
    return TextFormField(
      initialValue: value,
      obscureText: obscure,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    );
  }

  Future<void> _showSearch() async {
    final controller = TextEditingController(text: searchQuery);
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
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('清除')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
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
    if (query.isNotEmpty && (tab == 1 || tab == 0)) {
      await _runGithubFullTextSearch(query);
      if (tab == 0 && githubSearchHits.isNotEmpty) {
        // 有远程命中时提示可去远程页查看
        _toast('本地过滤完成；远程命中 ${githubSearchHits.length} 条，可切换到「远程」查看');
      }
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
        _toast('GitHub 全文无匹配（仍显示本地文件名过滤结果）');
      } else {
        _toast('GitHub 全文命中 ${hits.length} 个文件');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => githubSearchHits = []);
      _toast('GitHub 全文搜索失败: $e');
    } finally {
      if (mounted) setState(() => githubSearchLoading = false);
    }
  }

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
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
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
                              fontWeight: FontWeight.w700,
                            ),
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
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = repos[i];
                          final active = activeRepo?.id == r.id;
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                active
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: active
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              title: Text(r.name),
                              subtitle: Text(
                                '${r.fullName} @ ${r.branch}\n${r.postsPath}',
                              ),
                              isThreeLine: true,
                              onTap: () async {
                                settings = settings.copyWith(activeRepoId: r.id);
                                await _persistSettings();
                                remotePosts = [];
                                commits = [];
                                setState(() {});
                                setModal(() {});
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'edit') {
                                    await _editRepo(existing: r);
                                  } else if (v == 'delete') {
                                    final ok = await _confirm('删除仓库配置「${r.name}」？');
                                    if (ok) {
                                      repos.removeWhere((e) => e.id == r.id);
                                      await _persistRepos();
                                      if (settings.activeRepoId == r.id) {
                                        settings = settings.copyWith(
                                          activeRepoId:
                                              repos.isEmpty ? '' : repos.first.id,
                                        );
                                        await _persistSettings();
                                      }
                                    }
                                  }
                                  setModal(() {});
                                  setState(() {});
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                                  PopupMenuItem(value: 'delete', child: Text('删除')),
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
    final name = TextEditingController(text: existing?.name ?? '');
    final owner = TextEditingController(text: existing?.owner ?? 'caogenfunan123');
    final repo = TextEditingController(text: existing?.repo ?? 'xiamend');
    final branch = TextEditingController(text: existing?.branch ?? 'main');
    final posts = TextEditingController(
      text: existing?.postsPath ?? 'source/_posts',
    );
    final site = TextEditingController(
      text: existing?.siteUrl ?? 'https://caogenfunan.me/',
    );
    final token = TextEditingController(
      text: existing?.token.isNotEmpty == true
          ? existing!.token
          : settings.effectiveGithubToken,
    );
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
                    TextField(controller: name, decoration: const InputDecoration(labelText: '显示名称')),
                    TextField(controller: owner, decoration: const InputDecoration(labelText: 'Owner')),
                    TextField(controller: repo, decoration: const InputDecoration(labelText: 'Repo')),
                    TextField(controller: branch, decoration: const InputDecoration(labelText: 'Branch')),
                    TextField(controller: posts, decoration: const InputDecoration(labelText: '文章目录')),
                    TextField(controller: site, decoration: const InputDecoration(labelText: '站点 URL')),
                    if (settings.githubTokens.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: settings.githubTokens.any((e) => e.id == selectedTokenId)
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
                              child: Text(t.displayLabel, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          final t = settings.githubTokens.firstWhere((e) => e.id == v);
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
                      decoration: const InputDecoration(labelText: 'GitHub Token'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;

    final tokenValue = token.text.trim();
    final cfg = RepoConfig(
      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.text.trim().isEmpty ? repo.text.trim() : name.text.trim(),
      owner: owner.text.trim(),
      repo: repo.text.trim(),
      branch: branch.text.trim().isEmpty ? 'main' : branch.text.trim(),
      postsPath:
          posts.text.trim().isEmpty ? 'source/_posts' : posts.text.trim(),
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

    // 新填入的 token 自动纳入已登录列表
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
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
      _toast('无提交历史');
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
      _toast('路径不能为空');
      return;
    }
    final ok = await _confirm('将 $path 恢复为 $sha 的内容并新建提交？');
    if (!ok) return;
    setState(() => busy = true);
    try {
      final article = await github.rollbackFile(repo, path, sha);
      _toast('回滚成功: ${article.remotePath}');
      await _refreshRemote();
      await _refreshCommits();
    } catch (e) {
      _toast('回滚失败: $e');
    } finally {
      if (mounted) setState(() => busy = false);
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
              Clipboard.setData(ClipboardData(text: site));
              Navigator.pop(ctx);
              _toast('站点地址已复制');
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


  Future<void> _deleteRemotePost(GitHubFileItem item) async {
    final repo = effectiveRepo;
    if (repo == null) return;
    final ok = await _confirm('确认删除远程文章 ${item.path}？此操作会提交到 GitHub，不可撤销。');
    if (!ok) return;
    setState(() => busy = true);
    try {
      // 先拉取完整文章以拿到 sha
      final article = await github.getArticle(repo, item);
      await github.deleteArticle(repo, article);
      // 同步本地：若有对应草稿，标记为未发布并清 remote
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
      _toast('已删除远程文章');
      await _refreshRemote();
      await _refreshCommits();
    } catch (e) {
      _toast('删除失败: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _showAiManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final profiles = List<AiProfile>.from(settings.aiProfiles);
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
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
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final created = await _editAiProfile(null);
                            if (created != null) {
                              final list = List<AiProfile>.from(settings.aiProfiles)..add(created);
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
                              _toast('已保存配置');
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
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: profiles.isEmpty
                          ? const Center(child: Text('暂无配置，点右上角新增'))
                          : ListView.separated(
                              itemCount: profiles.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final p = profiles[i];
                                final active = settings.activeAiProfileId == p.id;
                                return Card(
                                  child: ListTile(
                                    leading: Icon(
                                      active ? Icons.check_circle : Icons.smart_toy_outlined,
                                      color: active ? Theme.of(ctx).colorScheme.primary : null,
                                    ),
                                    title: Text(p.displayLabel),
                                    subtitle: Text(
                                      '${p.baseUrl}\n模型: ${p.model.isEmpty ? "未选" : p.model}',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    isThreeLine: true,
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (v) async {
                                        if (v == 'use') {
                                          settings = settings.copyWith(
                                            activeAiProfileId: p.id,
                                            aiBaseUrl: p.baseUrl,
                                            aiApiKey: p.apiKey,
                                            aiModel: p.model,
                                            aiProvider: p.name,
                                          );
                                          await _persistSettings();
                                          setModal(() {});
                                          if (mounted) setState(() {});
                                          _toast('已切换到 ${p.displayLabel}');
                                        } else if (v == 'edit') {
                                          final edited = await _editAiProfile(p);
                                          if (edited != null) {
                                            final list = List<AiProfile>.from(settings.aiProfiles);
                                            final ix = list.indexWhere((e) => e.id == p.id);
                                            if (ix >= 0) list[ix] = edited;
                                            final activeId = settings.activeAiProfileId == p.id
                                                ? edited.id
                                                : settings.activeAiProfileId;
                                            settings = settings.copyWith(
                                              aiProfiles: list,
                                              activeAiProfileId: activeId,
                                              aiBaseUrl: activeId == edited.id ? edited.baseUrl : settings.aiBaseUrl,
                                              aiApiKey: activeId == edited.id ? edited.apiKey : settings.aiApiKey,
                                              aiModel: activeId == edited.id ? edited.model : settings.aiModel,
                                              aiProvider: activeId == edited.id ? edited.name : settings.aiProvider,
                                            );
                                            await _persistSettings();
                                            setModal(() {});
                                            if (mounted) setState(() {});
                                          }
                                        } else if (v == 'delete') {
                                          final ok = await _confirm('删除配置「${p.name}」？');
                                          if (!ok) return;
                                          final list = List<AiProfile>.from(settings.aiProfiles)
                                            ..removeWhere((e) => e.id == p.id);
                                          var activeId = settings.activeAiProfileId;
                                          if (activeId == p.id) {
                                            activeId = list.isNotEmpty ? list.first.id : '';
                                          }
                                          AiProfile? activeP;
                                          for (final e in list) {
                                            if (e.id == activeId) {
                                              activeP = e;
                                              break;
                                            }
                                          }
                                          if (activeP == null && list.isNotEmpty) {
                                            activeP = list.first;
                                            activeId = activeP.id;
                                          }
                                          settings = settings.copyWith(
                                            aiProfiles: list,
                                            activeAiProfileId: activeId,
                                            aiBaseUrl: activeP?.baseUrl ?? settings.aiBaseUrl,
                                            aiApiKey: activeP?.apiKey ?? '',
                                            aiModel: activeP?.model ?? settings.aiModel,
                                            aiProvider: activeP?.name ?? settings.aiProvider,
                                          );
                                          await _persistSettings();
                                          setModal(() {});
                                          if (mounted) setState(() {});
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'use', child: Text('设为当前')),
                                        PopupMenuItem(value: 'edit', child: Text('编辑')),
                                        PopupMenuItem(value: 'delete', child: Text('删除')),
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
                                      if (mounted) setState(() {});
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

  AppSettings _ensureGithubTokensFromLegacy(
    AppSettings s,
    List<RepoConfig> repoList,
  ) {
    final list = List<GithubTokenProfile>.from(s.githubTokens);
    final seen = {for (final t in list) t.token.trim()};

    void addToken(String token, String name) {
      final t = token.trim();
      if (t.isEmpty || seen.contains(t)) return;
      seen.add(t);
      list.add(
        GithubTokenProfile(
          id: 'gh_${DateTime.now().millisecondsSinceEpoch}_${list.length}',
          name: name,
          token: t,
        ),
      );
    }

    addToken(s.defaultToken, '默认 Token');
    for (final r in repoList) {
      addToken(r.token, r.name.isNotEmpty ? r.name : '仓库 Token');
    }

    if (list.isEmpty) return s;
    final activeId = s.activeGithubTokenId.isNotEmpty &&
            list.any((e) => e.id == s.activeGithubTokenId)
        ? s.activeGithubTokenId
        : list.first.id;
    final activeToken = list.firstWhere((e) => e.id == activeId).token;
    return s.copyWith(
      githubTokens: list,
      activeGithubTokenId: activeId,
      defaultToken: activeToken,
    );
  }

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

    // 当前仓库 token 为空时，自动填入当前登录令牌
    final repo = activeRepo;
    if (repo != null && repo.token.isEmpty) {
      final i = repos.indexWhere((e) => e.id == repo.id);
      if (i >= 0) {
        repos[i] = repo.copyWith(token: profile.token);
        await _persistRepos();
      }
    }
    if (mounted) setState(() {});
    _toast('已切换到 ${profile.displayLabel}');
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

  Future<void> _showGithubTokenManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final tokens = List<GithubTokenProfile>.from(settings.githubTokens);
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
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
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final created = await _editGithubToken(null);
                            if (created != null) {
                              await _upsertGithubToken(created, makeActive: true);
                              setModal(() {});
                              if (mounted) setState(() {});
                              _toast('已保存 ${created.displayLabel}');
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
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: tokens.isEmpty
                          ? const Center(child: Text('暂无已登录令牌，点右上角登录'))
                          : ListView.separated(
                              itemCount: tokens.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final t = tokens[i];
                                final active = settings.activeGithubTokenId == t.id;
                                return Card(
                                  child: ListTile(
                                    leading: Icon(
                                      active ? Icons.check_circle : Icons.key_outlined,
                                      color: active ? Theme.of(ctx).colorScheme.primary : null,
                                    ),
                                    title: Text(t.displayLabel),
                                    subtitle: Text(
                                      [
                                        if (t.login.isNotEmpty) '@${t.login}',
                                        t.maskedToken,
                                        if (t.lastVerifiedAt != null)
                                          '验证于 ${t.lastVerifiedAt!.toLocal().toString().substring(0, 16)}',
                                      ].join(' · '),
                                    ),
                                    isThreeLine: t.lastVerifiedAt != null,
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (v) async {
                                        if (v == 'use') {
                                          await _activateGithubToken(t.id);
                                          setModal(() {});
                                        } else if (v == 'edit') {
                                          final edited = await _editGithubToken(t);
                                          if (edited != null) {
                                            await _upsertGithubToken(
                                              edited,
                                              makeActive: settings.activeGithubTokenId == t.id,
                                            );
                                            setModal(() {});
                                          }
                                        } else if (v == 'verify') {
                                          try {
                                            final user = await github.getUser(t.token);
                                            final login = user['login']?.toString() ?? '';
                                            await _upsertGithubToken(
                                              t.copyWith(
                                                login: login,
                                                avatarUrl: user['avatar_url']?.toString() ?? '',
                                                htmlUrl: user['html_url']?.toString() ?? '',
                                                lastVerifiedAt: DateTime.now(),
                                                name: t.name.isEmpty || t.name == '默认 Token' || t.name == 'GitHub Token'
                                                    ? (login.isNotEmpty ? login : t.name)
                                                    : t.name,
                                              ),
                                              makeActive: active,
                                            );
                                            setModal(() {});
                                            _toast(login.isEmpty ? 'Token 有效' : '有效 · @$login');
                                          } catch (e) {
                                            _toast('校验失败: $e');
                                          }
                                        } else if (v == 'delete') {
                                          final ok = await _confirm('删除已保存令牌「${t.displayLabel}」？');
                                          if (!ok) return;
                                          final list = List<GithubTokenProfile>.from(settings.githubTokens)
                                            ..removeWhere((e) => e.id == t.id);
                                          var activeId = settings.activeGithubTokenId;
                                          if (activeId == t.id) {
                                            activeId = list.isNotEmpty ? list.first.id : '';
                                          }
                                          final activeToken = list.isEmpty
                                              ? ''
                                              : list.firstWhere(
                                                  (e) => e.id == activeId,
                                                  orElse: () => list.first,
                                                ).token;
                                          settings = settings.copyWith(
                                            githubTokens: list,
                                            activeGithubTokenId: activeId,
                                            defaultToken: activeToken,
                                          );
                                          await _persistSettings();
                                          setModal(() {});
                                          if (mounted) setState(() {});
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'use', child: Text('设为当前')),
                                        PopupMenuItem(value: 'verify', child: Text('验证')),
                                        PopupMenuItem(value: 'edit', child: Text('编辑')),
                                        PopupMenuItem(value: 'delete', child: Text('删除')),
                                      ],
                                    ),
                                    onTap: () async {
                                      await _activateGithubToken(t.id);
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

  Future<GithubTokenProfile?> _editGithubToken(GithubTokenProfile? existing) async {
    final nameCtrl = TextEditingController(
      text: existing?.name.isNotEmpty == true
          ? existing!.name
          : (existing?.login.isNotEmpty == true ? existing!.login : 'GitHub Token'),
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
                _toast(login.isEmpty ? 'Token 有效' : '验证成功 · @$login');
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
                        Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: verifying ? null : verifyAndFill,
                          icon: verifying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
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
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                FilledButton(
                  onPressed: verifying
                      ? null
                      : () async {
                          final token = tokenCtrl.text.trim();
                          if (token.isEmpty) {
                            _toast('请填写 Token');
                            return;
                          }
                          // 保存前尽量验证一次（失败也允许用户强制保存）
                          if (login.isEmpty) {
                            try {
                              final user = await github.getUser(token);
                              login = user['login']?.toString() ?? '';
                              avatarUrl = user['avatar_url']?.toString() ?? '';
                              htmlUrl = user['html_url']?.toString() ?? '';
                            } catch (e) {
                              final force = await _confirm('Token 校验失败：\n$e\n\n仍要保存吗？');
                              if (!force) return;
                            }
                          }
                          final name = nameCtrl.text.trim().isEmpty
                              ? (login.isNotEmpty ? login : 'GitHub Token')
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
                              lastVerifiedAt: login.isNotEmpty ? DateTime.now() : existing?.lastVerifiedAt,
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

  Future<AiProfile?> _editAiProfile(AiProfile? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '中转站');
    final baseCtrl = TextEditingController(
      text: existing?.baseUrl.isNotEmpty == true
          ? existing!.baseUrl
          : (settings.aiBaseUrl.isNotEmpty ? settings.aiBaseUrl : 'https://api.openai.com/v1'),
    );
    final keyCtrl = TextEditingController(
      text: existing?.apiKey.isNotEmpty == true ? existing!.apiKey : settings.aiApiKey,
    );
    final modelCtrl = TextEditingController(text: existing?.model ?? settings.aiModel);
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
                  name: nameCtrl.text.trim().isEmpty ? '中转站' : nameCtrl.text.trim(),
                  baseUrl: baseCtrl.text.trim(),
                  apiKey: keyCtrl.text.trim(),
                  model: modelCtrl.text.trim(),
                  useBearer: useBearer,
                  cachedModels: models,
                );
                final list = await AiService().listModels(settings, profile: temp);
                setDlg(() {
                  models = list;
                  if (selectedModel.isEmpty && list.isNotEmpty) {
                    selectedModel = list.first;
                    modelCtrl.text = selectedModel;
                  } else if (selectedModel.isNotEmpty && list.contains(selectedModel)) {
                    modelCtrl.text = selectedModel;
                  }
                  fetching = false;
                });
                if (list.isEmpty) {
                  _toast('未拉到模型，可手动填写模型名');
                } else {
                  _toast('已获取 ${list.length} 个模型');
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
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('获取模型'),
                          ),
                        ],
                      ),
                      if (err != null) ...[
                        const SizedBox(height: 8),
                        Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      ],
                      if (models.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: models.contains(selectedModel) ? selectedModel : null,
                          decoration: const InputDecoration(labelText: '从列表选择模型'),
                          items: models
                              .map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
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
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                FilledButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim().isEmpty ? '中转站' : nameCtrl.text.trim();
                    final base = baseCtrl.text.trim();
                    final key = keyCtrl.text.trim();
                    final model = modelCtrl.text.trim();
                    if (base.isEmpty) {
                      _toast('请填写 Base URL');
                      return;
                    }
                    if (key.isEmpty) {
                      _toast('请填写 API Key');
                      return;
                    }
                    if (model.isEmpty) {
                      _toast('请选择或填写模型');
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

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    return ok == true;
  }

  String _fmt(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

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
                TextField(controller: c, decoration: const InputDecoration(labelText: 'WebDAV 网址', hintText: 'https://dav.jianguoyun.com/dav')),
                const SizedBox(height: 12),
                TextField(controller: u, decoration: const InputDecoration(labelText: '账号')),
                const SizedBox(height: 12),
                TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: '密码')),
                const SizedBox(height: 12),
                TextField(controller: f, decoration: const InputDecoration(labelText: '文件夹')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                settings = settings.copyWith(
                  webdavUrl: c.text.trim(),
                  webdavUsername: u.text.trim(),
                  webdavPassword: pw.text,
                  webdavFolder: f.text.trim().isEmpty ? 'hexo-backup' : f.text.trim(),
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

  Future<void> _showThemeColorPicker() async {
    final colors = [
      const Color(0xFF0EA5E9), // 天蓝
      const Color(0xFF6366F1), // 靛蓝
      const Color(0xFF8B5CF6), // 紫色
      const Color(0xFFEC4899), // 粉色
      const Color(0xFFF43F5E), // 玫瑰红
      const Color(0xFF10B981), // 翡翠绿
      const Color(0xFF14B8A6), // 青绿
      const Color(0xFFF59E0B), // 琥珀
      const Color(0xFF64748B), // 石板灰
      const Color(0xFF1E293B), // 深灰
    ];
    final names = ['天蓝', '靛蓝', '紫色', '粉色', '玫瑰红', '翡翠绿', '青绿', '琥珀', '石板灰', '深灰'];
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
                  _toast('主题色已切换为${names[i]}');
                  Navigator.pop(ctx);
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _importLocalMd() async {
    try {
      final result = await _channel.invokeMethod<Map>('pickFile');
      if (result == null) return;
      final b64 = result['base64']?.toString() ?? '';
      final name = result['name']?.toString() ?? 'untitled.md';
      if (b64.isEmpty) return;
      final content = utf8.decode(base64Decode(b64));
      final article = Article.fromMarkdown(content,
          id: DateTime.now().millisecondsSinceEpoch.toString());
      await _openEditor(article: article);
    } catch (e) {
      _toast('导入失败: $e');
    }
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
      final folder = settings.webdavFolder.endsWith('/') ? settings.webdavFolder : '${settings.webdavFolder}/';
      final remote = await svc.list(settings.webdavUrl, settings.webdavUsername, settings.webdavPassword, folder);
      final localIds = drafts.map((a) => '${a.id}.md').toSet();
      int count = 0;
      for (final item in remote) {
        if (!item.isDir && item.name.endsWith('.md')) {
          final id = item.name.replaceAll(RegExp(r'\.md$'), '');
          if (!localIds.contains(item.name)) {
            final bytes = await svc.downloadFile(settings.webdavUrl, settings.webdavUsername, settings.webdavPassword, folder, item.name);
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
          this.drafts = drafts..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        });
        _toast('已从云端同步 $count 篇草稿到本地');
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => loading = false);
        _toast('WebDAV 同步失败: $e');
      }
    }
  }

  Future<void> _showSiteEditor() async {
    final repo = effectiveRepo;
    if (repo == null) {
      _toast('请先配置仓库');
      return;
    }

    loading = true;
    if (mounted) setState(() {});

    // 从 GitHub 加载当前站点文件
    String siteDescription = '个人博客 - 分享技术、生活与思考';
    String siteTitle = '小子的博客';
    String siteSubtitle = '记录生活的点滴';
    String siteAuthor = '小子';
    String avatarUrl = '';
    String headerText = '记录生活的点滴';
    String footerInfo = '小子的博客 · https://xiamend.pages.dev';
    String aboutContent = '';
    String guestbookContent = '';
    String nowContent = '';
    String worksContent = '';
    String indexContent = '';

    try {
      final g = GitHubService();
      final configRaw = await g.getRawFile(repo, '_config.yml');
      if (configRaw != null) {
        final c = configRaw['content']!;
        final titleMatch = RegExp(r'^title:\s*(.*)$', multiLine: true).firstMatch(c);
        if (titleMatch != null) siteTitle = titleMatch.group(1)!.trim();
        final subtitleMatch = RegExp(r"^subtitle:\s*'([^']*)'", multiLine: true).firstMatch(c);
        if (subtitleMatch != null) siteSubtitle = subtitleMatch.group(1)!.trim();
        final authorMatch = RegExp(r'^author:\s*(.*)$', multiLine: true).firstMatch(c);
        final descMatch = RegExp(r"^description:\s*'([^']*)'", multiLine: true).firstMatch(c);
        if (descMatch != null) siteDescription = descMatch.group(1)!.trim();
        if (authorMatch != null) siteAuthor = authorMatch.group(1)!.trim();
      }

      final themeRaw = await g.getRawFile(repo, 'themes/A4/_config.yml');
      if (themeRaw != null) {
        final themeContent = themeRaw['content']!;
        for (final line in themeContent.split('\n')) {
          final t = line.trim();
          if (t.startsWith('favicon:')) avatarUrl = t.substring(8).trim();
        }
        final footerMatch = RegExp(r'footer:\s*"([^"]*)"').firstMatch(themeContent);
        if (footerMatch != null) footerInfo = footerMatch.group(1) ?? footerInfo;
        final headerMatch = RegExp(r'header:\s*\n((?:\s*-\s*"[^"]*"\n?)+)').firstMatch(themeContent);
        if (headerMatch != null) {
          headerText = headerMatch.group(1)!
              .split(RegExp(r'\s*-\s*"|"\n?\s*'))
              .where((s) => s.isNotEmpty)
              .join('\n');
        }
      }

      final aboutRaw = await g.getRawFile(repo, 'source/about/index.md');
      if (aboutRaw != null) aboutContent = aboutRaw['content']!;
      final guestbookRaw = await g.getRawFile(repo, 'source/comments/index.md');
      if (guestbookRaw != null) guestbookContent = guestbookRaw['content']!;
      final nowRaw = await g.getRawFile(repo, 'source/now/index.md');
      if (nowRaw != null) nowContent = nowRaw['content']!;
      final worksRaw = await g.getRawFile(repo, 'source/works/index.md');
      if (worksRaw != null) worksContent = worksRaw['content']!;
      final indexRaw = await g.getRawFile(repo, 'source/index/index.md');
      if (indexRaw != null) indexContent = indexRaw['content']!;
    } catch (e) {
      if (mounted) _toast('加载站点配置失败: $e');
    }

    if (mounted) setState(() => loading = false);

    // 用全屏页面替代 AlertDialog，避免手机上操作困难
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _SiteEditorPage(
          repo: repo,
          initialSiteDescription: siteDescription,
          initialSiteTitle: siteTitle,
          initialSiteSubtitle: siteSubtitle,
          initialSiteAuthor: siteAuthor,
          initialAvatarUrl: avatarUrl,
          initialHeaderText: headerText,
          initialFooterInfo: footerInfo,
          initialAboutContent: aboutContent,
          initialGuestbookContent: guestbookContent,
          initialNowContent: nowContent,
          initialWorksContent: worksContent,
          initialIndexContent: indexContent,
        ),
      ),
    );
    if (mounted) setState(() {});
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
      if (mounted) {
        setState(() => loading = false);
        _toast('已上传 $count 篇草稿');
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => loading = false);
        _toast('WebDAV 失败: $e');
      }
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, {this.color = const Color(0xFF64748B)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SiteEditorPage extends StatefulWidget {
  final RepoConfig repo;
  final String initialSiteDescription;
  final String initialSiteTitle;

  final String initialSiteSubtitle;
  final String initialSiteAuthor;
  final String initialAvatarUrl;
  final String initialHeaderText;
  final String initialFooterInfo;
  final String initialAboutContent;
  final String initialGuestbookContent;
  final String initialNowContent;
  final String initialWorksContent;
  final String initialIndexContent;

  const _SiteEditorPage({
    required this.repo,
    required this.initialSiteDescription,
    required this.initialSiteTitle,

    required this.initialSiteSubtitle,
    required this.initialSiteAuthor,
    required this.initialAvatarUrl,
    required this.initialHeaderText,
    required this.initialFooterInfo,
    required this.initialAboutContent,
    required this.initialGuestbookContent,
    required this.initialNowContent,
    required this.initialWorksContent,
    required this.initialIndexContent,
  });

  @override
  State<_SiteEditorPage> createState() => _SiteEditorPageState();
}

class _SiteEditorPageState extends State<_SiteEditorPage> {
  late TextEditingController _descCtrl;

  late TextEditingController _titleCtrl;
  late TextEditingController _subtitleCtrl;
  late TextEditingController _authorCtrl;
  late TextEditingController _avatarCtrl;
  late TextEditingController _headerCtrl;
  late TextEditingController _footerCtrl;
  late TextEditingController _aboutCtrl;
  late TextEditingController _guestbookCtrl;
  late TextEditingController _nowCtrl;
  late TextEditingController _worksCtrl;
  late TextEditingController _indexCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.initialSiteDescription);

    _titleCtrl = TextEditingController(text: widget.initialSiteTitle);
    _subtitleCtrl = TextEditingController(text: widget.initialSiteSubtitle);
    _authorCtrl = TextEditingController(text: widget.initialSiteAuthor);
    _avatarCtrl = TextEditingController(text: widget.initialAvatarUrl);
    _headerCtrl = TextEditingController(text: widget.initialHeaderText);
    _footerCtrl = TextEditingController(text: widget.initialFooterInfo);
    _aboutCtrl = TextEditingController(text: widget.initialAboutContent);
    _guestbookCtrl = TextEditingController(text: widget.initialGuestbookContent);
    _nowCtrl = TextEditingController(text: widget.initialNowContent);
    _worksCtrl = TextEditingController(text: widget.initialWorksContent);
    _indexCtrl = TextEditingController(text: widget.initialIndexContent);
  }

  @override
  void dispose() {
    _descCtrl.dispose();

    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _authorCtrl.dispose();
    _avatarCtrl.dispose();
    _headerCtrl.dispose();
    _footerCtrl.dispose();
    _aboutCtrl.dispose();
    _guestbookCtrl.dispose();
    _nowCtrl.dispose();
    _worksCtrl.dispose();
    _indexCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final g = GitHubService();

      // 1. 更新 _config.yml
      final configRaw = await g.getRawFile(widget.repo, '_config.yml');
      if (configRaw != null) {
        String cc = configRaw['content']!;
        cc = cc
            .replaceAll(RegExp(r'^title:.*$', multiLine: true), 'title: ${_titleCtrl.text.trim()}')
            .replaceAll(RegExp(r'^subtitle:.*$', multiLine: true), "subtitle: '${_subtitleCtrl.text.trim()}'")
            .replaceAll(RegExp(r'^author:.*$', multiLine: true), 'author: ${_authorCtrl.text.trim()}')
            .replaceAll(RegExp(r'^description:.*$', multiLine: true), "description: '${_descCtrl.text.trim()}'");
        await g.putRawFile(widget.repo, '_config.yml', cc, sha: configRaw['sha']);
      }

      // 2. 更新 themes/A4/_config.yml
      final themeRaw = await g.getRawFile(widget.repo, 'themes/A4/_config.yml');
      if (themeRaw != null) {
        String tc = themeRaw['content']!;
        tc = tc
            .replaceAll(RegExp(r'^favicon:.*$', multiLine: true), 'favicon: ${_avatarCtrl.text.trim()}')
            .replaceAll(RegExp(r'^  footer:.*$', multiLine: true), '  footer: "${_footerCtrl.text.trim()}"');
        // 修复 index.header — 替换整个 header 块为多行 YAML 列表
        final headerBlockRe = RegExp(r'^  header:.*?(?=^\s{2}\w)', multiLine: true, dotAll: true);
        final headerVal = _headerCtrl.text.trim();
        if (headerVal.isNotEmpty) {
          final lines = headerVal.split('\n').map((l) => '    - "${l.trim()}"').join('\n');
          tc = tc.replaceAllMapped(headerBlockRe, (m) => '  header:\n$lines');
        }
        await g.putRawFile(widget.repo, 'themes/A4/_config.yml', tc, sha: themeRaw['sha']);
      }

      // 3. 更新页面文件
      Future<void> savePage(String path, String content) async {
        final existing = await g.getRawFile(widget.repo, path);
        await g.putRawFile(widget.repo, path, content, sha: existing?['sha']);
      }

      await savePage('source/about/index.md', _aboutCtrl.text);
      await savePage('source/comments/index.md', _guestbookCtrl.text);
      await savePage('source/now/index.md', _nowCtrl.text);
      await savePage('source/works/index.md', _worksCtrl.text);
      await savePage('source/index/index.md', _indexCtrl.text);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('站点内容已同步到 GitHub，稍后自动部署')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网站页面编辑'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('编辑后保存将直接同步到 GitHub 仓库，自动触发部署',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            TextField(controller: _descCtrl,
                decoration: const InputDecoration(
                    labelText: '网站描述 (description)', hintText: '个人博客 - 分享技术、生活与思考')),
            const SizedBox(height: 12),
            TextField(controller: _avatarCtrl,
                decoration: const InputDecoration(
                    labelText: '头像 / Favicon 路径', hintText: '/img/favicon.png')),
            const SizedBox(height: 12),
            TextField(controller: _titleCtrl,
                decoration: const InputDecoration(labelText: '网站标题 (title)')),
            const SizedBox(height: 12),
            TextField(controller: _subtitleCtrl,
                decoration: const InputDecoration(labelText: '副标题 (subtitle)')),
            const SizedBox(height: 12),
            TextField(controller: _authorCtrl,
                decoration: const InputDecoration(labelText: '作者 (author)')),
            const SizedBox(height: 12),
            TextField(controller: _headerCtrl, maxLines: 3,
                decoration: const InputDecoration(
                    labelText: '首页头部文字 (每行一句)',
                    hintText: '记录生活美好\n写字，是为了把日子留住\n看过大海的人不会忘记海的广阔',
                    helperText: '每行一句，保存后会自动替换首页头部')),
            const SizedBox(height: 12),
            TextField(controller: _footerCtrl,
                decoration: const InputDecoration(labelText: '页脚信息')),
            const SizedBox(height: 16),
            const Divider(),
            const Text('页面内容 (Markdown)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(controller: _aboutCtrl, maxLines: 5,
                decoration: const InputDecoration(
                    labelText: '关于页面 (source/about/index.md)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _guestbookCtrl, maxLines: 5,
                decoration: const InputDecoration(
                    labelText: '留言页面 (source/comments/index.md)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _nowCtrl, maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Now 页面 (source/now/index.md)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _worksCtrl, maxLines: 5,
                decoration: const InputDecoration(
                    labelText: '作品页面 (source/works/index.md)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _indexCtrl, maxLines: 5,
                decoration: const InputDecoration(
                    labelText: '首页内容 (source/index/index.md)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 32),
            Center(
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload),
                label: Text(_saving ? '保存中…' : '保存并同步到 GitHub'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
