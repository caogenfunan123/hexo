import 'package:flutter/material.dart';
import '../services/recycle_bin_service.dart';
import 'dart:io';

class RecycleBinScreen extends StatefulWidget {
  final RecycleBinService recycleBinService;
  final Function(String restoredPath)? onRestored;

  const RecycleBinScreen({
    super.key,
    required this.recycleBinService,
    this.onRestored,
  });

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<RecycleBinEntry> _entries = [];
  final Set<String> _selectedIds = {};
  bool _loading = false;
  int _autoCleanDays = 30;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _loading = true);
    try {
      final entries = await widget.recycleBinService.loadEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) { debugPrint('RecycleBin: load failed: $e'); if (!mounted) return; setState(() => _loading = false); }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _entries.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_entries.map((e) => e.id));
      }
    });
  }

  Future<void> _restoreSelected() async {
    final idsToRestore = _selectedIds.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复'),
        content: Text('确定要恢复选中的 ${idsToRestore.length} 个文件吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('恢复')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      for (final id in idsToRestore) {
        final restoredPath = await widget.recycleBinService.restore(id);
        widget.onRestored?.call(restoredPath);
      }
      if (!mounted) return;
      setState(() {
        _selectedIds.clear();
        _loading = false;
      });
      _loadEntries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已恢复 ${idsToRestore.length} 个文件')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败: $e')),
      );
    }
  }

  Future<void> _permanentlyDeleteSelected() async {
    final idsToDelete = _selectedIds.toList();
    if (idsToDelete.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('永久删除'),
        content: Text('确定要永久删除选中的 ${idsToDelete.length} 个文件吗？\n此操作不可撤销！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await widget.recycleBinService.permanentlyDeleteBatch(idsToDelete);
      if (!mounted) return;
      setState(() {
        _selectedIds.clear();
        _loading = false;
      });
      _loadEntries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已永久删除 ${idsToDelete.length} 个文件')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e')),
      );
    }
  }

  Future<void> _emptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: Text('确定要清空回收站吗？\n所有 ${_entries.length} 个文件将被永久删除，此操作不可撤销！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空回收站'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final count = await widget.recycleBinService.emptyTrash();
      if (!mounted) return;
      setState(() {
        _selectedIds.clear();
        _loading = false;
      });
      _loadEntries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清空回收站，共删除 $count 个文件')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清空失败: $e')),
      );
    }
  }

  Future<void> _autoCleanNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自动清理'),
        content: Text('将永久删除所有超过 $_autoCleanDays 天的文件，确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('立即清理'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final count = await widget.recycleBinService.autoClean(_autoCleanDays);
      if (!mounted) return;
      setState(() => _loading = false);
      _loadEntries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('自动清理完成，共删除 $count 个过期文件')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('自动清理失败: $e')),
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedIds.isNotEmpty;
    final allSelected = _entries.isNotEmpty && _selectedIds.length == _entries.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_entries.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'empty':
                    _emptyTrash();
                  case 'auto_clean':
                    _autoCleanNow();
                  case 'settings':
                    _showAutoCleanSettings();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'empty', child: ListTile(
                  leading: Icon(Icons.delete_forever, color: Colors.red),
                  title: Text('清空回收站'),
                  contentPadding: EdgeInsets.zero,
                )),
                const PopupMenuItem(value: 'auto_clean', child: ListTile(
                  leading: Icon(Icons.auto_delete, color: Colors.orange),
                  title: Text('立即自动清理'),
                  contentPadding: EdgeInsets.zero,
                )),
                const PopupMenuItem(value: 'settings', child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('自动清理设置'),
                  contentPadding: EdgeInsets.zero,
                )),
              ],
            ),
        ],
      ),
      body: _loading && _entries.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmptyView()
              : _buildEntryList(hasSelection, allSelected),
      bottomNavigationBar: hasSelection
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text('已选 ${_selectedIds.length} 项'),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _restoreSelected,
                      icon: const Icon(Icons.restore),
                      label: const Text('恢复'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _permanentlyDeleteSelected,
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('永久删除'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      floatingActionButton: _entries.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _emptyTrash,
              backgroundColor: Colors.red,
              icon: const Icon(Icons.delete_forever),
              label: const Text('清空回收站'),
            )
          : null,
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('回收站为空', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text('删除的文章会出现在这里', style: TextStyle(color: Colors.grey.shade500)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _showAutoCleanSettings,
            icon: const Icon(Icons.settings),
            label: const Text('自动清理设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryList(bool hasSelection, bool allSelected) {
    return RefreshIndicator(
      onRefresh: _loadEntries,
      child: Column(
        children: [
          _buildSelectionBar(allSelected),
          Expanded(
            child: ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (ctx, i) => _buildEntryTile(_entries[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(bool allSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: (_) => _toggleSelectAll(),
          ),
          GestureDetector(
            onTap: _toggleSelectAll,
            child: Text(allSelected ? '取消全选' : '全选'),
          ),
          const Spacer(),
          Text('共 ${_entries.length} 项'),
        ],
      ),
    );
  }

  Widget _buildEntryTile(RecycleBinEntry entry) {
    final isSelected = _selectedIds.contains(entry.id);
    final article = entry.article;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onLongPress: () => _toggleSelection(entry.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSelection(entry.id),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title.isNotEmpty ? article.title : entry.fileName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.originalPath,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (article.tags.isNotEmpty)
                          Icon(Icons.local_offer, size: 14, color: Colors.grey.shade500),
                        if (article.tags.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              article.tags.join(', '),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (article.categories.isNotEmpty) ...[
                          if (article.tags.isNotEmpty) const SizedBox(width: 12),
                          Icon(Icons.folder, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              article.categories.join(', '),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatDate(entry.deletedAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(entry.fileSize),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAutoCleanSettings() {
    showDialog(
      context: context,
      builder: (ctx) {
        int days = _autoCleanDays;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('自动清理设置'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('设置回收站中文件的保留天数，超过该天数的文件将被自动永久删除。'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('保留天数: '),
                    Expanded(
                      child: Slider(
                        value: days.toDouble(),
                        min: 1,
                        max: 90,
                        divisions: 89,
                        label: '$days 天',
                        onChanged: (v) {
                          setDialogState(() => days = v.round());
                        },
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '$days 天',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  days == 1 ? '文件将在删除 1 天后自动清理' : '文件将在删除 $days 天后自动清理',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() => _autoCleanDays = days);
                  Navigator.pop(ctx);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    );
  }
}