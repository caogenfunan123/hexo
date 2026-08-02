import 'package:flutter/material.dart';

import '../core/repository/blog_repository.dart';
import '../models/article.dart';
import '../models/blog_post.dart';
import '../models/blog_site_config.dart';
import '../services/log_service.dart';
import '../services/sync_service.dart';

/// 双向同步页面
///
/// 展示本地文章与远程 CMS 文章的同步状态，支持：
/// - 推送本地文章到远程
/// - 拉取远程文章到本地草稿
/// - 冲突检测与提示
class SyncScreen extends StatefulWidget {
  final BlogRepository adapter;
  final BlogSiteConfig siteConfig;
  final SyncService syncService;
  final LogService logService;
  final List<Article> localArticles;
  final void Function(Article article) onOpenArticle;
  final void Function(BlogPost post) onOpenRemotePost;

  const SyncScreen({
    super.key,
    required this.adapter,
    required this.siteConfig,
    required this.syncService,
    required this.logService,
    required this.localArticles,
    required this.onOpenArticle,
    required this.onOpenRemotePost,
  });

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  List<SyncEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSync();
  }

  Future<void> _loadSync() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.syncService.compareSync(
        widget.siteConfig,
        widget.adapter,
        widget.localArticles,
      );
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _pushToRemote(SyncEntry entry) async {
    if (entry.localArticleId == null) return;
    final article = widget.localArticles.where((a) => a.id == entry.localArticleId).firstOrNull;
    if (article == null) return;

    setState(() => _loading = true);
    try {
      await widget.syncService.pushToRemote(
        widget.adapter,
        article,
        widget.siteConfig.id,
      );
      widget.logService.add('同步推送', '已推送「${article.title}」');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已推送: ${article.title}')),
        );
      }
      await _loadSync();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('推送失败: $e')),
        );
      }
    }
  }

  Future<void> _pullToLocal(SyncEntry entry) async {
    if (entry.remotePostId == null) return;

    setState(() => _loading = true);
    try {
      // 生成新文章 ID
      final localArticleId = DateTime.now().millisecondsSinceEpoch.toString();
      final post = await widget.syncService.pullFromRemote(
        widget.adapter,
        entry.remotePostId!,
        widget.siteConfig.id,
        localArticleId: localArticleId,
      );
      widget.onOpenRemotePost(post);
      if (mounted) {
        await _loadSync();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拉取失败: $e')),
        );
      }
    }
  }

  void _handleConflict(SyncEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Text('同步冲突'),
          ],
        ),
        content: Text('文章「${entry.title}」在本地和远程都有更新，请选择处理方式：'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(ctx);
              _pushToRemote(entry);
            },
            child: const Text('以本地为准（推送）'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pullToLocal(entry);
            },
            child: const Text('以远程为准（拉取）'),
          ),
        ],
      ),
    );
  }

  Color _statusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.localOnly:
        return Colors.blue;
      case SyncStatus.remoteOnly:
        return Colors.purple;
      case SyncStatus.localNewer:
        return Colors.orange;
      case SyncStatus.remoteNewer:
        return Colors.teal;
      case SyncStatus.conflict:
        return Colors.red;
      case SyncStatus.synced:
        return Colors.green;
    }
  }

  String _statusLabel(SyncStatus status) {
    switch (status) {
      case SyncStatus.localOnly:
        return '仅本地';
      case SyncStatus.remoteOnly:
        return '仅远程';
      case SyncStatus.localNewer:
        return '本地更新';
      case SyncStatus.remoteNewer:
        return '远程更新';
      case SyncStatus.conflict:
        return '冲突';
      case SyncStatus.synced:
        return '已同步';
    }
  }

  IconData _statusIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.localOnly:
        return Icons.phone_android;
      case SyncStatus.remoteOnly:
        return Icons.cloud;
      case SyncStatus.localNewer:
        return Icons.upload_file;
      case SyncStatus.remoteNewer:
        return Icons.download;
      case SyncStatus.conflict:
        return Icons.warning_amber;
      case SyncStatus.synced:
        return Icons.check_circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final synced = _entries.where((e) => e.status == SyncStatus.synced).length;
    final conflicts = _entries.where((e) => e.hasConflict).length;
    final needsPush = _entries.where((e) => e.needsPush).length;
    final needsPull = _entries.where((e) => e.needsPull).length;

    return Column(
      children: [
        // ── 统计概览 ──
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              _statChip('已同步', synced, Colors.green),
              const SizedBox(width: 8),
              _statChip('需推送', needsPush, Colors.blue),
              const SizedBox(width: 8),
              _statChip('需拉取', needsPull, Colors.purple),
              const SizedBox(width: 8),
              _statChip('冲突', conflicts, conflicts > 0 ? Colors.red : Colors.grey),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loading ? null : _loadSync,
                tooltip: '刷新',
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                TextButton(onPressed: _loadSync, child: const Text('重试')),
              ],
            ),
          ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
                  ? const Center(
                      child: Text('暂无同步数据', style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _entries.length,
                      itemBuilder: (_, i) {
                        final entry = _entries[i];
                        final color = _statusColor(entry.status);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: Colors.white,
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // 状态图标
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(_statusIcon(entry.status), color: color, size: 20),
                                ),
                                const SizedBox(width: 10),
                                // 标题和状态
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.title.isEmpty ? '（无标题）' : entry.title,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: color.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              _statusLabel(entry.status),
                                              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          if (entry.localModifiedAt != null) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              '本地: ${_formatTime(entry.localModifiedAt!)}',
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                            ),
                                          ],
                                          if (entry.remoteModifiedAt != null) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              '远程: ${_formatTime(entry.remoteModifiedAt!)}',
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // 操作按钮
                                if (entry.status != SyncStatus.synced)
                                  PopupMenuButton<String>(
                                    onSelected: (v) {
                                      switch (v) {
                                        case 'push':
                                          if (entry.hasConflict) {
                                            _handleConflict(entry);
                                          } else {
                                            _pushToRemote(entry);
                                          }
                                          break;
                                        case 'pull':
                                          _pullToLocal(entry);
                                          break;
                                      }
                                    },
                                    icon: const Icon(Icons.more_vert, size: 18),
                                    itemBuilder: (_) {
                                      final items = <PopupMenuEntry<String>>[];
                                      if (entry.needsPush || entry.hasConflict) {
                                        items.add(const PopupMenuItem(
                                          value: 'push',
                                          child: Row(
                                            children: [
                                              Icon(Icons.upload, size: 16),
                                              SizedBox(width: 8),
                                              Text('推送到远程'),
                                            ],
                                          ),
                                        ));
                                      }
                                      if (entry.needsPull || entry.hasConflict) {
                                        items.add(const PopupMenuItem(
                                          value: 'pull',
                                          child: Row(
                                            children: [
                                              Icon(Icons.download, size: 16),
                                              SizedBox(width: 8),
                                              Text('拉取到本地'),
                                            ],
                                          ),
                                        ));
                                      }
                                      return items;
                                    },
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}