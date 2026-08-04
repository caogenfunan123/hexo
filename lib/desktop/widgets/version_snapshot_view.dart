/// 版本快照回退 UI 组件
/// 展示文章历史快照列表，支持预览、对比、恢复
/// 对标：Yank Note 版本历史面板
library;

import 'package:flutter/material.dart';
import '../../services/version_snapshot_service.dart';
import '../../services/conflict_diff_service.dart';

/// 版本快照回退组件
class VersionSnapshotView extends StatefulWidget {
  final String articleId;
  final String articleTitle;
  final String currentContent;
  final VersionSnapshotService snapshotService;
  final Function(String content)? onRestore;
  final Function(String snapshotId)? onDelete;

  const VersionSnapshotView({
    super.key,
    required this.articleId,
    required this.articleTitle,
    required this.currentContent,
    required this.snapshotService,
    this.onRestore,
    this.onDelete,
  });

  @override
  State<VersionSnapshotView> createState() => _VersionSnapshotViewState();
}

class _VersionSnapshotViewState extends State<VersionSnapshotView> {
  List<VersionSnapshot>? _snapshots;
  bool _loading = true;
  String? _selectedSnapshotId;
  String? _previewContent;
  bool _showDiff = false;

  @override
  void initState() {
    super.initState();
    _loadSnapshots();
  }

  Future<void> _loadSnapshots() async {
    setState(() => _loading = true);
    try {
      _snapshots = await widget.snapshotService.getSnapshots(widget.articleId);
      _snapshots?.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      _snapshots = [];
    }
    setState(() => _loading = false);
  }

  Future<void> _previewSnapshot(String snapshotId) async {
    final content = await widget.snapshotService.getSnapshotContent(
      widget.articleId,
      snapshotId,
    );
    setState(() {
      _selectedSnapshotId = snapshotId;
      _previewContent = content;
      _showDiff = false;
    });
  }

  Future<void> _restoreSnapshot(String snapshotId) async {
    final content = await widget.snapshotService.getSnapshotContent(
      widget.articleId,
      snapshotId,
    );
    if (content != null) {
      // 恢复前先保存当前版本快照
      await widget.snapshotService.createSnapshot(
        widget.articleId,
        '${widget.articleTitle} (恢复前备份)',
        widget.currentContent,
      );
      widget.onRestore?.call(content);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // 头部
        _buildHeader(isDark),
        // 主体
        Expanded(
          child: _showDiff && _previewContent != null
              ? _buildDiffView(isDark)
              : _buildSnapshotList(isDark),
        ),
      ],
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 18),
          const SizedBox(width: 8),
          Text(
            '版本快照',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          if (_snapshots != null)
            Text(
              ' (${_snapshots!.length})',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          const Spacer(),
          // 自动清理说明
          Text(
            '7天自动清理',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotList(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_snapshots == null || _snapshots!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('暂无快照', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _snapshots!.length,
      itemBuilder: (context, index) {
        final snapshot = _snapshots![index];
        final isSelected = snapshot.id == _selectedSnapshotId;
        final timeAgo = _formatTimeAgo(snapshot.createdAt);

        return Card(
          margin: const EdgeInsets.only(bottom: 4),
          color: isSelected
              ? (isDark ? const Color(0xFF2A3A5A) : const Color(0xFFE3F2FD))
              : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _previewSnapshot(snapshot.id),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_fix_high, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        _formatDateTime(snapshot.createdAt),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(),
                      Text(
                        timeAgo,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  if (snapshot.label != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      snapshot.label!,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${snapshot.contentLength} 字符',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                      ),
                      const Spacer(),
                      if (isSelected) ...[
                        _actionButton(
                          '对比',
                          Icons.compare,
                          () => setState(() => _showDiff = true),
                        ),
                        const SizedBox(width: 4),
                        _actionButton(
                          '恢复',
                          Icons.restore,
                          () => _restoreSnapshot(snapshot.id),
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
    );
  }

  Widget _buildDiffView(bool isDark) {
    final diff = ConflictDiffService.computeDiff(
      widget.currentContent,
      _previewContent ?? '',
    );
    final blocks = ConflictDiffService.groupIntoBlocks(diff);

    return Column(
      children: [
        // 顶部工具栏
        Container(
          padding: const EdgeInsets.all(8),
          color: isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _showDiff = false),
                icon: const Icon(Icons.arrow_back, size: 14),
                label: const Text('返回列表', style: TextStyle(fontSize: 11)),
              ),
              const Spacer(),
              Text(
                '当前版本 vs 快照版本',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        // Diff 内容
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: blocks.length,
            itemBuilder: (context, blockIndex) {
              final block = blocks[blockIndex];
              return _buildDiffBlock(block, isDark);
            },
          ),
        ),
        // 底部操作
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3),
            border: Border(
              top: BorderSide(
                color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _showDiff = false),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _restoreSnapshot(_selectedSnapshotId!),
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('恢复此版本'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDiffBlock(DiffBlock block, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 块位置标记
          if (!block.isInsertion && !block.isDeletion)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              color: isDark ? const Color(0xFF2A2A1A) : const Color(0xFFFFF8E1),
              child: Text(
                '行 ${block.startLineOld} → ${block.startLineNew}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ),
          // 变更行
          ...block.lines.map((line) => _buildDiffLine(line, isDark)),
        ],
      ),
    );
  }

  Widget _buildDiffLine(DiffLine line, bool isDark) {
    Color bg = Colors.transparent;
    Color? border;
    String prefix = '  ';

    switch (line.operation) {
      case DiffOperation.insert:
        bg = isDark ? const Color(0xFF1A3A2A) : const Color(0xFFE8F5E9);
        border = const Color(0xFF4CAF50);
        prefix = '+ ';
        break;
      case DiffOperation.delete:
        bg = isDark ? const Color(0xFF3A1A1A) : const Color(0xFFFFEBEE);
        border = const Color(0xFFEF5350);
        prefix = '- ';
        break;
      case DiffOperation.equal:
        prefix = '  ';
        break;
      default:
        break;
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        children: [
          if (border != null)
            Container(width: 3, color: border, margin: const EdgeInsets.only(right: 4)),
          Text(
            '$prefix${line.content}',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: isDark ? Colors.white : Colors.black87,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12),
            const SizedBox(width: 2),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${diff.inDays ~/ 7} 周前';
  }
}