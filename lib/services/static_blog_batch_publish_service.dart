import '../models/article.dart';
import '../models/article_type.dart';
import '../models/blog_post.dart';
import '../models/repo_config.dart';
import '../models/template_item.dart';
import '../core/site_manager.dart';
import '../core/template_engine/template_resolver.dart';
import '../core/diff/markdown_diff.dart';
import 'github_service.dart';
import 'storage_service.dart';

/// 单个站点的发布预览
class SitePublishPreview {
  final RepoConfig repo;
  final String path; // 目标路径
  final String newContent; // 将写入的完整内容
  final String? oldContent; // 远程旧内容（null=新建文件）
  final String? remoteSha; // 远程旧文件 sha（新建为 null）
  final String? templateName; // 解析到的默认模板名
  final bool loggedIn; // token 是否有效
  final String? loginError; // 未登录原因
  final LineDiffResult diff; // 行级差异

  const SitePublishPreview({
    required this.repo,
    required this.path,
    required this.newContent,
    this.oldContent,
    this.remoteSha,
    this.templateName,
    required this.loggedIn,
    this.loginError,
    required this.diff,
  });

  bool get isNewFile => diff.isNewFile;
  String get siteName => repo.name;
}

/// 多站点发布预览（聚合各站点）
class MultiSitePublishPreview {
  final List<SitePublishPreview> sites;

  const MultiSitePublishPreview({required this.sites});

  /// 可发布站点（token 有效）
  List<SitePublishPreview> get publishable =>
      sites.where((s) => s.loggedIn).toList();

  int get newFileCount => sites.where((s) => s.isNewFile).length;
  int get updateCount =>
      sites.where((s) => !s.isNewFile && s.loggedIn).length;
  int get skippedCount => sites.where((s) => !s.loggedIn).length;
}

/// 静态博客批量发布服务
///
/// 将一篇文章转换后批量发布到所有（或指定）静态博客仓库。
/// 每个目标站点对应一个 [RepoConfig]：
/// - 使用每站独立默认模板（[TemplateResolver.resolvePostTemplate]）渲染，
///   与单站发布 `upsertArticle` 输出一致；
/// - 发布前可调用 [buildPreview] 生成只读预览（目标路径 + 完整内容 + 行级
///   差异），确认后再通过 [publishFromPreview] / [batchPublishToStaticBlogs]
///   经 GitHub Contents API 真实写入。
class StaticBlogBatchPublishService {
  final SiteManager _siteManager;
  final GitHubService _githubService;
  final StorageService _storage;

  /// 登录态缓存：按 token 缓存校验结果，避免逐站/逐篇重复 GET /user
  final Map<String, _LoginCacheEntry> _loginCache = {};
  static const _loginCacheTtl = Duration(minutes: 5);

  StaticBlogBatchPublishService({
    required SiteManager siteManager,
    required GitHubService githubService,
    StorageService? storageService,
  })  : _siteManager = siteManager,
        _githubService = githubService,
        _storage = storageService ?? StorageService();

  /// 生成批量发布预览（只读，不产生任何 GitHub 写入）。
  ///
  /// [post] 要发布的文章；[selectedSiteIds] 为空则覆盖全部静态仓库。
  /// 登录态校验与远程旧内容拉取均以有界并发执行（默认 4 路），登录态带
  /// 5 分钟缓存；逐站按每站默认模板渲染并计算行级差异。
  Future<MultiSitePublishPreview> buildPreview(
    BlogPost post, {
    List<String>? selectedSiteIds,
  }) async {
    final templates = await _storage.loadAllTemplates();
    final targetRepos = _targetRepos(selectedSiteIds);

    // 并发校验登录态（带缓存）
    final logins = await _runPool(targetRepos, _checkLogin);

    // 并发拉取远程旧内容（仅已登录站点）
    final remotes = await _runPool(
      targetRepos.indexed.toList(),
      (entry) async {
        final repo = entry.$2;
        if (!logins[entry.$1].verified) {
          return const _RemoteContent(null, null);
        }
        final existing =
            await _githubService.getRawFile(repo, _pathFor(post, repo));
        return _RemoteContent(existing?['content'], existing?['sha']);
      },
    );

    final sites = <SitePublishPreview>[];
    for (var i = 0; i < targetRepos.length; i++) {
      final repo = targetRepos[i];
      final login = logins[i];
      final remote = remotes[i];
      final path = _pathFor(post, repo);
      final newContent = _renderForRepo(post, repo, templates);
      final tpl = TemplateResolver.resolvePostTemplate(repo, templates);
      final oldContent = remote.content;
      final diff = oldContent != null
          ? MarkdownDiff.diffText(oldContent, newContent)
          : MarkdownDiff.diffText('', newContent);

      sites.add(SitePublishPreview(
        repo: repo,
        path: path,
        newContent: newContent,
        oldContent: oldContent,
        remoteSha: remote.sha,
        templateName: tpl?.name,
        loggedIn: login.verified,
        loginError: login.error,
        diff: diff,
      ));
    }

    return MultiSitePublishPreview(sites: sites);
  }

  /// 批量发布文章到所有静态博客站点
  ///
  /// [post] 要发布的文章
  /// [selectedSiteIds] 选定的站点 ID 列表，为空则发布到所有静态站点
  /// [onProgress] 进度回调（当前序号、总数、消息）
  /// [onComplete] 完成回调（是否全部成功、汇总消息、分站点结果）
  Future<void> batchPublishToStaticBlogs(
    BlogPost post, {
    List<String>? selectedSiteIds,
    Function(int, int, String)? onProgress,
    Function(bool, String, Map<String, dynamic>)? onComplete,
  }) async {
    try {
      final templates = await _storage.loadAllTemplates();
      final targetRepos = _targetRepos(selectedSiteIds);

      if (targetRepos.isEmpty) {
        onComplete?.call(false, '没有找到可用的静态博客站点', {});
        return;
      }

      final total = targetRepos.length;
      var successCount = 0;
      var failCount = 0;
      final results = <String, dynamic>{};

      for (int i = 0; i < targetRepos.length; i++) {
        final repo = targetRepos[i];
        final siteName = repo.name;

        try {
          if (repo.token.isEmpty) {
            throw Exception('未配置 GitHub Token');
          }
          onProgress?.call(i + 1, total, '正在发布到 $siteName...');

          final converted = _renderForRepo(post, repo, templates);
          final path = _pathFor(post, repo);

          await _putWithSha(repo, path, converted, post);

          successCount++;
          results[siteName] = {
            'success': true,
            'message': '发布成功 → $path',
            'repo': repo.fullName,
          };
        } catch (e) {
          failCount++;
          results[siteName] = {
            'success': false,
            'message': e.toString(),
            'repo': repo.fullName,
          };
        }
      }

      final success = failCount == 0;
      final message = success
          ? '成功发布到所有 $total 个站点'
          : '发布完成：成功 $successCount 个，失败 $failCount 个';

      onComplete?.call(success, message, results);
    } catch (e) {
      onComplete?.call(false, '批量发布失败: ${e.toString()}', {});
    }
  }

  /// 依据已确认的预览执行发布（仅写入可发布站点）。
  ///
  /// 写入前重新探测远程 sha，避免预览后远程被他人更新导致覆盖冲突。
  Future<void> publishFromPreview(
    BlogPost post,
    MultiSitePublishPreview preview, {
    Function(int, int, String)? onProgress,
    Function(bool, String, Map<String, dynamic>)? onComplete,
  }) async {
    final targets = preview.publishable;
    if (targets.isEmpty) {
      onComplete?.call(false, '没有可发布的站点（全部未登录）', {});
      return;
    }

    final total = targets.length;
    var successCount = 0;
    var failCount = 0;
    final results = <String, dynamic>{};

    for (int i = 0; i < targets.length; i++) {
      final site = targets[i];
      final siteName = site.siteName;
      try {
        onProgress?.call(i + 1, total, '正在发布到 $siteName...');
        await _putWithSha(site.repo, site.path, site.newContent, post);
        successCount++;
        results[siteName] = {
          'success': true,
          'message': '发布成功 → ${site.path}',
          'repo': site.repo.fullName,
        };
      } catch (e) {
        failCount++;
        results[siteName] = {
          'success': false,
          'message': e.toString(),
          'repo': site.repo.fullName,
        };
      }
    }

    final success = failCount == 0;
    final message = success
        ? '成功发布到所有 $total 个站点'
        : '发布完成：成功 $successCount 个，失败 $failCount 个';
    onComplete?.call(success, message, results);
  }

  /// 目标仓库列表（选定 ID 或全部静态仓库，默认站点优先）
  List<RepoConfig> _targetRepos(List<String>? selectedSiteIds) {
    final staticRepos = List<RepoConfig>.from(_siteManager.staticRepos)
      ..sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));
    return selectedSiteIds != null
        ? staticRepos.where((r) => selectedSiteIds.contains(r.id)).toList()
        : staticRepos;
  }

  /// 校验单仓库登录态（带 5 分钟 TTL 缓存，按 token 复用）
  Future<_LoginResult> _checkLogin(RepoConfig repo) async {
    final token = repo.token.trim();
    if (token.isEmpty) {
      return const _LoginResult(false, '未配置 GitHub Token');
    }
    final now = DateTime.now();
    final cached = _loginCache[token];
    if (cached != null && now.difference(cached.at) < _loginCacheTtl) {
      return _LoginResult(cached.verified,
          cached.verified ? null : 'GitHub Token 校验失败');
    }
    var verified = false;
    String? error;
    try {
      verified = await _githubService.verifyToken(token);
      if (!verified) error = 'GitHub Token 校验失败';
    } catch (e) {
      error = 'Token 校验异常: $e';
    }
    _loginCache[token] = _LoginCacheEntry(verified, now);
    return _LoginResult(verified, error);
  }

  /// 有界并发执行 [fn]，保持输入顺序返回结果。
  ///
  /// 默认 4 路并发，避免站点过多时一次性打满 GitHub API 连接。
  Future<List<R>> _runPool<I, R>(
    List<I> inputs,
    Future<R> Function(I) fn, {
    int maxConcurrent = 4,
  }) async {
    if (inputs.isEmpty) return const [];
    final results = List<R?>.filled(inputs.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= inputs.length) return;
        results[i] = await fn(inputs[i]);
      }
    }

    final workers = maxConcurrent < inputs.length
        ? maxConcurrent
        : inputs.length;
    await Future.wait(List.generate(workers, (_) => worker()));
    return results.cast<R>();
  }

  /// 目标文件完整路径
  String _pathFor(BlogPost post, RepoConfig repo) {
    final fileName = _fileNameFor(post, repo);
    final postsPath = repo.postsPath.replaceAll(RegExp(r'/+$'), '');
    return '$postsPath/$fileName';
  }

  /// 写入远程（携带 sha 覆盖）
  Future<void> _putWithSha(
      RepoConfig repo, String path, String content, BlogPost post) async {
    String? existingSha;
    try {
      final existing = await _githubService.getRawFile(repo, path);
      existingSha = existing?['sha'];
    } catch (_) {/* 按新建处理 */}

    await _githubService.putRawFile(
      repo,
      path,
      content,
      sha: (existingSha?.isNotEmpty ?? false) ? existingSha : null,
      commitMessage: post.status == 'publish'
          ? '发布文章: ${post.title}'
          : '更新草稿: ${post.title}',
    );
  }

  /// 将 BlogPost 映射为 Article，复用单站发布渲染链路
  Article _toArticle(BlogPost post) => Article(
        id: post.id?.toString() ?? post.title,
        title: post.title,
        content: post.contentMd,
        tags: post.tags,
        categories: post.categories,
        createdAt: post.date,
        updatedAt: post.modifiedDate,
        isDraft: post.status != 'publish',
        published: post.status == 'publish',
        articleType: ArticleType.post,
      );

  /// 按站点渲染文章内容。
  ///
  /// 优先使用每站默认模板（[TemplateResolver.resolvePostTemplate]，即
  /// `repo.defaultPostTemplateId` 绑定模板），文章自带 [Article.templateId]
  /// 时优先于站点默认模板；未绑定则回退框架内置模板，与单站发布一致。
  String _renderForRepo(
      BlogPost post, RepoConfig repo, List<TemplateItem> templates) {
    var article = _toArticle(post);
    final resolved = TemplateResolver.resolvePostTemplate(repo, templates);
    if (resolved != null && article.templateId != resolved.id) {
      article = article.copyWith(templateId: resolved.id);
    }
    return article.toMarkdownWithFrontMatterForRepo(repo, templates: templates);
  }

  /// 生成目标文件名
  String _fileNameFor(BlogPost post, RepoConfig repo) {
    final safeTitle = (post.slug ?? post.title)
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|#%\s]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final title = safeTitle.isEmpty ? 'untitled' : safeTitle;
    if (repo.frameworkId == 'jekyll' || repo.fileNameRule.postDatePrefix) {
      final d = post.date;
      final prefix = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      return '$prefix-$title.md';
    }
    return '$title.md';
  }
}

/// 单仓库登录态校验结果
class _LoginResult {
  final bool verified;
  final String? error;
  const _LoginResult(this.verified, this.error);
}

/// 登录态缓存条目
class _LoginCacheEntry {
  final bool verified;
  final DateTime at;
  const _LoginCacheEntry(this.verified, this.at);
}

/// 远程文件探测结果
class _RemoteContent {
  final String? content;
  final String? sha;
  const _RemoteContent(this.content, this.sha);
}
