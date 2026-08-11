import 'package:flutter/material.dart';

import '../core/repository/blog_repository.dart';
import '../core/site_manager.dart';
import '../models/blog_post.dart';
import '../models/repo_config.dart';
import '../services/log_service.dart';
import '../l10n/app_localizations.dart';

/// 远程文章浏览面板
///
/// 从 CMS 站点和静态博客站点拉取文章列表，支持：
/// - 分页浏览（单站点）、下拉刷新
/// - 点击加载到编辑器（HTML→Markdown 转换已在适配器中完成）
/// - 删除远程文章
///
/// 多站点模式（[allAdapters] 非空且多于一个站点）下支持：
/// - 全部站点：聚合查看所有 CMS 站点和静态博客站点的文章
/// - 自选站点：勾选已登录（已配置密钥）的站点，仅查看这些站点的文章
class RemotePostsScreen extends StatefulWidget {
  /// 当前（活跃）CMS 站点适配器
  final BlogRepository adapter;

  /// 全部 CMS 站点适配器（用于全部站点 / 自选站点模式）
  final List<BlogRepository>? allAdapters;

  /// 站点管理器（用于获取站点信息）
  final SiteManager? siteManager;

  final LogService logService;
  final void Function(BlogPost post) onOpenInEditor;
  final Future<void> Function(BlogPost post) onDeletePost;

  const RemotePostsScreen({
    super.key,
    required this.adapter,
    this.allAdapters,
    this.siteManager,
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

/// 站点类型范围
enum _SiteTypeScope {
  /// 所有站点
  all,
  /// 静态博客站点
  static,
  /// 动态CMS站点
  dynamic,
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
  _SiteTypeScope _siteTypeScope = _SiteTypeScope.all;
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

  /// 根据站点类型筛选适配器
  List<BlogRepository> get _filteredAdapters {
    if (!_multiSite || _siteTypeScope == _SiteTypeScope.all) {
      return _activeAdapters;
    }
    
    return _activeAdapters.where((adapter) {
      final siteType = _getSiteType(adapter.config.id);
      return switch (_siteTypeScope) {
        _SiteTypeScope.static => siteType == SiteType.staticBlog,
        _SiteTypeScope.dynamic => siteType == SiteType.dynamicCms,
        _SiteTypeScope.all => true,
      };
    }).toList();
  }

  /// 获取站点类型（静态博客或动态CMS）
  SiteType? _getSiteType(String siteId) {
    if (widget.siteManager != null) {
      final identity = widget.siteManager!.getSiteIdentity(siteId);
      return identity?.type;
    }
    return null;
  }

  /// 判断是否为静态博客站点
  bool _isStaticSite(String siteId) {
    return _getSiteType(siteId) == SiteType.staticBlog;
  }

  /// 判断是否为动态CMS站点
  bool _isDynamicSite(String siteId) {
    return _getSiteType(siteId) == SiteType.dynamicCms;
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

  void _changeSiteTypeScope(_SiteTypeScope scope) {
    if (_siteTypeScope == scope) return;
    setState(() => _siteTypeScope = scope);
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

    final adapters = _filteredAdapters;
    if (adapters.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _posts = [];
          _error = AppLocalizations.ofContext(context)
              .translate('select_at_least_one_site');
        });
      }
      return;
    }

    try {
      if (_multiSite && _scope != _RemoteScope.current) {
        // ── 多站点聚合模式：逐站点翻页拉取全部文章 ──
        final results = await Future.wait(adapters.map((a) async {
          try {
            return await _fetchAllSitePosts(a);
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
            final key = '${p.siteId ?? siteId}:${p.id ?? p.slug ?? p.title}';
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

  /// 逐页拉取单站点的全部文章（静态站点由适配器一次返回全部，动态 CMS 翻页拉完）
  Future<List<BlogPost>> _fetchAllSitePosts(BlogRepository adapter) async {
    const perPage = 100;
    final all = <BlogPost>[];
    var page = 1;
    while (true) {
      final batch = await adapter.getPosts(page: page, perPage: perPage);
      if (batch.isEmpty) break;
      all.addAll(batch);
      if (batch.length < perPage) break;
      page++;
    }
    return all;
  }

  Future<void> _deletePost(BlogPost post) async {
    final l10n = AppLocalizations.ofContext(context);
    // 静态站点文章无数字 id（基于文件路径删除），此处不做 id 拦截
    if (post.title.isEmpty && post.id == null) return;
    final siteLabel = _multiSite ? '（${_siteName(post.siteId)}）' : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('confirm_delete_title')),
        content: Text(l10n
            .translate('confirm_delete_remote')
            .replaceAll('{title}', post.title)
            .replaceAll('{site}', siteLabel)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.onDeletePost(post);
      setState(() => _removePostFromList(post));
      widget.logService.add(l10n.translate('log_delete_remote'), '标题: ${post.title}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(l10n.translate('deleted_prefix').replaceAll('{title}', post.title))),
        );
      }
    } catch (e) {
      widget.logService.add(l10n.translate('log_delete_remote_failed'), '$e', success: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  l10n.translate('delete_failed').replaceAll('{error}', '$e'))),
        );
      }
    }
  }

  /// 从列表移除被删除的文章（静态文章 id 为 null，需按 siteId+slug 匹配）
  void _removePostFromList(BlogPost post) {
    _posts.removeWhere((p) {
      if (post.id != null) {
        return p.id == post.id && p.siteId == post.siteId;
      }
      return p.siteId == post.siteId &&
          (p.slug == post.slug ||
              (p.slug == null && p.title == post.title && p.link == post.link));
    });
  }

  String _formatDate(DateTime dt) {
    final l10n = AppLocalizations.ofContext(context);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return l10n.translate('just_now');
    if (diff.inHours < 1) return l10n.translate('minutes_ago').replaceAll('{count}', '${diff.inMinutes}');
    if (diff.inDays < 1) return l10n.translate('hours_ago').replaceAll('{count}', '${diff.inHours}');
    if (diff.inDays < 7) return l10n.translate('days_ago').replaceAll('{count}', '${diff.inDays}');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String get _headerTitle {
    final l10n = AppLocalizations.ofContext(context);
    if (!_multiSite) {
      final siteType = widget.siteManager?.currentSiteIdentity?.type;
      final siteName = widget.adapter.config.name;
      if (siteType == SiteType.staticBlog) {
        return l10n.translate('static_blog_prefix').replaceAll('{name}', siteName);
      } else {
        return l10n
            .translate('cms_remote_posts')
            .replaceAll('{type}', widget.adapter.config.type.name);
      }
    }
    return switch (_scope) {
      _RemoteScope.current => l10n
          .translate('current_site_name')
          .replaceAll('{name}', widget.adapter.config.name),
      _RemoteScope.all => l10n.translate('all_site_posts'),
      _RemoteScope.selected => l10n.translate('selected_site_posts'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.ofContext(context);
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
                l10n.translate('posts_count').replaceAll('{count}', '${_posts.length}'),
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _loading ? null : () => _loadPosts(refresh: true),
                tooltip: l10n.translate('refresh'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── 站点类型筛选器 ──
        if (_multiSite) ...[
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: SegmentedButton<_SiteTypeScope>(
              segments: [
                ButtonSegment(
                  value: _SiteTypeScope.all,
                  label: Text(l10n.translate('all_sites')),
                  icon: const Icon(Icons.all_inclusive, size: 16),
                ),
                ButtonSegment(
                  value: _SiteTypeScope.static,
                  label: Text(l10n.translate('static_blog')),
                  icon: const Icon(Icons.code, size: 16),
                ),
                ButtonSegment(
                  value: _SiteTypeScope.dynamic,
                  label: Text(l10n.translate('dynamic_cms')),
                  icon: const Icon(Icons.web, size: 16),
                ),
              ],
              selected: {_siteTypeScope},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (v) => _changeSiteTypeScope(v.first),
            ),
          ),
          const Divider(height: 1),
        ],

        // ── 多站点范围选择 ──
        if (_multiSite) ...[
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: SegmentedButton<_RemoteScope>(
              segments: [
                ButtonSegment(
                  value: _RemoteScope.current,
                  label: Text(l10n.translate('current_site')),
                  icon: const Icon(Icons.trip_origin, size: 16),
                ),
                ButtonSegment(
                  value: _RemoteScope.all,
                  label: Text(l10n.translate('all_sites')),
                  icon: const Icon(Icons.dns, size: 16),
                ),
                ButtonSegment(
                  value: _RemoteScope.selected,
                  label: Text(l10n.translate('selected_sites')),
                  icon: const Icon(Icons.checklist, size: 16),
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
                  final siteType = _getSiteType(a.config.id);
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
                l10n.translate('select_site_hint'),
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
                  child: Text(l10n.translate('retry')),
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
                          l10n.translate('no_remote_posts'),
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.translate('tap_refresh'),
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
                                            post.title.isEmpty ? l10n.translate('no_title') : post.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // 站点类型标签（多站点模式）
                                        if (_multiSite && post.siteId != null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _isStaticSite(post.siteId!)
                                                  ? const Color(0xFF10B981).withOpacity(0.1)
                                                  : const Color(0xFF0EA5E9).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _isStaticSite(post.siteId!)
                                                  ? l10n.translate('site_static')
                                                  : l10n.translate('site_cms'),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: _isStaticSite(post.siteId!)
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
                                              _siteName(post.siteId),
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
                                            post.isPublished ? l10n.translate('published') : l10n.translate('draft'),
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
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text(l10n.translate('delete_remote_post')),
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
