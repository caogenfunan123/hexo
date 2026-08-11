import 'package:flutter/material.dart';

import '../core/repository/blog_repository.dart';
import '../core/site_manager.dart';
import '../models/blog_post.dart';
import '../services/log_service.dart';

/// 统一的远程文章管理界面
///
/// 支持同时管理静态博客和动态CMS站点的文章
/// 提供站点筛选、类型筛选、搜索等功能
class UnifiedRemotePostsScreen extends StatefulWidget {
  /// 站点管理器
  final SiteManager siteManager;

  /// 日志服务
  final LogService logService;

  /// 打开文章到编辑器的回调
  final void Function(BlogPost post) onOpenInEditor;

  /// 删除文章的回调
  final Future<void> Function(BlogPost post) onDeletePost;

  const UnifiedRemotePostsScreen({
    super.key,
    required this.siteManager,
    required this.logService,
    required this.onOpenInEditor,
    required this.onDeletePost,
  });

  @override
  State<UnifiedRemotePostsScreen> createState() => _UnifiedRemotePostsScreenState();
}

/// 站点类型筛选
enum _SiteTypeFilter {
  all,
  static,
  dynamic,
}

/// 站点范围筛选
enum _SiteScopeFilter {
  current,
  all,
  selected,
}

class _UnifiedRemotePostsScreenState extends State<UnifiedRemotePostsScreen> {
  List<BlogPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  bool _hasMore = true;
  String? _error;
  late ScrollController _scrollController;
  
  // 筛选相关
  _SiteTypeFilter _siteTypeFilter = _SiteTypeFilter.all;
  _SiteScopeFilter _siteScopeFilter = _SiteScopeFilter.current;
  final Set<String> _selectedSites = {};
  
  // 搜索相关
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  // 获取所有站点信息
  List<SiteIdentity> get _allSites => widget.siteManager.allSites;
  
  // 当前活跃站点
  SiteIdentity? get _currentSite => widget.siteManager.currentSiteIdentity;
  
  // 获取适配器
  BlogRepository? _getAdapter(String siteId) {
    return widget.siteManager.getAdapter(siteId);
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    // 默认选中已登录的站点
    _initializeSelectedSites();
    
    // 加载文章列表
    _loadPosts();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _initializeSelectedSites() {
    // 默认选中已登录（已配置有效密钥）的站点
    for (final site in _allSites) {
      if (site.isStatic) {
        // 静态站点检查是否有有效的token
        final repo = widget.siteManager.staticRepos
            .where((r) => r.id == site.id)
            .firstOrNull;
        if (repo?.token.isNotEmpty == true) {
          _selectedSites.add(site.id);
        }
      } else {
        // 动态站点检查配置是否有效
        final config = widget.siteManager.dynamicSites
            .where((c) => c.id == site.id)
            .firstOrNull;
        if (config?.isValid == true) {
          _selectedSites.add(site.id);
        }
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  List<BlogRepository> _getFilteredAdapters() {
    List<BlogRepository> adapters = [];
    
    // 根据站点范围筛选
    switch (_siteScopeFilter) {
      case _SiteScopeFilter.current:
        if (_currentSite != null) {
          final adapter = _getAdapter(_currentSite!.id);
          if (adapter != null) adapters.add(adapter);
        }
        break;
        
      case _SiteScopeFilter.all:
        for (final site in _allSites) {
          final adapter = _getAdapter(site.id);
          if (adapter != null) adapters.add(adapter);
        }
        break;
        
      case _SiteScopeFilter.selected:
        for (final siteId in _selectedSites) {
          final adapter = _getAdapter(siteId);
          if (adapter != null) adapters.add(adapter);
        }
        break;
    }
    
    // 根据站点类型筛选
    if (_siteTypeFilter != _SiteTypeFilter.all) {
      adapters = adapters.where((adapter) {
        final site = _allSites.where((s) => s.id == adapter.config.id).firstOrNull;
        if (site == null) return false;
        
        return switch (_siteTypeFilter) {
          _SiteTypeFilter.static => site.isStatic,
          _SiteTypeFilter.dynamic => site.isDynamic,
          _SiteTypeFilter.all => true,
        };
      }).toList();
    }
    
    return adapters;
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

    final adapters = _getFilteredAdapters();
    if (adapters.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _posts = [];
          _error = '请选择至少一个站点';
        });
      }
      return;
    }

    try {
      if (adapters.length > 1 && _siteScopeFilter != _SiteScopeFilter.current) {
        // ── 多站点聚合模式 ──
        final results = await Future.wait(adapters.map((a) async {
          try {
            return await a.getPosts(page: 1, perPage: 30);
          } catch (e) {
            debugPrint('UnifiedRemotePosts: load site ${a.config.name} failed: $e');
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
        
        // 如果有搜索查询，进行过滤
        List<BlogPost> filteredPosts = merged;
        if (_searchQuery.isNotEmpty) {
          filteredPosts = merged.where((post) {
            final searchLower = _searchQuery.toLowerCase();
            return post.title.toLowerCase().contains(searchLower) ||
                   post.contentMd.toLowerCase().contains(searchLower);
          }).toList();
        }
        
        filteredPosts.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
        
        if (mounted) {
          setState(() {
            _posts = filteredPosts;
            _hasMore = false;
            _loading = false;
            _loadingMore = false;
            _error = null;
          });
        }
      } else {
        // ── 单站点分页模式 ──
        if (adapters.isEmpty) return;
        
        final adapter = adapters.first;
        final posts = await adapter.getPosts(page: _page, perPage: 20);
        
        // 如果有搜索查询，进行过滤
        List<BlogPost> filteredPosts = posts;
        if (_searchQuery.isNotEmpty) {
          filteredPosts = posts.where((post) {
            final searchLower = _searchQuery.toLowerCase();
            return post.title.toLowerCase().contains(searchLower) ||
                   post.contentMd.toLowerCase().contains(searchLower);
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
    
    final siteLabel = _multiSite ? '（${_getSiteName(post.siteId)}）' : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除文章「${post.title}」$siteLabel 吗？\n此操作不可撤销。'),
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

  String _getSiteName(String? siteId) {
    for (final site in _allSites) {
      if (site.id == siteId) return site.name;
    }
    return siteId ?? '';
  }

  bool get _multiSite => _allSites.length > 1;

  String _getHeaderTitle() {
    if (!_multiSite && _currentSite != null) {
      return '${_currentSite!.type == SiteType.staticBlog ? '静态博客' : '动态CMS'} · ${_currentSite!.name}';
    }
    
    final typeFilter = switch (_siteTypeFilter) {
      _SiteTypeFilter.all => '所有类型',
      _SiteTypeFilter.static => '静态博客',
      _SiteTypeFilter.dynamic => '动态CMS',
    };
    
    final scopeFilter = switch (_siteScopeFilter) {
      _SiteScopeFilter.current => '当前站点',
      _SiteScopeFilter.all => '全部站点',
      _SiteScopeFilter.selected => '自选站点',
    };
    
    return '$typeFilter · $scopeFilter';
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getHeaderTitle(),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${_posts.length} 篇文章',
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

        // ── 筛选器区域 ──
        if (_multiSite) ...[
          // 站点类型筛选
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: SegmentedButton<_SiteTypeFilter>(
              segments: const [
                ButtonSegment(
                  value: _SiteTypeFilter.all,
                  label: Text('所有类型'),
                  icon: Icon(Icons.all_inclusive, size: 16),
                ),
                ButtonSegment(
                  value: _SiteTypeFilter.static,
                  label: Text('静态博客'),
                  icon: Icon(Icons.code, size: 16),
                ),
                ButtonSegment(
                  value: _SiteTypeFilter.dynamic,
                  label: Text('动态CMS'),
                  icon: Icon(Icons.web, size: 16),
                ),
              ],
              selected: {_siteTypeFilter},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (v) => setState(() {
                _siteTypeFilter = v.first;
                _loadPosts(refresh: true);
              }),
            ),
          ),
          const Divider(height: 1),

          // 站点范围筛选
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: SegmentedButton<_SiteScopeFilter>(
              segments: const [
                ButtonSegment(
                  value: _SiteScopeFilter.current,
                  label: Text('当前站点'),
                  icon: Icon(Icons.trip_origin, size: 16),
                ),
                ButtonSegment(
                  value: _SiteScopeFilter.all,
                  label: Text('全部站点'),
                  icon: Icon(Icons.dns, size: 16),
                ),
                ButtonSegment(
                  value: _SiteScopeFilter.selected,
                  label: Text('自选站点'),
                  icon: Icon(Icons.checklist, size: 16),
                ),
              ],
              selected: {_siteScopeFilter},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (v) => setState(() {
                _siteScopeFilter = v.first;
                _loadPosts(refresh: true);
              }),
            ),
          ),
          const Divider(height: 1),

          // 自选站点：站点勾选列表
          if (_siteScopeFilter == _SiteScopeFilter.selected) ...[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _allSites.map((site) {
                  final checked = _selectedSites.contains(site.id);
                  return FilterChip(
                    label: Text(
                      site.name,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: checked,
                    visualDensity: VisualDensity.compact,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedSites.add(site.id);
                        } else {
                          _selectedSites.remove(site.id);
                        }
                      });
                      _loadPosts(refresh: true);
                    },
                  );
                }).toList(),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              color: Colors.white,
              child: Text(
                '仅展示已勾选站点的文章；默认勾选已登录（已配置密钥）的站点。',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
            const Divider(height: 1),
          ],
        ],

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
                          '请检查站点配置或调整筛选条件',
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
                                        // 站点类型标签
                                        if (_multiSite && post.siteId != null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _getSiteType(post.siteId!) == SiteType.staticBlog
                                                  ? const Color(0xFF059669).withOpacity(0.1)
                                                  : const Color(0xFF0EA5E9).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _getSiteType(post.siteId!) == SiteType.staticBlog
                                                  ? '静态'
                                                  : 'CMS',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: _getSiteType(post.siteId!) == SiteType.staticBlog
                                                    ? const Color(0xFF059669)
                                                    : const Color(0xFF0E7490),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          // 站点名称标签
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF6B7280).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _getSiteName(post.siteId),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF374151),
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

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  SiteType? _getSiteType(String siteId) {
    for (final site in _allSites) {
      if (site.id == siteId) return site.type;
    }
    return null;
  }
}