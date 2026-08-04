/// 移动端快照管理屏幕
///
/// 参考 Yank Note 快照生命周期设计：
/// - 时间线列表展示所有快照
/// - 点击预览快照内容
/// - 左右滑动：恢复此版本 / 删除快照
/// - 支持创建带标签的手动快照
library;

import 'package:flutter/material.dart';
import '../services/version_snapshot_service.dart';
import '../services/conflict_diff_service.dart';

/// 移动端快照管理屏幕
class MobileSnapshotScreen extends StatefulWidget {
  final String articleId;
  final String articleTitle;
  final String currentContent;
  final VersionSnapshotService snapshotService;
  final void Function(String content)? onRestore;

  const MobileSnapshotScreen({
    super.key,
    required this.articleId,
    required this.articleTitle,
    required this.currentContent,
    required this.snapshotService,
    this.onRestore,
  });

  @override
  State<MobileSnapshotScreen> createState() => _MobileSnapshotScreenState();
}

class _MobileSnapshotScreenState extends State<MobileSnapshotScreen> {
  List<VersionSnapshot>? _snapshots;
  bool _loading = true;
  String? _selectedSnapshotId;
  String? _previewContent;
  bool _showDiff = false;
  final TextEditingController _labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSnapshots();
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _loadSnapshots() async {
    setState(() => _loading = true);
    try {
      _snapshots = await widget.snapshotService.getSnapshots(widget.articleId);
      _snapshots?.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      _snapshots = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _previewSnapshot(String snapshotId) async {
    final content = await widget.snapshotService.getSnapshotContent(
      widget.articleId,
      snapshotId,
    );
    if (mounted) {
      setState(() {
        _selectedSnapshotId = snapshotId;
        _previewContent = content;
        _showDiff = false;
      });
    }
  }

  Future<void> _restoreSnapshot(String snapshotId) async {
    final content = await widget.snapshotService.getSnapshotContent(
      widget.articleId,
      snapshotId,
    );
    if (content != null && mounted) {
      // 恢复前先保存当前版本快照
      await widget.snapshotService.createSnapshot(
        widget.articleId,
        '${widget.articleTitle} (恢复前备份)',
        widget.currentContent,
      );
      widget.onRestore?.call(content);
      Navigator.pop(context);
    }
  }

  Future<void> _deleteSnapshot(String snapshotId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除快照'),
        content: const Text('确定要删除此快照吗？此操作不可撤销。'),
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
    if (confirmed == true) {
      await widget.snapshotService.deleteSnapshot(widget.articleId, snapshotId);
      if (mounted) {
        if (_selectedSnapshotId == snapshotId) {
          setState(() {
            _selectedSnapshotId = null;
            _previewContent = null;
            _showDiff = false;
          });
        }
        _loadSnapshots();
      }
    }
  }

  Future<void> _createLabeledSnapshot() async {
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) {
        _labelController.clear();
        return AlertDialog(
          title: const Text('创建快照'),
          content: TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              hintText: '输入快照标签（可选）',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _labelController.text),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );

    if (label != null && mounted) {
      final snapshot = await widget.snapshotService.createSnapshot(
        widget.articleId,
        label.isNotEmpty ? '${widget.articleTitle} ($label)' : widget.articleTitle,
        widget.currentContent,
      );
      if (snapshot != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('快照已创建${label.isNotEmpty ? ": $label" : ""}')),
        );
        _loadSnapshots();
      }
    }
  }

  void _toggleDiffView() {
    setState(() => _showDiff = !_showDiff);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('版本快照'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_selectedSnapshotId != null && _previewContent != null)
            IconButton(
              icon: Icon(_showDiff ? Icons.list : Icons.compare),
              tooltip: _showDiff ? '返回列表' : '对比差异',
              onPressed: _toggleDiffView,
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '创建快照',
            onPressed: _createLabeledSnapshot,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _showDiff && _previewContent != null
              ? _buildDiffView(isDark)
              : _buildContent(isDark),
    );
  }

  Widget _buildContent(bool isDark) {
    if (_snapshots == null || _snapshots!.isEmpty) {
      return _buildEmptyView(isDark);
    }

    if (_selectedSnapshotId != null && _previewContent != null) {
      return _buildPreviewView(isDark);
    }

    return _buildTimelineView(isDark);
  }

  // ============================================================
  // 时间线列表
  // ============================================================

  Widget _buildTimelineView(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadSnapshots,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        itemCount: _snapshots!.length + 1,
        itemBuilder: (context, index) {
          if (index == _snapshots!.length) {
            return _buildCurrentVersionItem(isDark);
          }
          return _buildSnapshotTimelineItem(_snapshots![index], isDark);
        },
      ),
    );
  }

  Widget _buildSnapshotTimelineItem(VersionSnapshot snapshot, bool isDark) {
    final isSelected = snapshot.id == _selectedSnapshotId;
    final timeAgo = _formatTimeAgo(snapshot.createdAt);

    return Dismissible(
      key: Key(snapshot.id),
      background: Container(
        color: Colors.green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Row(
          children: [
            Icon(Icons.restore, color: Colors.white),
            SizedBox(width: 8),
            Text('恢复此版本', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('删除', style: TextStyle(color: Colors.white)),
            SizedBox(width: 8),
            Icon(Icons.delete, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // 右滑：恢复
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('恢复快照'),
              content: const Text('确定要恢复到此版本吗？当前内容将被保存为快照。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('恢复'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            _restoreSnapshot(snapshot.id);
          }
          return false; // 不执行 Dismissible 动画，手动处理
        } else {
          // 左滑：删除
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('删除快照'),
              content: const Text('确定要删除此快照吗？'),
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
          if (confirmed == true) {
            _deleteSnapshot(snapshot.id);
          }
          return false;
        }
      },
      child: _buildTimelineCard(
        isDark: isDark,
        isSelected: isSelected,
        dateTime: snapshot.createdAt,
        timeAgo: timeAgo,
        label: snapshot.label,
        contentLength: snapshot.contentLength,
        onTap: () => _previewSnapshot(snapshot.id),
      ),
    );
  }

  Widget _buildCurrentVersionItem(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '当前版本',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${widget.currentContent.length} 字符',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard({
    required bool isDark,
    required bool isSelected,
    required DateTime dateTime,
    required String timeAgo,
    String? label,
    required int contentLength,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间线指示器
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade400,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                    width: 2,
                  ),
                ),
              ),
              Container(
                width: 2,
                height: 80,
                color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // 卡片
          Expanded(
            child: Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: isSelected
                  ? (isDark ? const Color(0xFF2A3A5A) : const Color(0xFFE3F2FD))
                  : null,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_fix_high, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            _formatDateTime(dateTime),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const Spacer(),
                          Text(
                            timeAgo,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      if (label != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '$contentLength 字符',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 预览视图
  // ============================================================

  Widget _buildPreviewView(bool isDark) {
    return Column(
      children: [
        // 预览头部
        Container(
          padding: const EdgeInsets.all(12),
          color: isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3),
          child: Row(
            children: [
              const Icon(Icons.preview, size: 16),
              const SizedBox(width: 8),
              const Text('快照预览', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _selectedSnapshotId = null),
                icon: const Icon(Icons.arrow_back, size: 14),
                label: const Text('返回列表', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        // 预览内容
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              _previewContent ?? '',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: isDark ? Colors.white : Colors.black87,
                height: 1.6,
              ),
            ),
          ),
        ),
        // 底部操作
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteSnapshot(_selectedSnapshotId!),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('删除'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _restoreSnapshot(_selectedSnapshotId!),
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('恢复此版本'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // Diff 对比视图
  // ============================================================

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
                label: const Text('返回预览', style: TextStyle(fontSize: 11)),
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
        SafeArea(
          child: Container(
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
          if (!block.isInsertion && !block.isDeletion)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              color: isDark ? const Color(0xFF2A2A1A) : const Color(0xFFFFF8E1),
              child: Text(
                '行 ${block.startLineOld} -> ${block.startLineNew}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ),
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
          Expanded(
            child: Text(
              '$prefix${line.content}',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: isDark ? Colors.white : Colors.black87,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 空状态
  // ============================================================

  Widget _buildEmptyView(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '暂无快照',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '编辑文章时会自动创建快照',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _createLabeledSnapshot,
            icon: const Icon(Icons.add),
            label: const Text('创建手动快照'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 工具方法
  // ============================================================

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