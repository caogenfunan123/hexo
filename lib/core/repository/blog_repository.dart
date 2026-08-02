import '../../models/blog_post.dart';
import '../../models/blog_site_config.dart';

/// 博客仓库统一抽象接口
/// 静态博客（Hexo/Hugo/Astro）和动态 CMS（WP/Ghost/Typecho）共用此接口
///
/// 上层编辑器不关心底层是文件系统还是 REST API，
/// 只通过此接口操作文章
abstract class BlogRepository {
  /// 获取当前站点配置
  BlogSiteConfig get config;

  /// 连通性测试（验证鉴权和网络）
  Future<ConnectionResult> testConnection();

  /// 获取文章列表
  /// [page] 分页页码，从 1 开始
  /// [perPage] 每页数量，默认 10
  Future<List<BlogPost>> getPosts({int page = 1, int perPage = 10});

  /// 获取单篇文章
  Future<BlogPost?> getPostById(int id);

  /// 创建新文章
  /// 返回带远程 ID 的 BlogPost
  Future<BlogPost> createPost(BlogPost post);

  /// 更新文章
  /// 返回更新后的 BlogPost
  Future<BlogPost> updatePost(BlogPost post);

  /// 删除文章
  Future<bool> deletePost(int postId);

  /// 上传媒体文件
  /// [filePath] 本地文件路径
  /// 返回远程 URL
  Future<MediaUploadResult> uploadMedia(String filePath);

  /// 释放资源（关闭 HTTP 客户端等）
  void dispose();
}

/// 连通性测试结果
class ConnectionResult {
  final bool success;
  final String message;
  final String? errorDetail;

  const ConnectionResult({
    required this.success,
    required this.message,
    this.errorDetail,
  });

  factory ConnectionResult.ok(String message) =>
      ConnectionResult(success: true, message: message);

  factory ConnectionResult.fail(String message, {String? detail}) =>
      ConnectionResult(success: false, message: message, errorDetail: detail);
}

/// 媒体上传结果
class MediaUploadResult {
  final int? mediaId;
  final String url;
  final String? error;

  const MediaUploadResult({
    this.mediaId,
    required this.url,
    this.error,
  });

  bool get isSuccess => error == null && url.isNotEmpty;

  factory MediaUploadResult.success(int mediaId, String url) =>
      MediaUploadResult(mediaId: mediaId, url: url);

  factory MediaUploadResult.failure(String error) =>
      MediaUploadResult(url: '', error: error);
}

/// 博客仓库异常
/// 所有适配器（WordPress / Ghost / Typecho）共用
class BlogRepositoryException implements Exception {
  final int statusCode;
  final String message;
  final String? body;

  const BlogRepositoryException(this.statusCode, this.message, this.body);

  @override
  String toString() => message;
}