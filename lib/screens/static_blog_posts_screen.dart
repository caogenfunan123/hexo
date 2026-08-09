import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../core/repository/blog_repository.dart';
import '../core/repository/static_blog_repository.dart';
import '../core/site_manager.dart';
import '../models/blog_post.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../services/log_service.dart';
import '../services/static_blog_batch_publish_service.dart';

/// 静态博客文章管理界面
///
/// 专门用于管理 Hexo、Hugo、Astro 等静态博客框架的文章
/// 支持文章列表浏览、搜索、分页等功能
class StaticBlogPostsScreen extends StatefulWidget {
  /// 当前静态博客仓库配置
  final RepoConfig repoConfig;

  /// 站点管理器
  final SiteManager siteManager;

  /// 日志服务
  final LogService logService;

  /// 打开文章到编辑器的回调
  final void Function(BlogPost post) onOpenInEditor;

  /// 删除文章的回调
  final Future<void> Function(BlogPost post) onDeletePost;

  const StaticBlogPostsScreen({
    super.key,
    required this.repoConfig,
    required this.siteManager,
    required this.logService,
    required this.onOpenInEditor,
    required this.onDeletePost,
  });

  @override
  State<StaticBlogPostsScreen> createState() => _StaticBlogPostsScreenState();
}

class _StaticBlogPostsScreenState extends State<StaticBlogPostsScreen> {
  List<BlogPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  bool _hasMore = true;
  
  /// 选中的文章列表
  final Set<String> _selectedPostIds = {};
  
  /// 批量发布服务
  late final StaticBlogBatchPublishService _batchPublishService;
  
  /// 批量发布进度
  int _batchPublishProgress = 0;
  int _batchPublishTotal = 0;
  String _batchPublishMessage = '';
  bool _isBatchPublishing = false;
  String? _error;
  late ScrollController _scrollController;
  
  // 搜索相关
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  // 静态博客适配器
  late StaticBlogRepository _repository;

@override
  void initState() {
    super.initState();
    _loadPosts();
    
    // 初始化批量发布服务
    _batchPublishService = StaticBlogBatchPublishService(
      settings: AppSettings(), // 这里需要传入实际的设置
      siteManager: widget.siteManager,
      gitService: GitHubService(), // 这里需要传入实际的 Git 服务
      templateService: TemplateService(), // 这里需要传入模板服务
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _repository.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (refresh) {
      if (!mounted) return;
      setState(() {
        _page = 1;
        _posts = [];
        _hasMore = true;
        _loading = true;
        _error = null;
      });
    }

    try {
      // 获取文章列表
      final posts = await _repository.getPosts(page: _page, perPage: 20);
      
      // 如果有搜索查询，进行过滤
      List<BlogPost> filteredPosts = posts;
      if (_searchQuery.isNotEmpty) {
        filteredPosts = posts.where((post) {
          final searchLower = _searchQuery.toLowerCase();
          return post.title.toLowerCase().contains(searchLower) ||
                 post.excerpt.toLowerCase().contains(searchLower) ||
                 post.author.toLowerCase().contains(searchLower);
        }).toList();
      }
      
      if (mounted) {
        setState(() {
          if (refresh) {
            _posts = filteredPosts;
          } else {
            _posts.addAll(filteredPosts);
          }
          _hasMore = posts.length >= 20;
          _loading = false;
          _loadingMore = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    if (!mounted) return;
    
    setState(() {
      _loadingMore = true;
      _page++;
    });
    
    await _loadPosts();
  }

  Future<void> _deletePost(BlogPost post) async {
    if (post.id == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除文章「${post.title}」吗？\n此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.onDeletePost(post);
      setState(() => _posts.removeWhere((p) => p.id == post.id && p.siteId == post.siteId));
      widget.logService.add('删除静态博客文章', '标题: ${post.title}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除: ${post.title}')),
        );
      }
    } catch (e) {
      widget.logService.add('删除静态博客文章失败', '$e', success: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── 头部信息 ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              const Icon(Icons.code, size: 18, color: Color(0xFF059669)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '静态博客 · ${widget.repoConfig.name}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${widget.repoConfig.frameworkId.toUpperCase()} · ${_posts.length} 篇文章',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _loading ? null : () => _loadPosts(refresh: true),
                tooltip: '刷新',
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── 搜索栏 ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索文章标题、内容或作者...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                    // 防抖搜索
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (_searchQuery == value) {
                        _loadPosts(refresh: true);
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                    _loadPosts(refresh: true);
                  },
                ),
              const SizedBox(width: 8),
              if (_selectedPostIds.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.publish, size: 20),
                  onPressed: _isBatchPublishing ? null : _showBatchPublishDialog,
                  tooltip: '批量发布文章',
                ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── 错误提示 ──
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.red.withOpacity(0.05),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => _loadPosts(refresh: true),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),

        // ── 文章列表 ──
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _posts.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.article_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          '暂无文章',
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '点击刷新按钮重新加载',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        ),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadPosts(refresh: true),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _posts.length + (_hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= _posts.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            );
                          }
                          final post = _posts[i];
                          final preview = post.contentMd.isNotEmpty
                              ? post.contentMd.replaceAll(RegExp(r'\s+'), ' ').trim()
                              : post.contentHtml?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            color: Colors.white,
                            elevation: 0,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => widget.onOpenInEditor(post),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            post.title.isEmpty ? '（无标题）' : post.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // 状态标签
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: post.isPublished
                                                ? const Color(0xFF059669).withOpacity(0.1)
                                                : const Color(0xFFD97706).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            post.isPublished ? '已发布' : '草稿',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: post.isPublished
                                                  ? const Color(0xFF059669)
                                                  : const Color(0xFFD97706),
                                            ),
                                          ),
                                        ),
                                        // 删除按钮
                                        PopupMenuButton<String>(
                                          onSelected: (v) {
                                            if (v == 'delete') _deletePost(post);
                                          },
                                          icon: const Icon(Icons.more_horiz, size: 18),
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text('删除文章'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (preview.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        preview,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    // 元数据
                                    Row(
                                      children: [
                                        Icon(Icons.access_time, size: 13, color: Colors.grey.shade400),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDate(post.modifiedDate),
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                        ),
                                        if (post.id != null) ...[
                                          const SizedBox(width: 12),
                                          Icon(Icons.tag, size: 13, color: Colors.grey.shade400),
                                          const SizedBox(width: 4),
                                          Text(
                                            'ID: ${post.id}',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                          ),
                                        ],
                                        if (post.tags.isNotEmpty) ...[
                                          const SizedBox(width: 12),
                                          Icon(Icons.label_outline, size: 13, color: Colors.grey.shade400),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              post.tags.take(3).join(', '),
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  /// 显示批量发布对话框
  void _showBatchPublishDialog() {
    final selectedPosts = _posts.where((post) => _selectedPostIds.contains(post.id)).toList();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量发布文章'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已选择 ${selectedPosts.length} 篇文章'),
            const SizedBox(height: 16),
            const Text('发布选项：'),
            RadioListTile<String>(
              title: const Text('发布到所有站点'),
              value: 'all',
              groupValue: 'all',
              onChanged: (value) => _startBatchPublish(selectedPosts, null),
            ),
            RadioListTile<String>(
              title: const Text('发布到选定站点'),
              value: 'selected',
              groupValue: 'selected',
              onChanged: (value) => _showSiteSelector(selectedPosts),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 显示站点选择器
  void _showSiteSelector(List<BlogPost> selectedPosts) {
    // 获取所有静态博客站点
    final staticSites = widget.siteManager.staticSites
        .where((site) => site.isStatic)
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择发布站点'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: staticSites.length,
            itemBuilder: (context, index) {
              final site = staticSites[index];
              return CheckboxListTile(
                title: Text(site.name),
                value: _selectedSiteIds.contains(site.id),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedSiteIds.add(site.id);
                    } else {
                      _selectedSiteIds.remove(site.id);
                    }
                  });
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (_selectedSiteIds.isNotEmpty) {
                _startBatchPublish(selectedPosts, _selectedSiteIds.toList());
              }
            },
            child: const Text('发布'),
          ),
        ],
      ),
    );
  }

  /// 开始批量发布
  void _startBatchPublish(List<BlogPost> selectedPosts, List<String>? selectedSiteIds) {
    Navigator.of(context).pop();
    
    if (selectedPosts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有选择要发布的文章')),
      );
      return;
    }

    setState(() {
      _isBatchPublishing = true;
      _batchPublishProgress = 0;
      _batchPublishTotal = selectedPosts.length;
      _batchPublishMessage = '开始批量发布...';
    });

    // 发布第一篇文章
    _publishNextPost(selectedPosts, selectedSiteIds, 0);
  }

  /// 发布下一篇文章
  void _publishNextPost(List<BlogPost> selectedPosts, List<String>? selectedSiteIds, int index) {
    if (index >= selectedPosts.length) {
      // 所有文章发布完成
      setState(() {
        _isBatchPublishing = false;
        _selectedPostIds.clear();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('批量发布完成')),
      );
      return;
    }

    final post = selectedPosts[index];
    
    _batchPublishService.batchPublishToStaticBlogs(
      post,
      selectedSiteIds: selectedSiteIds,
      onProgress: (current, total, message) {
        setState(() {
          _batchPublishProgress = current;
          _batchPublishTotal = total;
          _batchPublishMessage = message;
        });
      },
      onComplete: (success, message, results) {
        setState(() {
          _batchPublishProgress = index + 1;
          _batchPublishMessage = message;
        });

        // 显示发布结果
        _showBatchPublishResults(results);

        // 继续发布下一篇文章
        _publishNextPost(selectedPosts, selectedSiteIds, index + 1);
      },
    );
  }

  /// 显示批量发布结果
  void _showBatchPublishResults(Map<String, dynamic> results) {
    final successCount = results.values.where((r) => r['success'] == true).length;
    final failCount = results.values.where((r) => r['success'] == false).length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('批量发布结果'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('成功: $successCount, 失败: $failCount'),
            const SizedBox(height: 16),
            ...results.entries.map((entry) {
              final result = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      result['success'] == true ? Icons.check_circle : Icons.error,
                      color: result['success'] == true ? Colors.green : Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                          Text(result['message'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}