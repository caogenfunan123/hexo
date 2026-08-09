import 'dart:io';
import '../models/app_settings.dart';
import '../models/blog_post.dart';
import '../models/repo_config.dart';
import '../core/site_manager.dart';
import 'github_service.dart';
import 'template_service.dart';

/// 静态博客批量发布服务
///
/// 将一篇文章转换后批量发布到所有（或指定）静态博客仓库。
/// 每个目标站点对应一个 [RepoConfig]，使用 GitHub Contents API 真实写入。
class StaticBlogBatchPublishService {
  final AppSettings _settings;
  final SiteManager _siteManager;
  final GitHubService _githubService;
  final TemplateService _templateService;

  StaticBlogBatchPublishService({
    required AppSettings settings,
    required SiteManager siteManager,
    required GitHubService githubService,
    required TemplateService templateService,
  }) : _settings = settings,
       _siteManager = siteManager,
       _githubService = githubService,
       _templateService = templateService;

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
      // 静态博客站点（全部 RepoConfig）
      final staticRepos = List<RepoConfig>.from(_siteManager.staticRepos)
        ..sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));

      final targetRepos = selectedSiteIds != null
          ? staticRepos.where((r) => selectedSiteIds.contains(r.id)).toList()
          : staticRepos;

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

          // 按站点框架转换文章格式
          final converted = await _convertForRepo(post, repo);

          // 生成目标路径（postsPath + 文件名）
          final fileName = _fileNameFor(post, repo);
          final postsPath =
              repo.postsPath.replaceAll(RegExp(r'/+$'), '');
          final path = '$postsPath/$fileName';

          // 探测远程是否已存在（携带 sha 覆盖）
          String? existingSha;
          try {
            final existing = await _githubService.getRawFile(repo, path);
            existingSha = existing?['sha'];
          } catch (_) {/* 按新建处理 */}

          await _githubService.putRawFile(
            repo,
            path,
            converted,
            sha: (existingSha?.isNotEmpty ?? false) ? existingSha : null,
            commitMessage:
                post.status == 'publish' ? '发布文章: ${post.title}' : '更新草稿: ${post.title}',
          );

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

  /// 根据站点框架转换文章内容为对应格式
  Future<String> _convertForRepo(BlogPost post, RepoConfig repo) async {
    final framework = repo.frameworkId;
    switch (framework) {
      case 'hexo':
        return _toHexo(post);
      case 'hugo':
        return _toHugo(post);
      case 'astro':
        return _toAstro(post);
      case 'jekyll':
        return _toJekyll(post);
      case 'vuepress':
        return _toVuepress(post);
      case 'gatsby':
        return _toGatsby(post);
      case 'nextjs':
        return _toNextjs(post);
      case 'pelican':
        return _toPelican(post);
      case '11ty':
        return _toEleventy(post);
      default:
        // 未知框架使用通用 frontmatter
        return _toHexo(post);
    }
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

  // ── 各框架格式转换 ──

  String _toHexo(BlogPost post) {
    final fm = <String, dynamic>{
      'title': post.title,
      'date': _fmtDate(post.date),
      if (post.tags.isNotEmpty) 'tags': post.tags,
      if (post.categories.isNotEmpty) 'categories': post.categories,
      if (post.status.isNotEmpty) 'status': post.status,
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
    };
    return '${_fm(fm)}\n\n${post.contentMd}';
  }

  String _toHugo(BlogPost post) {
    final fm = <String, dynamic>{
      'title': post.title,
      'date': _fmtDate(post.date),
      if (post.tags.isNotEmpty) 'tags': post.tags,
      if (post.categories.isNotEmpty) 'categories': post.categories,
      'draft': post.status != 'publish',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
    };
    return '${_fm(fm)}\n\n${post.contentMd}';
  }

  String _toAstro(BlogPost post) {
    final fm = <String, dynamic>{
      'title': post.title,
      'date': _fmtDate(post.date),
      if (post.tags.isNotEmpty) 'tags': post.tags,
      if (post.categories.isNotEmpty) 'categories': post.categories,
      'draft': post.status != 'publish',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
    };
    return '${_fm(fm)}\n\n${post.contentMd}';
  }

  String _toJekyll(BlogPost post) {
    final fm = <String, dynamic>{
      'layout': 'post',
      'title': post.title,
      'date': _fmtDate(post.date),
      if (post.tags.isNotEmpty) 'tags': post.tags,
      if (post.categories.isNotEmpty) 'categories': post.categories,
      'published': post.status == 'publish',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
    };
    return '${_fm(fm)}\n\n${post.contentMd}';
  }

  String _toVuepress(BlogPost post) {
    final fm = <String, dynamic>{
      'title': post.title,
      'date': _fmtDate(post.date),
      if (post.tags.isNotEmpty) 'tags': post.tags,
      if (post.categories.isNotEmpty) 'categories': post.categories,
      'draft': post.status != 'publish',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
    };
    return '${_fm(fm)}\n\n${post.contentMd}';
  }

  String _toGatsby(BlogPost post) {
    final fm = <String, dynamic>{
      'title': post.title,
      'date': _fmtDate(post.date),
      if (post.tags.isNotEmpty) 'tags': post.tags,
      if (post.categories.isNotEmpty) 'categories': post.categories,
      'draft': post.status != 'publish',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
    };
    return '${_fm(fm)}\n\n${post.contentMd}';
  }

  String _toNextjs(BlogPost post) {
    final fm = <String, dynamic>{
      'title': post.title,
      'date': _fmtDate(post.date),
      if (post.tags.isNotEmpty) 'tags': post.tags,
      if (post.categories.isNotEmpty) 'categories': post.categories,
      'draft': post.status != 'publish',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
    };
    return '${_fm(fm)}\n\n${post.contentMd}';
  }

  String _toPelican(BlogPost post) {
    final fm = <String, dynamic>{
      'title': post.title,
      'date': _fmtDate(post.date),
      if (post.tags.isNotEmpty) 'tags': post.tags,
      if (post.categories.isNotEmpty) 'category': post.categories.join(', '),
      'status': post.status == 'publish' ? 'published' : 'draft',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
    };
    return '${_fm(fm)}\n\n${post.contentMd}';
  }

  String _toEleventy(BlogPost post) {
    final fm = <String, dynamic>{
      'title': post.title,
      'date': _fmtDate(post.date),
      if (post.tags.isNotEmpty) 'tags': post.tags,
      if (post.categories.isNotEmpty) 'categories': post.categories,
      'draft': post.status != 'publish',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
    };
    return '${_fm(fm)}\n\n${post.contentMd}';
  }

  /// 格式化 YAML frontmatter
  String _fm(Map<String, dynamic> data) {
    final buffer = StringBuffer('---\n');
    data.forEach((key, value) {
      if (value is List) {
        buffer.write('$key:\n');
        for (final item in value) {
          buffer.write('  - "$item"\n');
        }
      } else {
        buffer.write('$key: "$value"\n');
      }
    });
    buffer.write('---\n');
    return buffer.toString();
  }

  String _fmtDate(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
