import 'package:flutter/material.dart';

import '../core/repository/blog_repository.dart';
import '../models/blog_post.dart';
import '../services/log_service.dart';

/// 远程文章浏览面板
///
/// 从 CMS 站点拉取文章列表，支持：
/// - 分页浏览（单站点）、下拉刷新
/// - 点击加载到编辑器（HTML→Markdown 转换已在适配器中完成）
/// - 删除远程文章
///
/// 多站点模式（[allAdapters] 非空且多于一个站点）下支持：
/// - 全部站点：聚合查看所有 CMS 站点的文章
/// - 自选站点：勾选已登录（已配置密钥）的站点，仅查看这些站点的文章
class RemotePostsScreen extends StatefulWidget {
  /// 当前（活跃）CMS 站点适配器
  final BlogRepository adapter;

  /// 全部 CMS 站点适配器（用于全部站点 / 自选站点模式）
  final List<BlogRepository>? allAdapters;

  final LogService logService;
  final void Function(BlogPost post) onOpenInEditor;
  final Future<void> Function(BlogPost post) onDeletePost;

  const RemotePostsScreen({
    super.key,
    required this.adapter,
    this.allAdapters,
    required this.logService,
    required this.onOpenInEditor,
    required this.onDeletePost,
  });

  @override
  State<RemotePostsScreen> createState() => _RemotePostsScreenState();
}

/// 查看范围
enum _RemoteScope {
  /// 当前站点
  current,

  /// 全部站点
  all,

  /// 自选站点（勾选的已登录站点）
  selected,
}

class _RemotePostsScreenState extends State<RemotePostsScreen> {
  List<BlogPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  bool _hasMore = true;
  String? _error;
  late ScrollController _scrollController;

  _RemoteScope _scope = _RemoteScope.current;
  final Set<String> _checkedSites = {};

  bool get _multiSite => widget.allAdapters != null && widget.allAdapters!.length > 1;

  List<BlogRepository> get _allAdapters =>
      widget.allAdapters ?? <BlogRepository>[widget.adapter];

  /// 当前生效的适配器列表
  List<BlogRepository> get _activeAdapters {
    if (!_multiSite || _scope == _RemoteScope.current) {
      return [widget.adapter];
    }
    if (_scope == _RemoteScope.all) return _allAdapters;
    return _allAdapters
        .where((a) => _checkedSites.contains(a.config.id))
        .toList();
  }

  String _siteName(String? siteId) {
    for (final a in _allAdapters) {
      if (a.config.id == siteId) return a.config.name;
    }
    return siteId ?? '';
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    // 默认勾选已登录（已配置有效密钥）的站点
    for (final a in _allAdapters) {
      if (a.config.isValid) _checkedSites.add(a.config.id);
    }
    Future.microtask(() => _loadPosts());
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _changeScope(_RemoteScope scope) {
    if (_scope == scope) return;
    setState(() => _scope = scope);
    _loadPosts(refresh: true);
  }

  void _toggleSite(String siteId) {
    setState(() {
      if (_checkedSites.contains(siteId)) {
        _checkedSites.remove(siteId);
      } else {
        _checkedSites.add(siteId);
      }
    });
    if (_scope == _RemoteScope.selected) {
      _loadPosts(refresh: true);
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

    final adapters = _activeAdapters;
    if (adapters.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _posts = [];
          _error = '请至少勾选一个站点';
        });
      }
      return;
    }

    try {
      if (_multiSite && _scope != _RemoteScope.current) {
        // ── 多站点聚合模式 ──
        final results = await Future.wait(adapters.map((a) async {
          try {
            return await a.getPosts(page: 1, perPage: 30);
          } catch (e) {
            debugPrint('RemotePosts: load site ${a.config.name} failed: $e');
            return <BlogPost>[];
          }
        }));
        final merged = <BlogPost>[];
        final seen = <String>{};
        for (var i = 0; i < results.length; i++) {
          final siteId = adapters[i].config.id;
          for (final p in results[i]) {
            final key = '${p.siteId ?? siteId}:${p.id}';
            if (seen.contains(key)) continue;
            seen.add(key);
            merged.add(p);
          }
        }
        merged.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
        if (mounted) {
          setState(() {
            _posts = merged;
            _hasMore = false;
            _loading = false;
            _loadingMore = false;
            _error = null;
          });
        }
      } else {
        // ── 单站点分页模式 ──
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
    if (_multiSite && _scope != _RemoteScope.current) return; // 聚合模式不分页
    if (!mounted) return;
    setState(() {
      _loadingMore = true;
      _page++;
    });
    await _loadPosts();
  }

  Future<void> _deletePost(BlogPost post) async {
    if (post.id == null) return;
    final siteLabel = _multiSite ? '（${_siteName(post.siteId)}）' : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除远程文章「${post.title}」$siteLabel 吗？\n此操作不可撤销。'),
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

  String get _headerTitle {
    if (!_multiSite) return '${widget.adapter.config.type.name} 远程文章';
    return switch (_scope) {
      _RemoteScope.current => '当前站点 · ${widget.adapter.config.name}',
      _RemoteScope.all => '全部站点远程文章',
      _RemoteScope.selected => '自选站点远程文章',
    };
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
              Expanded(
                child: Text(
                  _headerTitle,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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

        // ── 多站点范围选择 ──
        if (_multiSite) ...[
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: SegmentedButton<_RemoteScope>(
              segments: const [
                ButtonSegment(
                  value: _RemoteScope.current,
                  label: Text('当前站点'),
                  icon: Icon(Icons.trip_origin, size: 16),
                ),
                ButtonSegment(
                  value: _RemoteScope.all,
                  label: Text('全部站点'),
                  icon: Icon(Icons.dns, size: 16),
                ),
                ButtonSegment(
                  value: _RemoteScope.selected,
                  label: Text('自选站点'),
                  icon: Icon(Icons.checklist, size: 16),
                ),
              ],
              selected: {_scope},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (v) => _changeScope(v.first),
            ),
          ),
          const Divider(height: 1),
          // 自选站点：站点勾选列表
          if (_scope == _RemoteScope.selected) ...[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _allAdapters.map((a) {
                  final checked = _checkedSites.contains(a.config.id);
                  return FilterChip(
                    label: Text(
                      a.config.name,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: checked,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _toggleSite(a.config.id),
                  );
                }).toList(),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              color: Colors.white,
              child: Text(
                '仅展示已勾选站点的远程文章；默认勾选已登录（已配置密钥）的站点。',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
            const Divider(height: 1),
          ],
        ],

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
                                        // 站点标签（多站点模式）
                                        if (_multiSite && post.siteId != null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0EA5E9).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _siteName(post.siteId),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF0E7490),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
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
