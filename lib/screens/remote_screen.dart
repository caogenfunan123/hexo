import 'package:flutter/material.dart';
import '../models/repo_config.dart';
import '../models/blog_post.dart';
import '../services/github_service.dart';

class RemoteScreen extends StatefulWidget {
  final List<GitHubFileItem> posts;
  final RepoConfig? activeRepo;
  final RepoConfig? effectiveRepo;
  final GitHubService github;
  final VoidCallback onRefresh;
  final void Function(GitHubFileItem) onOpen;
  final void Function(GitHubFileItem) onDelete;
  final Future<void> Function(List<GitHubFileItem>) onBatchDelete;
  final void Function(String) onRollback;
  final List<BlogPost>? blogPosts; // 静态博客文章列表
  final void Function(BlogPost)? onBlogPostOpen; // 打开静态博客文章
  final Future<void> Function(BlogPost)? onBlogPostDelete; // 删除静态博客文章

  const RemoteScreen({
    super.key,
    required this.posts,
    required this.activeRepo,
    required this.effectiveRepo,
    required this.github,
    required this.onRefresh,
    required this.onOpen,
    required this.onDelete,
    required this.onBatchDelete,
    required this.onRollback,
    this.blogPosts,
    this.onBlogPostOpen,
    this.onBlogPostDelete,
  });

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  final Set<String> _selected = {};
  bool _selectMode = false;
  bool _showStaticPosts = false; // 是否显示静态博客文章

  void _toggleSelect(GitHubFileItem item) {
    setState(() {
      if (_selected.contains(item.path)) {
        _selected.remove(item.path);
        if (_selected.isEmpty) _selectMode = false;
      } else {
        _selected.add(item.path);
      }
    });
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selected.clear();
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == widget.posts.length) {
        _selected.clear();
        _selectMode = false;
      } else {
        _selected.addAll(widget.posts.map((e) => e.path));
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final items = widget.posts.where((e) => _selected.contains(e.path)).toList();
    await widget.onBatchDelete(items);
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
  }

  void _toggleStaticPosts() {
    setState(() {
      _showStaticPosts = !_showStaticPosts;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 检查是否有静态博客文章
    final hasStaticPosts = widget.blogPosts != null && widget.blogPosts!.isNotEmpty;
    
    return Column(
      children: [
        // 静态博客切换按钮
        if (hasStaticPosts)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.code, size: 18, color: Color(0xFF059669)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '静态博客文章 (${widget.blogPosts!.length} 篇)',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: _showStaticPosts,
                  onChanged: (value) => _toggleStaticPosts(),
                ),
              ],
            ),
          ),
        const Divider(height: 1),

        // 显示静态博客文章或远程文件
        if (_showStaticPosts && hasStaticPosts)
          Expanded(
            child: _buildStaticBlogPostsList(),
          )
        else
          Expanded(
            child: _buildRemoteFilesList(),
          ),

        // 底部操作栏
        if (!_selectMode && !_showStaticPosts)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _toggleSelectMode,
                  icon: const Icon(Icons.checklist, size: 18),
                  label: const Text('批量选择'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _buildRemoteFilesList() {
    if (widget.posts.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('暂无远程文章', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text(widget.activeRepo?.fullName ?? '',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新')),
        ]),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: widget.posts.length,
        itemBuilder: (_, i) {
          final p = widget.posts[i];
          final isSelected = _selected.contains(p.path);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: isSelected
                  ? BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2)
                  : BorderSide.none,
            ),
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.05)
                : Colors.white,
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _selectMode
                  ? () => _toggleSelect(p)
                  : () => widget.onOpen(p),
              onLongPress: () {
                if (!_selectMode) {
                  setState(() => _selectMode = true);
                  _toggleSelect(p);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  if (_selectMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(
                        isSelected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                        size: 22,
                      ),
                    ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.description_outlined,
                        size: 20, color: Color(0xFF0EA5E9)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(p.path,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (!_selectMode)
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') {
                          widget.onOpen(p);
                        } else if (v == 'delete') {
                          widget.onDelete(p);
                        } else if (v == 'rollback') {
                          widget.onRollback(p.path);
                        } else if (v == 'select') {
                          _toggleSelectMode();
                          _toggleSelect(p);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('编辑')),
                        PopupMenuItem(
                            value: 'rollback', child: Text('回滚历史')),
                        PopupMenuItem(value: 'select', child: Text('批量选择')),
                        PopupMenuItem(value: 'delete', child: Text('删除远程')),
                      ],
                    )
                  else
                    const Icon(Icons.chevron_right,
                        color: Color(0xFFCBD5E1)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStaticBlogPostsList() {
    if (widget.blogPosts!.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.article_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('暂无静态博客文章', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('请检查仓库配置', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ]),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: widget.blogPosts!.length,
        itemBuilder: (_, i) {
          final post = widget.blogPosts![i];
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
              onTap: () => widget.onBlogPostOpen?.call(post),
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
                            if (v == 'delete') {
                              widget.onBlogPostDelete?.call(post);
                            }
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
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
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
}