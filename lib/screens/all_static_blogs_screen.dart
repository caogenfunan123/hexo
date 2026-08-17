import 'dart:io';

import 'package:flutter/material.dart';

import '../core/repository/static_blog_repository.dart';
import '../models/app_settings.dart';
import '../models/blog_post.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../services/log_service.dart';

/// 全部静态博客文章聚合管理界面
///
/// 聚合所有静态博客仓库的文章，支持搜索、批量选择与批量删除。
/// 带快照缓存：二次打开先直出缓存，再按仓库指纹增量刷新。
class AllStaticBlogsScreen extends StatefulWidget {
  /// 全部静态博客仓库
  final List<RepoConfig> repos;

  final AppSettings settings;
  final GitHubService githubService;
  final LogService logService;

  /// 快照缓存根目录提供者（null 禁用缓存）
  final Future<Directory> Function()? snapshotRootProvider;

  /// 打开文章到编辑器的回调
  final void Function(BlogPost post) onOpenInEditor;

  /// 删除文章的回调（需从仓库中定位并删除文件）
  final Future<void> Function(BlogPost post) onDeletePost;

  const AllStaticBlogsScreen({
    super.key,
    required this.repos,
    required this.settings,
    required this.githubService,
    required this.logService,
    this.snapshotRootProvider,
    required this.onOpenInEditor,
    required this.onDeletePost,
  });

  @override
  State<AllStaticBlogsScreen> createState() => _AllStaticBlogsScreenState();
}

class _AllStaticBlogsScreenState extends State<AllStaticBlogsScreen> {
  late final List<StaticBlogRepository> _repositories;

  List<BlogPost> _posts = [];
  bool _loading = true;
  String? _error;
  final Set<String> _selectedKeys = {};
  bool _deleting = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String _repoName(String? siteId) {
    for (final r in widget.repos) {
      if (r.id == siteId) return r.name;
    }
    return siteId ?? '';
  }

  String _postKey(BlogPost post) =>
      '${post.siteId}:${post.link ?? post.title}';

  @override
  void initState() {
    super.initState();
    _repositories = widget.repos.map((r) {
      return StaticBlogRepository(
        repoConfig: r,
        appSettings: widget.settings,
        githubService: widget.githubService,
        logService: widget.logService,
        snapshotRootProvider: widget.snapshotRootProvider,
      );
    }).toList();
    // 先直出缓存，再增量刷新
    _loadWithCache();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final r in _repositories) {
      r.dispose();
    }
    super.dispose();
  }

  /// 带快照缓存的加载：先直出缓存立即渲染，再逐个仓库比对指纹增量刷新
  Future<void> _loadWithCache() async {
    // 第一阶段：读缓存快照立即渲染（无网络）
    if (widget.snapshotRootProvider != null) {
      final cachedMerged = await _loadAllFromCache();
      if (cachedMerged != null) {
        if (!mounted) return;
        setState(() {
          _posts = cachedMerged;
          _loading = false;
          _error = null;
        });
      }
    }
    // 第二阶段：按指纹比对，仅对变化的仓库重拉
    await _refreshChanged();
  }

  /// 从各仓库缓存快照合并文章（全部缓存缺失时返回 null）
  Future<List<BlogPost>?> _loadAllFromCache() async {
    final merged = <BlogPost>[];
    final seen = <String>{};
    var loadedAny = false;
    for (var i = 0; i < _repositories.length; i++) {
      final repo = _repositories[i];
      final snap = await repo.loadSnapshot();
      if (snap == null) continue;
      loadedAny = true;
      for (final p in snap.posts) {
        final key = '${p.siteId ?? widget.repos[i].id}:${p.link ?? p.title}';
        if (seen.contains(key)) continue;
        seen.add(key);
        merged.add(p);
      }
    }
    if (!loadedAny) return null;
    merged.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
    return merged;
  }

  /// 增量刷新：每个仓库比对指纹，无变化跳过网络，有变化重拉该仓库
  Future<void> _refreshChanged() async {
    final results = <List<BlogPost>?>[];
    try {
      results.addAll(await Future.wait(_repositories.map((repo) async {
        try {
          // 重新拉取：缓存失效（指纹变化/无缓存）时才会发网络请求
          return await repo.getPostsCached(forceRefresh: false);
        } catch (e) {
          // 单仓库失败：保留该仓库既有缓存展示，不阻断整体
          debugPrint('AllStaticBlogs: refresh ${repo.repoConfig.name}: $e');
          return null;
        }
      })));
    } catch (e) {
      debugPrint('AllStaticBlogs: 增量刷新失败 $e');
      return;
    }

    if (!mounted) return;
    // 失败仓库（null）沿用当前已渲染数据，未失败仓库用最新结果
    final next = <BlogPost>[];
    final seen = <String>{};
    for (var i = 0; i < results.length; i++) {
      final list = results[i];
      if (list == null) continue;
      final siteId = widget.repos[i].id;
      for (final p in list) {
        final key = '${p.siteId ?? siteId}:${p.link ?? p.title}';
        if (seen.contains(key)) continue;
        seen.add(key);
        next.add(p);
      }
    }
    next.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
    setState(() {
      if (next.isNotEmpty) _posts = next;
      _loading = false;
      if (_error != null) _error = null;
    });
  }

  /// 强制全量刷新：跳过缓存，全部仓库重新拉取并重建缓存
  Future<void> _forceRefresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait(_repositories.map((repo) async {
        try {
          return await repo.getPostsCached(forceRefresh: true);
        } catch (e) {
          debugPrint('AllStaticBlogs: force ${repo.repoConfig.name}: $e');
          return <BlogPost>[];
        }
      }));

      final merged = _mergePosts(results);

      if (!mounted) return;
      setState(() {
        _posts = merged;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// 合并多仓库文章并去重排序
  List<BlogPost> _mergePosts(List<List<BlogPost>> results) {
    final merged = <BlogPost>[];
    final seen = <String>{};
    for (var i = 0; i < results.length; i++) {
      final siteId = widget.repos[i].id;
      for (final p in results[i]) {
        final key = '${p.siteId ?? siteId}:${p.link ?? p.title}';
        if (seen.contains(key)) continue;
        seen.add(key);
        merged.add(p);
      }
    }
    merged.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
    return merged;
  }

  /// 兼容旧调用：直接全量加载（保留原语义）
  Future<void> _loadPosts() => _forceRefresh();

  List<BlogPost> get _filteredPosts {
    if (_searchQuery.isEmpty) return _posts;
    final q = _searchQuery.toLowerCase();
    return _posts.where((p) {
      return p.title.toLowerCase().contains(q) ||
          p.contentMd.toLowerCase().contains(q) ||
          _repoName(p.siteId).toLowerCase().contains(q);
    }).toList();
  }

  /// 单篇删除
  Future<void> _deletePost(BlogPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
            '确定要删除文章「${post.title}」（${_repoName(post.siteId)}）吗？\n此操作不可撤销。'),
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
      widget.logService.add('删除博客文章', '标题: ${post.title}');
    } catch (e) {
      widget.logService.add('删除博客文章失败', '$e', success: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  /// 批量删除选中文章
  Future<void> _deleteSelected() async {
    final selected = _posts
        .where((p) => _selectedKeys.contains(_postKey(p)))
        .toList();
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认批量删除'),
        content: Text('确定要删除选中的 ${selected.length} 篇文章吗？\n此操作不可撤销。'),
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

    setState(() => _deleting = true);
    final success = <String>[];
    final failed = <String>[];

    for (final post in selected) {
      try {
        await widget.onDeletePost(post);
        success.add(post.title);
      } catch (e) {
        failed.add('${post.title}: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _deleting = false;
      _posts.removeWhere((p) => _selectedKeys.contains(_postKey(p)));
      _selectedKeys.clear();
    });

    widget.logService
        .add('批量删除博客文章', '成功 ${success.length} / 失败 ${failed.length}');
    _showDeleteResult(success, failed);
  }

  void _showDeleteResult(List<String> success, List<String> failed) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text('批量删除结果 · 成功 ${success.length} / 失败 ${failed.length}'),
        content: SizedBox(
          width: double.maxFinite,
          child: failed.isEmpty
              ? const Text('全部删除成功')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: failed.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            failed[index],
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
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

  void _toggleSelect(BlogPost post) {
    setState(() {
      final key = _postKey(post);
      _selectedKeys.contains(key)
          ? _selectedKeys.remove(key)
          : _selectedKeys.add(key);
    });
  }

  void _selectAllVisible() {
    final visible = _filteredPosts;
    setState(() {
      if (visible.every((p) => _selectedKeys.contains(_postKey(p)))) {
        _selectedKeys.removeAll(visible.map(_postKey));
      } else {
        _selectedKeys.addAll(visible.map(_postKey));
      }
    });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('全部博客管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loading || _deleting ? null : _forceRefresh,
            tooltip: '强制刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 搜索 + 批量操作栏 ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '搜索文章标题、内容或仓库...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
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
                  ],
                ),
                if (_selectedKeys.isNotEmpty || _deleting) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _deleting ? null : _selectAllVisible,
                        icon: const Icon(Icons.select_all, size: 18),
                        label: Text(
                          _filteredPosts.isNotEmpty &&
                                  _filteredPosts.every((p) =>
                                      _selectedKeys.contains(_postKey(p)))
                              ? '取消全选'
                              : '全选',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '已选 ${_selectedKeys.length} 篇',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Spacer(),
                      if (_deleting)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      TextButton.icon(
                        onPressed: _deleting ? null : _deleteSelected,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('批量删除',
                            style: TextStyle(fontSize: 13)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
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
                  const Icon(Icons.error_outline,
                      color: Colors.red, size: 18),
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
                    onPressed: () => _forceRefresh(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),

          // ── 文章列表 ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPosts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.article_outlined,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              _posts.isEmpty ? '暂无文章' : '无匹配结果',
                              style: TextStyle(
                                  fontSize: 16, color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '点击右上角刷新重新加载',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade400),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _forceRefresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredPosts.length,
                          itemBuilder: (_, i) {
                            final post = _filteredPosts[i];
                            final key = _postKey(post);
                            final selected = _selectedKeys.contains(key);
                            final preview = post.contentMd.isNotEmpty
                                ? post.contentMd
                                    .replaceAll(RegExp(r'\s+'), ' ')
                                    .trim()
                                : '';

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
                                onLongPress: () => _toggleSelect(post),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          // 勾选框
                                          GestureDetector(
                                            onTap: () => _toggleSelect(post),
                                            child: Icon(
                                              selected
                                                  ? Icons.check_circle
                                                  : Icons
                                                      .radio_button_unchecked,
                                              size: 18,
                                              color: selected
                                                  ? const Color(0xFF0EA5E9)
                                                  : Colors.grey.shade400,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
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
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF64748B)
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _repoName(post.siteId),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
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
                                              post.isPublished
                                                  ? '已发布'
                                                  : '草稿',
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
                                            icon: const Icon(
                                                Icons.more_horiz,
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
                                                color:
                                                    Colors.grey.shade400),
                                          ),
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
      ),
    );
  }
}
