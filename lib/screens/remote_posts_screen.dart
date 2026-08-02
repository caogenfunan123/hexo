import 'package:flutter/material.dart';

import '../core/repository/blog_repository.dart';
import '../models/blog_post.dart';
import '../services/log_service.dart';

/// 远程文章浏览面板
///
/// 从当前 CMS 站点拉取文章列表，支持：
/// - 分页浏览
/// - 下拉刷新
/// - 点击加载到编辑器（HTML→Markdown 转换已在适配器中完成）
/// - 删除远程文章
class RemotePostsScreen extends StatefulWidget {
  final BlogRepository adapter;
  final LogService logService;
  final void Function(BlogPost post) onOpenInEditor;
  final Future<void> Function(BlogPost post) onDeletePost;

  const RemotePostsScreen({
    super.key,
    required this.adapter,
    required this.logService,
    required this.onOpenInEditor,
    required this.onDeletePost,
  });

  @override
  State<RemotePostsScreen> createState() => _RemotePostsScreenState();
}

class _RemotePostsScreenState extends State<RemotePostsScreen> {
  List<BlogPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _posts = [];
        _hasMore = true;
        _loading = true;
        _error = null;
      });
    }

    try {
      final posts = await widget.adapter.getPosts(page: _page, perPage: 20);
      if (mounted) {
        setState(() {
          if (refresh) {
            _posts = posts;
          } else {
            _posts.addAll(posts);
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
        content: Text('确定要删除远程文章「${post.title}」吗？\n此操作不可撤销。'),
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
      setState(() => _posts.removeWhere((p) => p.id == post.id));
      widget.logService.add('删除远程文章', '标题: ${post.title}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除: ${post.title}')),
        );
      }
    } catch (e) {
      widget.logService.add('删除远程文章失败', '$e', success: false);
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
              const Icon(Icons.cloud_outlined, size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text(
                '${widget.adapter.config.type.displayName} 远程文章',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${_posts.length} 篇',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _loading ? null : () => _loadPosts(refresh: true),
                tooltip: '刷新',
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
                          '暂无远程文章',
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
                        padding: const EdgeInsets.all(12),
                        itemCount: _posts.length + (_hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= _posts.length) {
                            // 加载更多指示器
                            if (!_loadingMore) {
                              WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
                            }
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
                                              child: Text('删除远程文章'),
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
}