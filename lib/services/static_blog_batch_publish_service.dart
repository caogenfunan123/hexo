import 'dart:io';
import 'dart:convert';
import '../../models/app_settings.dart';
import '../../models/blog_post.dart';
import '../../models/repo_config.dart';
import '../../services/git_service.dart';
import '../../services/template_service.dart';
import '../site_manager.dart';

/// 静态博客批量发布服务
class StaticBlogBatchPublishService {
  final AppSettings _settings;
  final SiteManager _siteManager;
  final GitService _gitService;
  final TemplateService _templateService;

  StaticBlogBatchPublishService({
    required AppSettings settings,
    required SiteManager siteManager,
    required GitService gitService,
    required TemplateService templateService,
  }) : _settings = settings,
       _siteManager = siteManager,
       _gitService = gitService,
       _templateService = templateService;

  /// 批量发布文章到所有静态博客站点
  ///
  /// [post] 要发布的文章
  /// [selectedSiteIds] 选定的站点 ID 列表，如果为空则发布到所有站点
  /// [onProgress] 进度回调
  /// [onComplete] 完成回调
  Future<void> batchPublishToStaticBlogs(
    BlogPost post, {
    List<String>? selectedSiteIds,
    Function(int, int, String)? onProgress,
    Function(bool, String, Map<String, dynamic>)? onComplete,
  }) async {
    try {
      // 获取所有静态博客站点
      final staticSites = _siteManager.staticSites
          .where((site) => site.isStatic)
          .toList();

      // 如果指定了站点，则只发布到这些站点
      final targetSites = selectedSiteIds != null
          ? staticSites.where((site) => selectedSiteIds.contains(site.id)).toList()
          : staticSites;

      if (targetSites.isEmpty) {
        onComplete?.call(false, '没有找到可用的静态博客站点', {});
        return;
      }

      final total = targetSites.length;
      var successCount = 0;
      var failCount = 0;
      final results = <String, dynamic>{};

      for (int i = 0; i < targetSites.length; i++) {
        final site = targetSites[i];
        final siteName = site.name;

        try {
          onProgress?.call(i + 1, total, '正在发布到 $siteName...');

          // 获取站点配置
          final repoConfig = _siteManager.currentStaticRepo;
          if (repoConfig == null || repoConfig.id != site.id) {
            throw Exception('无法获取站点配置');
          }

          // 转换文章内容为站点特定的格式
          final convertedContent = await _convertContentForSite(
            post,
            repoConfig,
            site,
          );

          // 创建临时文件
          final tempFile = await _createTempFile(convertedContent, repoConfig);

          // 提交到 Git
          await _gitService.commitFile(
            repoConfig: repoConfig,
            filePath: tempFile.path,
            commitMessage: '发布文章: ${post.title}',
            authorName: 'Hexo Blog Manager',
            authorEmail: 'noreply@hexo.blog',
          );

          // 推送到远程仓库
          await _gitService.push(repoConfig);

          // 清理临时文件
          await tempFile.delete();

          successCount++;
          results[siteName] = {
            'success': true,
            'message': '发布成功',
            'commit': '文章已提交',
          };

        } catch (e) {
          failCount++;
          results[siteName] = {
            'success': false,
            'message': e.toString(),
            'error': '发布失败',
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

  /// 为特定站点转换文章内容
  Future<String> _convertContentForSite(
    BlogPost post,
    RepoConfig repoConfig,
    SiteIdentity site,
  ) async {
    // 根据站点框架转换内容
    switch (repoConfig.frameworkId) {
      case 'hexo':
        return await _convertToHexoFormat(post, repoConfig);
      case 'hugo':
        return await _convertToHugoFormat(post, repoConfig);
      case 'astro':
        return await _convertToAstroFormat(post, repoConfig);
      case 'jekyll':
        return await _convertToJekyllFormat(post, repoConfig);
      case 'vuepress':
        return await _convertToVuepressFormat(post, repoConfig);
      case 'gatsby':
        return await _convertToGatsbyFormat(post, repoConfig);
      case 'nextjs':
        return await _convertToNextjsFormat(post, repoConfig);
      default:
        throw Exception('不支持的框架: ${repoConfig.frameworkId}');
    }
  }

  /// 转换为 Hexo 格式
  Future<String> _convertToHexoFormat(
    BlogPost post,
    RepoConfig repoConfig,
  ) async {
    final frontmatter = {
      'title': post.title,
      'date': post.date.toIso8601String(),
      'tags': post.tags,
      'categories': post.categories,
      'status': post.status,
      if (post.slug != null) 'slug': post.slug,
    };

    final frontmatterString = _generateFrontmatter(frontmatter);
    return '$frontmatterString\n\n${post.contentMd}';
  }

  /// 转换为 Hugo 格式
  Future<String> _convertToHugoFormat(
    BlogPost post,
    RepoConfig repoConfig,
  ) async {
    final frontmatter = {
      'title': post.title,
      'date': post.date.toIso8601String(),
      'tags': post.tags,
      'categories': post.categories,
      'draft': post.status != 'publish',
      if (post.slug != null) 'slug': post.slug,
    };

    final frontmatterString = _generateFrontmatter(frontmatter);
    return '$frontmatterString\n\n${post.contentMd}';
  }

  /// 转换为 Astro 格式
  Future<String> _convertToAstroFormat(
    BlogPost post,
    RepoConfig repoConfig,
  ) async {
    final frontmatter = {
      'title': post.title,
      'date': post.date.toIso8601String(),
      'tags': post.tags,
      'categories': post.categories,
      'draft': post.status != 'publish',
      if (post.slug != null) 'slug': post.slug,
    };

    final frontmatterString = _generateFrontmatter(frontmatter);
    return '$frontmatterString\n\n${post.contentMd}';
  }

  /// 转换为 Jekyll 格式
  Future<String> _convertToJekyllFormat(
    BlogPost post,
    RepoConfig repoConfig,
  ) async {
    final frontmatter = {
      'layout': 'post',
      'title': post.title,
      'date': post.date.toIso8601String(),
      'tags': post.tags,
      'categories': post.categories,
      'published': post.status == 'publish',
      if (post.slug != null) 'slug': post.slug,
    };

    final frontmatterString = _generateFrontmatter(frontmatter);
    return '$frontmatterString\n\n${post.contentMd}';
  }

  /// 转换为 VuePress 格式
  Future<String> _convertToVuepressFormat(
    BlogPost post,
    RepoConfig repoConfig,
  ) async {
    final frontmatter = {
      'title': post.title,
      'date': post.date.toIso8601String(),
      'tags': post.tags,
      'categories': post.categories,
      'draft': post.status != 'publish',
      if (post.slug != null) 'slug': post.slug,
    };

    final frontmatterString = _generateFrontmatter(frontmatter);
    return '$frontmatterString\n\n${post.contentMd}';
  }

  /// 转换为 Gatsby 格式
  Future<String> _convertToGatsbyFormat(
    BlogPost post,
    RepoConfig repoConfig,
  ) async {
    final frontmatter = {
      'title': post.title,
      'date': post.date.toIso8601String(),
      'tags': post.tags,
      'categories': post.categories,
      'draft': post.status != 'publish',
      if (post.slug != null) 'slug': post.slug,
    };

    final frontmatterString = _generateFrontmatter(frontmatter);
    return '$frontmatterString\n\n${post.contentMd}';
  }

  /// 转换为 Next.js 格式
  Future<String> _convertToNextjsFormat(
    BlogPost post,
    RepoConfig repoConfig,
  ) async {
    final frontmatter = {
      'title': post.title,
      'date': post.date.toIso8601String(),
      'tags': post.tags,
      'categories': post.categories,
      'draft': post.status != 'publish',
      if (post.slug != null) 'slug': post.slug,
    };

    final frontmatterString = _generateFrontmatter(frontmatter);
    return '$frontmatterString\n\n${post.contentMd}';
  }

  /// 生成 Frontmatter
  String _generateFrontmatter(Map<String, dynamic> data) {
    final buffer = StringBuffer('---\n');
    data.forEach((key, value) {
      if (value is List) {
        buffer.write('$key: [${value.map((v) => '"$v"').join(', ')}]\n');
      } else {
        buffer.write('$key: "$value"\n');
      }
    });
    buffer.write('---\n');
    return buffer.toString();
  }

  /// 创建临时文件
  Future<File> _createTempFile(String content, RepoConfig repoConfig) async {
    final tempDir = await Directory.systemTemp.createTemp('hexo_batch_publish_');
    final fileName = 'post_${DateTime.now().millisecondsSinceEpoch}.md';
    final filePath = '${tempDir.path}/$fileName';
    return File(filePath)..writeAsString(content);
  }
}