import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/blog_post.dart';
import '../../models/blog_site_config.dart';
import '../../models/repo_config.dart';
import '../repository/blog_repository.dart';
import '../../services/github_service.dart';
import '../../services/log_service.dart';
import '../../models/app_settings.dart';

/// 静态博客文章快照缓存条目
///
/// 持久化到应用数据目录，供「全部博客管理」二次打开时免网络直出。
class StaticBlogSnapshot {
  /// 缓存时的仓库指纹（来自 [GitHubService.listPostsFingerprint]）
  final String fingerprint;

  /// 缓存写入时间
  final DateTime savedAt;

  /// 文章快照
  final List<BlogPost> posts;

  const StaticBlogSnapshot({
    required this.fingerprint,
    required this.savedAt,
    required this.posts,
  });

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'savedAt': savedAt.toIso8601String(),
        'posts': posts.map((e) => e.toJson()).toList(),
      };

  factory StaticBlogSnapshot.fromJson(Map<String, dynamic> j) {
    final posts = (j['posts'] as List? ?? [])
        .whereType<Map>()
        .map((e) => BlogPost.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return StaticBlogSnapshot(
      fingerprint: j['fingerprint']?.toString() ?? '',
      savedAt:
          DateTime.tryParse(j['savedAt']?.toString() ?? '') ?? DateTime.now(),
      posts: posts,
    );
  }
}

/// 静态博客仓库适配器
/// 
/// 支持从 Hexo、Hugo、Astro、Jekyll、VuePress、Gatsby、Next.js 等静态博客框架
/// 中读取文章列表，并提供基本的文章管理功能
class StaticBlogRepository implements BlogRepository {
  final RepoConfig repoConfig;
  final AppSettings appSettings;
  final GitHubService githubService;
  final LogService logService;

  /// 快照缓存目录提供者（null 表示不启用缓存，回退全量加载）
  final Future<Directory> Function()? snapshotRootProvider;

  /// 最近一次成功写入的缓存指纹（供页面判断是否有更新）
  String? lastCachedFingerprint;

  StaticBlogRepository({
    required this.repoConfig,
    required this.appSettings,
    required this.githubService,
    required this.logService,
    this.snapshotRootProvider,
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

  // ════════════════════════════════════════════════════════════
  // 快照缓存：按仓库粒度持久化，二次打开免网络直出
  // ════════════════════════════════════════════════════════════

  Directory? _cacheDir;

  /// 快照缓存目录（应用数据目录下 `.blog_snapshot/<repoId>`）
  Future<Directory> _snapshotDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final provider = snapshotRootProvider;
    if (provider == null) {
      throw StateError('未配置快照缓存目录');
    }
    final root = await provider();
    final dir = Directory('${root.path}/.blog_snapshot/${_safePath(repoConfig.id)}');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  File _snapshotFile(Directory dir) => File('${dir.path}/snapshot.json');

  /// 将不可信字符串消毒为安全单一路径段
  static String _safePath(String input) => input
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), '_');

  /// 读取缓存快照；文件缺失/损坏返回 null（调用方回退全量加载）
  Future<StaticBlogSnapshot?> loadSnapshot() async {
    try {
      final dir = await _snapshotDir();
      final f = _snapshotFile(dir);
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      if (text.trim().isEmpty) return null;
      final data = jsonDecode(text);
      if (data is! Map) return null;
      final snap = StaticBlogSnapshot.fromJson(Map<String, dynamic>.from(data));
      if (snap.fingerprint.isEmpty || snap.posts.isEmpty) return null;
      return snap;
    } catch (e) {
      debugPrint('StaticBlogRepository: 读取快照失败 $e');
      return null;
    }
  }

  /// 写入缓存快照（原子写入，损坏不留半截文件）
  Future<void> saveSnapshot(List<BlogPost> posts, {required String fingerprint}) async {
    try {
      final dir = await _snapshotDir();
      final f = _snapshotFile(dir);
      final tmp = File('${f.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
      final snap = StaticBlogSnapshot(
        fingerprint: fingerprint,
        savedAt: DateTime.now(),
        posts: posts,
      );
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(snap.toJson()),
          flush: true);
      await tmp.rename(f.path);
      lastCachedFingerprint = fingerprint;
    } catch (e) {
      debugPrint('StaticBlogRepository: 写入快照失败 $e');
    }
  }

  /// 清空缓存（强制刷新前调用）
  Future<void> clearSnapshot() async {
    try {
      final dir = await _snapshotDir();
      final f = _snapshotFile(dir);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('StaticBlogRepository: 清空快照失败 $e');
    }
  }

  /// 获取当前仓库指纹（null 表示仓库不可读，需回退全量）
  Future<String?> currentFingerprint() => githubService.listPostsFingerprint(repoConfig);

  /// 若缓存未过期则直接返回缓存文章列表，否则返回 null
  Future<List<BlogPost>?> cachedIfFresh({
    required bool forceRefresh,
  }) async {
    if (!forceRefresh && snapshotRootProvider != null) {
      final snap = await loadSnapshot();
      if (snap != null) {
        final fp = await currentFingerprint();
        if (fp != null && fp == snap.fingerprint) {
          return snap.posts;
        }
      }
    }
    return null;
  }

  /// 获取文章列表（带快照缓存：先比对指纹，无更新直接返回缓存）
  Future<List<BlogPost>> getPostsCached({bool forceRefresh = false}) async {
    final cached = await cachedIfFresh(forceRefresh: forceRefresh);
    if (cached != null) return cached;

    final posts = await getPosts(page: 1, perPage: 500);
    if (snapshotRootProvider != null) {
      final fp = await currentFingerprint();
      if (fp != null) {
        await saveSnapshot(posts, fingerprint: fp);
      }
    }
    return posts;
  }

  /// 带缓存的全量文章列表（供聚合页面合并去重）
  Future<List<BlogPost>> getAllPostsCached({bool forceRefresh = false}) async {
    return getPostsCached(forceRefresh: forceRefresh);
  }

  @override
  Future<List<BlogPost>> getPosts({int page = 1, int perPage = 10}) async {
    try {
      final posts = await githubService.listPosts(repoConfig, recursive: true);
      
      // 转换为 BlogPost 格式。GitHub SHA 是 40 位 hex，无法直接 int.tryParse，
      // 用稳定哈希生成 int id，保证列表→详情可按 id 找回
      final blogPosts = posts.map((fileItem) {
        return BlogPost(
          id: fileItem.sha != null
              ? (fileItem.sha.hashCode & 0x7fffffff)
              : (fileItem.path.hashCode & 0x7fffffff),
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

      // 根据ID查找文章（SHA 哈希或路径匹配）
      for (final item in posts) {
        final hashId = item.sha != null
            ? (item.sha.hashCode & 0x7fffffff)
            : (item.path.hashCode & 0x7fffffff);
        if (hashId == id) {
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