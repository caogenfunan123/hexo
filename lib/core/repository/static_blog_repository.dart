import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../models/blog_post.dart';
import '../../models/blog_site_config.dart';
import '../../models/repo_config.dart';
import '../repository/blog_repository.dart';
import '../../services/github_service.dart';
import '../../services/log_service.dart';
import '../../models/app_settings.dart';

/// 静态博客仓库适配器
/// 
/// 支持从 Hexo、Hugo、Astro、Jekyll、VuePress、Gatsby、Next.js 等静态博客框架
/// 中读取文章列表，并提供基本的文章管理功能
class StaticBlogRepository implements BlogRepository {
  final RepoConfig repoConfig;
  final AppSettings appSettings;
  final GitHubService githubService;
  final LogService logService;
  
  StaticBlogRepository({
    required this.repoConfig,
    required this.appSettings,
    required this.githubService,
    required this.logService,
  });

  @override
  BlogSiteConfig get config {
    // 将 RepoConfig 转换为 BlogSiteConfig 格式
    return BlogSiteConfig(
      id: repoConfig.id,
      name: repoConfig.name,
      type: BlogType.fromString(repoConfig.frameworkId),
      siteUrl: repoConfig.siteUrl,
      isDefault: repoConfig.isDefault,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<ConnectionResult> testConnection() async {
    try {
      // 测试 GitHub token 是否有效
      final isValid = await githubService.testToken(repoConfig);
      if (isValid) {
        return ConnectionResult.ok('连接成功');
      } else {
        return ConnectionResult.fail('GitHub token 无效');
      }
    } catch (e) {
      return ConnectionResult.fail('连接失败', detail: e.toString());
    }
  }

  @override
  Future<List<BlogPost>> getPosts({int page = 1, int perPage = 10}) async {
    try {
      final posts = await githubService.listPosts(repoConfig, recursive: true);
      
      // 转换为 BlogPost 格式
      final blogPosts = posts.map((fileItem) {
        return BlogPost(
          id: fileItem.sha != null ? int.tryParse(fileItem.sha!) : null,
          title: _extractTitleFromFileItem(fileItem),
          contentMd: '', // 实际内容在点击时加载
          contentHtml: '',
          date: fileItem.lastModified ?? DateTime.now(),
          modifiedDate: fileItem.lastModified ?? DateTime.now(),
          slug: _extractSlugFromFileItem(fileItem),
          tags: _extractTagsFromFileItem(fileItem),
          categories: [],
          status: 'publish',
          siteId: repoConfig.id,
          link: '${repoConfig.siteUrl}/${fileItem.path}',
        );
      }).toList();

      // 按修改时间倒序排序
      blogPosts.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));

      // 分页处理
      final startIndex = (page - 1) * perPage;
      final endIndex = min(startIndex + perPage, blogPosts.length);
      
      if (startIndex >= blogPosts.length) {
        return [];
      }

      return blogPosts.sublist(startIndex, endIndex);
    } catch (e) {
      logService.add('获取静态博客文章失败', '$e', success: false);
      throw Exception('获取文章失败: $e');
    }
  }

  @override
  Future<BlogPost?> getPostById(int id) async {
    try {
      // 获取所有文章
      final posts = await githubService.listPosts(repoConfig);

      // 根据ID查找文章（使用SHA或路径作为ID）
      for (final item in posts) {
        if (item.sha == id.toString() ||
            item.path.contains(id.toString()) ||
            _extractTitleFromFileItem(item) == id.toString()) {
          return await getPostContent(item.sha ?? item.path);
        }
      }
      return null;
    } catch (e) {
      logService.add('获取静态博客文章详情失败', '$e', success: false);
      return null;
    }
  }

  @override
  Future<BlogPost> createPost(BlogPost post) async {
    throw UnimplementedError('静态博客暂不支持创建文章，请直接在仓库中创建');
  }

  @override
  Future<BlogPost> updatePost(BlogPost post) async {
    throw UnimplementedError('静态博客暂不支持更新文章，请直接在仓库中编辑');
  }

  @override
  Future<bool> deletePost(int postId) async {
    throw UnimplementedError('静态博客暂不支持删除文章，请直接在仓库中删除');
  }

  @override
  Future<MediaUploadResult> uploadMedia(String filePath) async {
    throw UnimplementedError('静态博客暂不支持媒体上传，请直接在仓库中上传');
  }

  @override
  void dispose() {
    // 静态博客适配器无需特殊清理
  }

  /// 判断是否为静态博客适配器
  @override
  bool get isStatic => true;

  /// 从文件项中提取标题
  String _extractTitleFromFileItem(GitHubFileItem fileItem) {
    // 尝试从文件名中提取标题（去除日期前缀和扩展名）
    String name = fileItem.name;
    
    // 移除 .md 扩展名
    if (name.endsWith('.md')) {
      name = name.substring(0, name.length - 3);
    }
    
    // 移除日期前缀（如 2024-01-01-）
    if (repoConfig.fileNameRule.postDatePrefix) {
      final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}-');
      if (dateRegex.hasMatch(name)) {
        name = name.replaceFirst(dateRegex, '');
      }
    }
    
    return name.isNotEmpty ? name : '（无标题）';
  }

  /// 从文件项中提取标签
  List<String> _extractTagsFromFileItem(GitHubFileItem fileItem) {
    // 静态博客的标签需要从文件内容中提取
    // 这里返回空列表，实际标签在点击文章时加载
    return [];
  }

  /// 从文件项中提取slug
  String _extractSlugFromFileItem(GitHubFileItem fileItem) {
    // 生成slug：去除日期前缀、扩展名，并将空格替换为连字符
    String slug = fileItem.name;
    
    // 移除 .md 扩展名
    if (slug.endsWith('.md')) {
      slug = slug.substring(0, slug.length - 3);
    }
    
    // 移除日期前缀
    if (repoConfig.fileNameRule.postDatePrefix) {
      final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}-');
      if (dateRegex.hasMatch(slug)) {
        slug = slug.replaceFirst(dateRegex, '');
      }
    }
    
    // 替换空格为连字符，转换为小写
    slug = slug.replaceAll(RegExp(r'\s+'), '-').toLowerCase();
    
    return slug;
  }

  /// 获取文章完整内容
  Future<BlogPost> getPostContent(String postId) async {
    try {
      // 获取文件列表
      final posts = await githubService.listPosts(repoConfig);
      
      // 找到对应的文件
      final fileItem = posts.firstWhere(
        (item) => item.sha == postId || item.path.contains(postId),
        orElse: () => throw Exception('文章不存在'),
      );
      
      // 获取文章内容
      final article = await githubService.getArticle(repoConfig, fileItem);
      
      // 转换为 BlogPost
      return BlogPost(
        id: fileItem.sha != null ? int.tryParse(fileItem.sha!) : null,
        title: article.title.isNotEmpty ? article.title : '（无标题）',
        contentMd: article.content,
        date: article.createdAt,
        modifiedDate: article.updatedAt,
        slug: _extractSlugFromFileItem(fileItem),
        tags: article.tags,
        categories: article.categories,
        siteId: repoConfig.id,
        status: article.published ? 'publish' : 'draft',
        link: '${repoConfig.siteUrl}/${fileItem.path}',
      );
    } catch (e) {
      logService.add('获取文章内容失败', '$e', success: false);
      throw Exception('获取文章内容失败: $e');
    }
  }
}