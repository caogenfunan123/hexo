import 'dart:convert';
import 'dart:io';

import '../../models/blog_post.dart';
import '../repository/blog_repository.dart';
import '../site_manager.dart';
import 'tool_entity.dart';

/// 远程 CMS 工具注册与执行
///
/// 为动态 CMS 站点（WordPress / Ghost / Typecho）提供 AI 可调用的工具集。
/// 静态站点不注册这些工具，通过 [SiteManager.canExecuteOperation] 做双层防护。
class RemoteCmsTools {
  RemoteCmsTools._();

  /// 站点管理器引用（由外部在初始化时设置）
  static SiteManager? siteManager;

  /// 所有远程 CMS 工具定义
  static List<ToolEntity> get all => [
        wpCreatePost,
        wpUpdatePost,
        wpDeletePost,
        wpListPosts,
        wpTestConnection,
        ghostCreatePost,
        ghostUpdatePost,
        ghostDeletePost,
        ghostListPosts,
        ghostTestConnection,
        typechoCreatePost,
        typechoUpdatePost,
        typechoDeletePost,
        typechoListPosts,
        typechoTestConnection,
        remoteMediaUpload,
      ];

  // ── WordPress 工具 ──

  static final ToolEntity wpCreatePost = ToolEntity(
    id: 'wp_create_post',
    name: 'WordPress 发布文章',
    description: '创建并发布一篇新文章到 WordPress 站点。需要提供标题、Markdown 正文内容，会自动转换为 Gutenberg HTML 格式。',
    type: ToolType.builtin,
    builtinHandler: 'wp_create_post',
    parameters: const [
      ToolParam(name: 'title', type: 'string', description: '文章标题', required: true),
      ToolParam(name: 'content_md', type: 'string', description: '文章正文（Markdown 格式）', required: true),
      ToolParam(name: 'status', type: 'string', description: '发布状态：publish（发布）或 draft（草稿），默认 draft', required: false, defaultValue: 'draft'),
      ToolParam(name: 'slug', type: 'string', description: 'URL 别名，默认自动生成', required: false),
      ToolParam(name: 'tags', type: 'string', description: '标签，逗号分隔', required: false),
      ToolParam(name: 'categories', type: 'string', description: '分类，逗号分隔', required: false),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity wpUpdatePost = ToolEntity(
    id: 'wp_update_post',
    name: 'WordPress 更新文章',
    description: '更新 WordPress 站点上已有的文章。需要提供文章 ID 和新的内容。',
    type: ToolType.builtin,
    builtinHandler: 'wp_update_post',
    parameters: const [
      ToolParam(name: 'post_id', type: 'number', description: '文章 ID', required: true),
      ToolParam(name: 'title', type: 'string', description: '文章标题', required: false),
      ToolParam(name: 'content_md', type: 'string', description: '文章正文（Markdown 格式）', required: false),
      ToolParam(name: 'status', type: 'string', description: '发布状态', required: false),
      ToolParam(name: 'slug', type: 'string', description: 'URL 别名', required: false),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity wpDeletePost = ToolEntity(
    id: 'wp_delete_post',
    name: 'WordPress 删除文章',
    description: '删除 WordPress 站点上的文章。需要用户确认后执行。',
    type: ToolType.builtin,
    builtinHandler: 'wp_delete_post',
    parameters: const [
      ToolParam(name: 'post_id', type: 'number', description: '文章 ID', required: true),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity wpListPosts = ToolEntity(
    id: 'wp_list_posts',
    name: 'WordPress 文章列表',
    description: '获取 WordPress 站点上的文章列表，支持分页。',
    type: ToolType.builtin,
    builtinHandler: 'wp_list_posts',
    parameters: const [
      ToolParam(name: 'page', type: 'number', description: '页码，从 1 开始', required: false, defaultValue: 1),
      ToolParam(name: 'per_page', type: 'number', description: '每页数量，默认 10', required: false, defaultValue: 10),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity wpTestConnection = ToolEntity(
    id: 'wp_test_connection',
    name: 'WordPress 连接测试',
    description: '测试 WordPress 站点连接和鉴权是否正常。',
    type: ToolType.builtin,
    builtinHandler: 'wp_test_connection',
    parameters: const [],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  // ── Ghost 工具 ──

  static final ToolEntity ghostCreatePost = ToolEntity(
    id: 'ghost_create_post',
    name: 'Ghost 发布文章',
    description: '创建并发布一篇新文章到 Ghost 站点。需要提供标题、Markdown 正文内容，会自动转换为 Mobiledoc JSON 格式。',
    type: ToolType.builtin,
    builtinHandler: 'ghost_create_post',
    parameters: const [
      ToolParam(name: 'title', type: 'string', description: '文章标题', required: true),
      ToolParam(name: 'content_md', type: 'string', description: '文章正文（Markdown 格式）', required: true),
      ToolParam(name: 'status', type: 'string', description: '发布状态：published（发布）或 draft（草稿），默认 draft', required: false, defaultValue: 'draft'),
      ToolParam(name: 'slug', type: 'string', description: 'URL 别名', required: false),
      ToolParam(name: 'tags', type: 'string', description: '标签，逗号分隔', required: false),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity ghostUpdatePost = ToolEntity(
    id: 'ghost_update_post',
    name: 'Ghost 更新文章',
    description: '更新 Ghost 站点上已有的文章。',
    type: ToolType.builtin,
    builtinHandler: 'ghost_update_post',
    parameters: const [
      ToolParam(name: 'post_id', type: 'number', description: '文章 ID', required: true),
      ToolParam(name: 'title', type: 'string', description: '文章标题', required: false),
      ToolParam(name: 'content_md', type: 'string', description: '文章正文（Markdown 格式）', required: false),
      ToolParam(name: 'status', type: 'string', description: '发布状态', required: false),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity ghostDeletePost = ToolEntity(
    id: 'ghost_delete_post',
    name: 'Ghost 删除文章',
    description: '删除 Ghost 站点上的文章。',
    type: ToolType.builtin,
    builtinHandler: 'ghost_delete_post',
    parameters: const [
      ToolParam(name: 'post_id', type: 'number', description: '文章 ID', required: true),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity ghostListPosts = ToolEntity(
    id: 'ghost_list_posts',
    name: 'Ghost 文章列表',
    description: '获取 Ghost 站点上的文章列表。',
    type: ToolType.builtin,
    builtinHandler: 'ghost_list_posts',
    parameters: const [
      ToolParam(name: 'page', type: 'number', description: '页码', required: false, defaultValue: 1),
      ToolParam(name: 'per_page', type: 'number', description: '每页数量', required: false, defaultValue: 10),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity ghostTestConnection = ToolEntity(
    id: 'ghost_test_connection',
    name: 'Ghost 连接测试',
    description: '测试 Ghost 站点连接和鉴权是否正常。',
    type: ToolType.builtin,
    builtinHandler: 'ghost_test_connection',
    parameters: const [],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  // ── Typecho 工具 ──

  static final ToolEntity typechoCreatePost = ToolEntity(
    id: 'typecho_create_post',
    name: 'Typecho 发布文章',
    description: '创建并发布一篇新文章到 Typecho 站点。需要提供标题和 Markdown 正文。',
    type: ToolType.builtin,
    builtinHandler: 'typecho_create_post',
    parameters: const [
      ToolParam(name: 'title', type: 'string', description: '文章标题', required: true),
      ToolParam(name: 'content_md', type: 'string', description: '文章正文（Markdown 格式）', required: true),
      ToolParam(name: 'status', type: 'string', description: '发布状态：publish（发布）或 draft（草稿），默认 draft', required: false, defaultValue: 'draft'),
      ToolParam(name: 'slug', type: 'string', description: 'URL 别名', required: false),
      ToolParam(name: 'tags', type: 'string', description: '标签，逗号分隔', required: false),
      ToolParam(name: 'categories', type: 'string', description: '分类，逗号分隔', required: false),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity typechoUpdatePost = ToolEntity(
    id: 'typecho_update_post',
    name: 'Typecho 更新文章',
    description: '更新 Typecho 站点上已有的文章。',
    type: ToolType.builtin,
    builtinHandler: 'typecho_update_post',
    parameters: const [
      ToolParam(name: 'post_id', type: 'number', description: '文章 ID', required: true),
      ToolParam(name: 'title', type: 'string', description: '文章标题', required: false),
      ToolParam(name: 'content_md', type: 'string', description: '文章正文（Markdown 格式）', required: false),
      ToolParam(name: 'status', type: 'string', description: '发布状态', required: false),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity typechoDeletePost = ToolEntity(
    id: 'typecho_delete_post',
    name: 'Typecho 删除文章',
    description: '删除 Typecho 站点上的文章。',
    type: ToolType.builtin,
    builtinHandler: 'typecho_delete_post',
    parameters: const [
      ToolParam(name: 'post_id', type: 'number', description: '文章 ID', required: true),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity typechoListPosts = ToolEntity(
    id: 'typecho_list_posts',
    name: 'Typecho 文章列表',
    description: '获取 Typecho 站点上的文章列表。',
    type: ToolType.builtin,
    builtinHandler: 'typecho_list_posts',
    parameters: const [
      ToolParam(name: 'page', type: 'number', description: '页码', required: false, defaultValue: 1),
      ToolParam(name: 'per_page', type: 'number', description: '每页数量', required: false, defaultValue: 10),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  static final ToolEntity typechoTestConnection = ToolEntity(
    id: 'typecho_test_connection',
    name: 'Typecho 连接测试',
    description: '测试 Typecho 站点连接和鉴权是否正常。',
    type: ToolType.builtin,
    builtinHandler: 'typecho_test_connection',
    parameters: const [],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  // ── 通用工具 ──

  static final ToolEntity remoteMediaUpload = ToolEntity(
    id: 'remote_media_upload',
    name: '远程媒体上传',
    description: '上传本地图片/媒体文件到远程 CMS 站点（WordPress / Ghost / Typecho）。支持文件路径或 base64 编码数据。',
    type: ToolType.builtin,
    builtinHandler: 'remote_media_upload',
    parameters: const [
      ToolParam(name: 'file_path', type: 'string', description: '本地文件路径（与 base64_data 二选一）', required: false),
      ToolParam(name: 'base64_data', type: 'string', description: 'base64 编码的图片数据（与 file_path 二选一）', required: false),
      ToolParam(name: 'file_name', type: 'string', description: '文件名（base64 模式时使用，默认 image.png）', required: false, defaultValue: 'image.png'),
    ],
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  // ── 执行远程 CMS 工具 ──

  static Future<ToolCallResult> execute(ToolCallRequest request) async {
    final sm = siteManager;
    if (sm == null) {
      return ToolCallResult(
        toolId: request.toolId,
        content: '',
        success: false,
        error: '站点管理器未初始化',
      );
    }

    // 双层防护：检查当前站点是否允许该操作
    final operation = _toolIdToOperation(request.toolId);
    if (operation != null && !sm.canExecuteOperation(operation)) {
      return ToolCallResult(
        toolId: request.toolId,
        content: '',
        success: false,
        error: '当前站点类型不支持此操作。'
            '静态站点不支持远程 CMS 操作，请先切换到动态 CMS 站点。',
      );
    }

    final adapter = sm.currentAdapter;
    if (adapter == null) {
      return ToolCallResult(
        toolId: request.toolId,
        content: '',
        success: false,
        error: '当前站点未配置或不是动态 CMS 站点',
      );
    }

    try {
      switch (request.toolId) {
        case 'wp_create_post':
        case 'ghost_create_post':
        case 'typecho_create_post':
          return _executeCreatePost(adapter, request);
        case 'wp_update_post':
        case 'ghost_update_post':
        case 'typecho_update_post':
          return _executeUpdatePost(adapter, request);
        case 'wp_delete_post':
        case 'ghost_delete_post':
        case 'typecho_delete_post':
          return _executeDeletePost(adapter, request);
        case 'wp_list_posts':
        case 'ghost_list_posts':
        case 'typecho_list_posts':
          return _executeListPosts(adapter, request);
        case 'wp_test_connection':
        case 'ghost_test_connection':
        case 'typecho_test_connection':
          return _executeTestConnection(adapter, request);
        case 'remote_media_upload':
          return _executeMediaUpload(adapter, request);
        default:
          return ToolCallResult(
            toolId: request.toolId,
            content: '',
            success: false,
            error: '未知的远程 CMS 工具: ${request.toolId}',
          );
      }
    } on BlogRepositoryException catch (e) {
      return ToolCallResult(
        toolId: request.toolId,
        content: '',
        success: false,
        error: '${e.message}',
      );
    } catch (e) {
      return ToolCallResult(
        toolId: request.toolId,
        content: '',
        success: false,
        error: '执行失败: $e',
      );
    }
  }

  /// 工具 ID → 操作类型映射
  static SiteOperation? _toolIdToOperation(String toolId) {
    switch (toolId) {
      case 'wp_create_post':
      case 'ghost_create_post':
      case 'typecho_create_post':
        return SiteOperation.remotePostCreate;
      case 'wp_update_post':
      case 'ghost_update_post':
      case 'typecho_update_post':
        return SiteOperation.remotePostUpdate;
      case 'wp_delete_post':
      case 'ghost_delete_post':
      case 'typecho_delete_post':
        return SiteOperation.remotePostDelete;
      case 'wp_list_posts':
      case 'ghost_list_posts':
      case 'typecho_list_posts':
        return SiteOperation.remotePostList;
      case 'wp_test_connection':
      case 'ghost_test_connection':
      case 'typecho_test_connection':
        return SiteOperation.remoteConnectionTest;
      case 'remote_media_upload':
        return SiteOperation.remoteMediaUpload;
      default:
        return null;
    }
  }

  /// 创建文章
  static Future<ToolCallResult> _executeCreatePost(
    BlogRepository adapter,
    ToolCallRequest req,
  ) async {
    final title = req.arguments['title']?.toString() ?? '';
    final contentMd = req.arguments['content_md']?.toString() ?? '';
    final status = req.arguments['status']?.toString() ?? 'draft';
    final slug = req.arguments['slug']?.toString();
    final tagsStr = req.arguments['tags']?.toString() ?? '';
    final categoriesStr = req.arguments['categories']?.toString() ?? '';

    if (title.isEmpty || contentMd.isEmpty) {
      return ToolCallResult(
        toolId: req.toolId,
        content: '',
        success: false,
        error: '标题和正文内容不能为空',
      );
    }

    final tags = tagsStr.isNotEmpty
        ? tagsStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    final categories = categoriesStr.isNotEmpty
        ? categoriesStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    final post = BlogPost(
      title: title,
      contentMd: contentMd,
      status: status,
      slug: slug,
      tags: tags,
      categories: categories,
      date: DateTime.now(),
      siteId: adapter.config.id,
      siteType: adapter.config.type,
    );

    final result = await adapter.createPost(post);
    final buf = StringBuffer();
    buf.writeln('文章发布成功！');
    buf.writeln('- ID: ${result.id}');
    buf.writeln('- 标题: ${result.title}');
    buf.writeln('- 状态: ${result.status}');
    if (result.link != null) {
      buf.writeln('- 链接: ${result.link}');
    }

    return ToolCallResult(toolId: req.toolId, content: buf.toString(), success: true);
  }

  /// 更新文章
  static Future<ToolCallResult> _executeUpdatePost(
    BlogRepository adapter,
    ToolCallRequest req,
  ) async {
    final postId = (req.arguments['post_id'] as num?)?.toInt();
    if (postId == null) {
      return ToolCallResult(
        toolId: req.toolId, content: '', success: false,
        error: '文章 ID 不能为空',
      );
    }

    // 先获取现有文章
    final existing = await adapter.getPostById(postId);
    if (existing == null) {
      return ToolCallResult(
        toolId: req.toolId, content: '', success: false,
        error: '文章不存在: ID=$postId',
      );
    }

    final title = req.arguments['title']?.toString() ?? existing.title;
    final contentMd = req.arguments['content_md']?.toString() ?? existing.contentMd;
    final status = req.arguments['status']?.toString() ?? existing.status;
    final slug = req.arguments['slug']?.toString() ?? existing.slug;

    final updated = existing.copyWith(
      title: title,
      contentMd: contentMd,
      status: status,
      slug: slug,
    );

    final result = await adapter.updatePost(updated);
    return ToolCallResult(
      toolId: req.toolId,
      content: '文章更新成功！\n- ID: ${result.id}\n- 标题: ${result.title}',
      success: true,
    );
  }

  /// 删除文章
  static Future<ToolCallResult> _executeDeletePost(
    BlogRepository adapter,
    ToolCallRequest req,
  ) async {
    final postId = (req.arguments['post_id'] as num?)?.toInt();
    if (postId == null) {
      return ToolCallResult(
        toolId: req.toolId, content: '', success: false,
        error: '文章 ID 不能为空',
      );
    }

    await adapter.deletePost(postId);
    return ToolCallResult(
      toolId: req.toolId,
      content: '文章已删除: ID=$postId',
      success: true,
    );
  }

  /// 文章列表
  static Future<ToolCallResult> _executeListPosts(
    BlogRepository adapter,
    ToolCallRequest req,
  ) async {
    final page = (req.arguments['page'] as num?)?.toInt() ?? 1;
    final perPage = (req.arguments['per_page'] as num?)?.toInt() ?? 10;
    final posts = await adapter.getPosts(page: page, perPage: perPage);

    if (posts.isEmpty) {
      return ToolCallResult(
        toolId: req.toolId,
        content: '暂无文章（第 $page 页）',
        success: true,
      );
    }

    final buf = StringBuffer();
    buf.writeln('文章列表（第 $page 页，共 ${posts.length} 篇）：\n');
    for (final post in posts) {
      final statusIcon = post.isPublished ? '📝' : '📄';
      buf.writeln('$statusIcon [${post.id}] ${post.title} (${post.status})');
      if (post.link != null) buf.writeln('   链接: ${post.link}');
    }

    return ToolCallResult(toolId: req.toolId, content: buf.toString(), success: true);
  }

  /// 连接测试
  static Future<ToolCallResult> _executeTestConnection(
    BlogRepository adapter,
    ToolCallRequest req,
  ) async {
    final result = await adapter.testConnection();
    return ToolCallResult(
      toolId: req.toolId,
      content: result.message,
      success: result.success,
      error: result.success ? null : result.errorDetail,
    );
  }

  /// 媒体上传
  static Future<ToolCallResult> _executeMediaUpload(
    BlogRepository adapter,
    ToolCallRequest req,
  ) async {
    final filePath = req.arguments['file_path']?.toString() ?? '';
    final base64Data = req.arguments['base64_data']?.toString() ?? '';
    final fileName = req.arguments['file_name']?.toString() ?? 'image.png';

    if (filePath.isEmpty && base64Data.isEmpty) {
      return ToolCallResult(
        toolId: 'remote_media_upload', content: '', success: false,
        error: '请提供 file_path 或 base64_data 参数',
      );
    }

    try {
      // 如果是 base64 数据，先写入临时文件
      String actualPath = filePath;
      if (base64Data.isNotEmpty) {
        final tempDir = await Directory.systemTemp.createTemp('hexo_upload_');
        actualPath = '${tempDir.path}/$fileName';
        final bytes = base64Decode(base64Data);
        await File(actualPath).writeAsBytes(bytes);
      }

      final result = await adapter.uploadMedia(actualPath);

      // 清理临时文件
      if (base64Data.isNotEmpty) {
        try { await File(actualPath).parent.delete(recursive: true); } catch (_) {}
      }

      if (result.isSuccess) {
        return ToolCallResult(
          toolId: 'remote_media_upload',
          content: '上传成功！\n- URL: ${result.url}\n- 媒体ID: ${result.mediaId}',
          success: true,
        );
      }

      return ToolCallResult(
        toolId: 'remote_media_upload',
        content: '',
        success: false,
        error: result.error ?? '上传失败',
      );
    } catch (e) {
      return ToolCallResult(
        toolId: 'remote_media_upload',
        content: '',
        success: false,
        error: '媒体上传异常: $e',
      );
    }
  }
}