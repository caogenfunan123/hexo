import 'package:flutter/material.dart';
import '../models/repo_config.dart';
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
  });

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  final Set<String> _selected = {};
  bool _selectMode = false;

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

  @override
  Widget build(BuildContext context) {
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
    return Column(
      children: [
        // 选择模式工具栏
        if (_selectMode)
          Container(
            color: const Color(0xFFEFF6FF),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                TextButton(
                  onPressed: _toggleSelectMode,
                  child: const Text('取消'),
                ),
                const Spacer(),
                Text('已选 ${_selected.length} 项',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _selectAll,
                  icon: const Icon(Icons.select_all, size: 18),
                  label: Text(
                      _selected.length == widget.posts.length ? '取消全选' : '全选'),
                ),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                  style: FilledButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  child: const Text('删除选中'),
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
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
          ),
        ),
        // 底部操作栏
        if (!_selectMode)
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
}