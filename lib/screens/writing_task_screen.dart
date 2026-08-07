import 'package:flutter/material.dart';

import '../models/writing_task.dart';
import '../services/storage_service.dart';
import '../services/writing_task_manager.dart';

/// 写作任务管理：选题 → 提纲 → 草稿 → 发布 状态机
class WritingTaskScreen extends StatefulWidget {
  const WritingTaskScreen({super.key});

  @override
  State<WritingTaskScreen> createState() => _WritingTaskScreenState();
}

class _WritingTaskScreenState extends State<WritingTaskScreen> {
  final _storage = StorageService();
  WritingTaskManager? _manager;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final root = await _storage.root;
    final manager = WritingTaskManager(root);
    await manager.load();
    if (!mounted) return;
    setState(() {
      _manager = manager;
      _loading = false;
    });
  }

  void _refresh() => setState(() {});

  Future<void> _create() async {
    final titleCtrl = TextEditingController();
    final topicCtrl = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建写作任务'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '任务标题'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: topicCtrl,
                decoration: const InputDecoration(labelText: '选题说明'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final title = titleCtrl.text.trim();
              if (title.isEmpty) return;
              await _manager!.create(
                title: title,
                topic: topicCtrl.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (created == true) _refresh();
  }

  void _openDetail(WritingTask task) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TaskDetailScreen(
          manager: _manager!,
          task: task,
        ),
      ),
    ).then((_) => _refresh());
  }

  Future<void> _delete(WritingTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('删除「${task.title}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _manager!.delete(task.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('写作任务'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建任务',
            onPressed: _loading ? null : _create,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _manager!.tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.task_alt, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('暂无写作任务',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('创建任务，跟踪从选题到发布的写作流程',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: _manager!.tasks.map((task) {
                    final statusColor = _statusColor(task.status, cs);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _openDetail(task),
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.12),
                          child: Icon(_statusIcon(task.status), color: statusColor, size: 20),
                        ),
                        title: Text(task.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (task.topic.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(task.topic,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            const SizedBox(height: 4),
                            _statusBar(task.status, cs),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _delete(task),
                        ),
                      ),
                    );
                  }).toList(),
                ),
    );
  }

  /// 状态进度条（选题→提纲→草稿→发布）
  Widget _statusBar(WritingTaskStatus status, ColorScheme cs) {
    const stages = [
      WritingTaskStatus.topic,
      WritingTaskStatus.outline,
      WritingTaskStatus.writing,
      WritingTaskStatus.published,
    ];
    final current = stages.indexOf(status);
    return Row(
      children: stages.asMap().entries.map((e) {
        final idx = e.key;
        final done = idx <= current;
        final color = done ? cs.primary : cs.outlineVariant;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 3,
                  color: color.withOpacity(0.5),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                done ? Icons.check_circle : Icons.circle_outlined,
                size: 10,
                color: color,
              ),
              const SizedBox(width: 4),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _statusColor(WritingTaskStatus s, ColorScheme cs) => switch (s) {
        WritingTaskStatus.topic => Colors.blue,
        WritingTaskStatus.outline => Colors.orange,
        WritingTaskStatus.writing => Colors.teal,
        WritingTaskStatus.published => Colors.green,
      };

  IconData _statusIcon(WritingTaskStatus s) => switch (s) {
        WritingTaskStatus.topic => Icons.lightbulb_outline,
        WritingTaskStatus.outline => Icons.list_alt,
        WritingTaskStatus.writing => Icons.edit_note,
        WritingTaskStatus.published => Icons.published_with_changes,
      };
}

/// 任务详情页：编辑各阶段内容 + 推进状态
class _TaskDetailScreen extends StatefulWidget {
  final WritingTaskManager manager;
  final WritingTask task;

  const _TaskDetailScreen({required this.manager, required this.task});

  @override
  State<_TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<_TaskDetailScreen> {
  late WritingTask _task;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
  }

  Future<void> _advance() async {
    final next = _task.status.next;
    if (next == null) return;
    final updated = await widget.manager.advance(_task.id);
    if (updated != null) {
      setState(() => _task = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已推进至「${updated.status.label}」阶段')),
      );
    }
  }

  void _editField(String title, String initial, {int maxLines = 6}) async {
    final ctrl = TextEditingController(text: initial);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final updated = _task.copyWith(topic: ctrl.text.trim());
      await widget.manager.saveTask(updated);
      setState(() => _task = updated);
    }
  }

  Widget _section(String label, String content, {int maxLines = 3}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.article_outlined, size: 20),
        title: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            content.isEmpty ? '（空）' : content,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: content.isEmpty ? Colors.grey : null,
            ),
          ),
        ),
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: () => _editField(label, content),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final next = _task.status.next;

    return Scaffold(
      appBar: AppBar(
        title: Text(_task.title),
        actions: [
          if (next != null)
            TextButton.icon(
              onPressed: _advance,
              icon: const Icon(Icons.arrow_forward),
              label: Text('推进到${next.label}'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.flag, color: cs.primary, size: 18),
                const SizedBox(width: 8),
                Text('当前阶段：${_task.status.label}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _section('选题', _task.topic),
          _section('提纲', _task.outline),
          _section('草稿', _task.draft),
          if (_task.articleId.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.link, size: 20),
              title: const Text('关联文章'),
              subtitle: Text(_task.articleId),
            ),
        ],
      ),
    );
  }
}
