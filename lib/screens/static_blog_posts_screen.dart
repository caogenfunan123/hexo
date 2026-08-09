import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/repository/static_blog_repository.dart';
import '../core/site_manager.dart';
import '../models/app_settings.dart';
import '../models/blog_post.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../services/log_service.dart';
import '../services/static_blog_batch_publish_service.dart';
import '../services/template_service.dart';

/// 静态博客文章管理界面
///
/// 管理 Hexo、Hugo、Astro 等静态博客框架的文章，
/// 支持列表浏览、搜索、批量发布到所有静态博客站点。
class StaticBlogPostsScreen extends StatefulWidget {
  final RepoConfig repoConfig;
  final SiteManager siteManager;
  final AppSettings settings;
  final GitHubService githubService;
  final LogService logService;
  final void Function(BlogPost post) onOpenInEditor;
  final Future<void> Function(BlogPost post) onDeletePost;

  const StaticBlogPostsScreen({
    super.key,
    required this.repoConfig,
    required this.siteManager,
    required this.settings,
    required this.githubService,
    required this.logService,
    required this.onOpenInEditor,
    required this.onDeletePost,
  });

  @override
  State<StaticBlogPostsScreen> createState() => _StaticBlogPostsScreenState();
}

class _StaticBlogPostsScreenState extends State<StaticBlogPostsScreen> {
  late final StaticBlogRepository _repository;
  late final StaticBlogBatchPublishService _batchPublishService;

  List<BlogPost> _posts = [];
  bool _loading = true;
  bool _hasMore = false;
  final Set<String> _selectedPostKeys = {};
  final Set<String> _selectedSiteIds = {};
  int _batchProgress = 0;
  int _batchTotal = 0;
  String _batchMessage = '';
  bool _isBatchPublishing = false;
  String? _error;
  late final ScrollController _scrollController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _repository = StaticBlogRepository(
      repoConfig: widget.repoConfig,
      appSettings: widget.settings,
      githubService: widget.githubService,
      logService: widget.logService,
    );
    _batchPublishService = StaticBlogBatchPublishService(
      settings: widget.settings,
      siteManager: widget.siteManager,
      githubService: widget.githubService,
      templateService: TemplateService(),
    );
    _loadPosts(refresh: true);
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

  String _postKey(BlogPost post) => post.link ?? post.title;

  Future<void> _loadPosts({bool refresh = false}) async {
    try {
      final posts = await _repository.getPosts(page: 1, perPage: 50);
      List<BlogPost> filtered = posts;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        filtered = posts
            .where((p) =>
                p.title.toLowerCase().contains(q) ||
                p.contentMd.toLowerCase().contains(q))
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _posts = filtered;
        _hasMore = false;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    // 当前仓库单次拉取已包含全部文章，分页留空
  }

  Future<void> _deletePost(BlogPost post) async {
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
      if (!mounted) return;
      setState(() => _posts.removeWhere((p) => _postKey(p) == _postKey(post)));
      widget.logService.add('删除静态博客文章', '标题: ${post.title}');
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
              if (_isBatchPublishing)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '$_batchProgress/$_batchTotal',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF0EA5E9)),
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
                    hintText: '搜索文章标题或内容...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
              const SizedBox(width: 8),
              if (_selectedPostKeys.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.publish, size: 20),
                  onPressed:
                      _isBatchPublishing ? null : _showBatchPublishDialog,
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

        // ── 批量发布进度条 ──
        if (_isBatchPublishing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _batchMessage,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.article_outlined,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              '暂无文章',
                              style: TextStyle(
                                  fontSize: 16, color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '点击刷新按钮重新加载',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade400),
                            ),
                          ]),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadPosts(refresh: true),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _posts.length,
                        itemBuilder: (_, i) {
                          final post = _posts[i];
                          final preview = post.contentMd.isNotEmpty
                              ? post.contentMd
                                  .replaceAll(RegExp(r'\s+'), ' ')
                                  .trim()
                              : post.contentHtml
                                      ?.replaceAll(RegExp(r'<[^>]+>'), '')
                                      .trim() ??
                                  '';
                          final key = _postKey(post);
                          final selected = _selectedPostKeys.contains(key);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            color: selected
                                ? const Color(0xFFE0F2FE)
                                : Colors.white,
                            elevation: 0,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => widget.onOpenInEditor(post),
                              onLongPress: () {
                                setState(() {
                                  selected
                                      ? _selectedPostKeys.remove(key)
                                      : _selectedPostKeys.add(key);
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (selected) ...[
                                          const Icon(Icons.check_circle,
                                              size: 16,
                                              color: Color(0xFF0EA5E9)),
                                          const SizedBox(width: 6),
                                        ],
                                        Expanded(
                                          child: Text(
                                            post.title.isEmpty
                                                ? '（无标题）'
                                                : post.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: post.isPublished
                                                ? const Color(0xFF059669)
                                                    .withOpacity(0.1)
                                                : const Color(0xFFD97706)
                                                    .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
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
                                        PopupMenuButton<String>(
                                          onSelected: (v) {
                                            if (v == 'delete') {
                                              _deletePost(post);
                                            }
                                          },
                                          icon: const Icon(Icons.more_horiz,
                                              size: 18),
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
                                    Row(
                                      children: [
                                        Icon(Icons.access_time,
                                            size: 13,
                                            color: Colors.grey.shade400),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDate(post.modifiedDate),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade400),
                                        ),
                                        if (post.tags.isNotEmpty) ...[
                                          const SizedBox(width: 12),
                                          Icon(Icons.label_outline,
                                              size: 13,
                                              color: Colors.grey.shade400),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              post.tags.take(3).join(', '),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade400),
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

  /// 显示批量发布对话框（选择全部站点或指定站点）
  void _showBatchPublishDialog() {
    final selectedPosts = _posts
        .where((p) => _selectedPostKeys.contains(_postKey(p)))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量发布文章'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已选择 ${selectedPosts.length} 篇文章'),
            const SizedBox(height: 16),
            const Text('发布选项：'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.public),
              title: const Text('发布到所有静态博客站点'),
              subtitle: const Text('自动转换为各站点框架格式并推送'),
              onTap: () {
                Navigator.pop(ctx);
                _startBatchPublish(selectedPosts, null);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.web),
              title: const Text('发布到选定站点'),
              subtitle: const Text('从静态博客列表中勾选目标仓库'),
              onTap: () {
                Navigator.pop(ctx);
                _showSiteSelector(selectedPosts);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 显示站点选择器
  void _showSiteSelector(List<BlogPost> selectedPosts) {
    final staticRepos = widget.siteManager.staticRepos.toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('选择发布站点'),
          content: SizedBox(
            width: double.maxFinite,
            child: staticRepos.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无静态博客仓库，请在设置中添加'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: staticRepos.length,
                    itemBuilder: (context, index) {
                      final repo = staticRepos[index];
                      return CheckboxListTile(
                        title: Text(repo.name),
                        subtitle: Text(repo.fullName),
                        value: _selectedSiteIds.contains(repo.id),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              _selectedSiteIds.add(repo.id);
                            } else {
                              _selectedSiteIds.remove(repo.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (_selectedSiteIds.isNotEmpty) {
                  _startBatchPublish(
                      selectedPosts, _selectedSiteIds.toList());
                }
              },
              child: const Text('发布'),
            ),
          ],
        ),
      ),
    );
  }

  /// 开始批量发布
  void _startBatchPublish(
      List<BlogPost> selectedPosts, List<String>? selectedSiteIds) {
    if (selectedPosts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有选择要发布的文章')),
      );
      return;
    }

    setState(() {
      _isBatchPublishing = true;
      _batchProgress = 0;
      _batchTotal = selectedPosts.length;
      _batchMessage = '开始批量发布...';
    });

    _publishNextPost(selectedPosts, selectedSiteIds, 0);
  }

  /// 发布下一篇文章
  void _publishNextPost(
      List<BlogPost> selectedPosts, List<String>? selectedSiteIds, int index) {
    if (index >= selectedPosts.length) {
      setState(() {
        _isBatchPublishing = false;
        _selectedPostKeys.clear();
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
        if (!mounted) return;
        setState(() {
          _batchProgress = current;
          _batchTotal = total;
          _batchMessage = message;
        });
      },
      onComplete: (success, message, results) {
        if (!mounted) return;
        setState(() {
          _batchProgress = index + 1;
          _batchMessage = message;
        });
        _showBatchPublishResults(results);
        _publishNextPost(selectedPosts, selectedSiteIds, index + 1);
      },
    );
  }

  /// 显示批量发布结果
  void _showBatchPublishResults(Map<String, dynamic> results) {
    final successCount =
        results.values.where((r) => r['success'] == true).length;
    final failCount =
        results.values.where((r) => r['success'] == false).length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('批量发布结果 · 成功 $successCount / 失败 $failCount'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: results.length,
            itemBuilder: (context, index) {
              final entry = results.entries.elementAt(index);
              final result = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      result['success'] == true
                          ? Icons.check_circle
                          : Icons.error,
                      color: result['success'] == true
                          ? Colors.green
                          : Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500)),
                          Text(result['message'] ?? '',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
