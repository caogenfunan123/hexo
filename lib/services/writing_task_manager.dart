/// 写作任务管理器：持久化 + CRUD + 状态机流转
import 'dart:convert';
import 'dart:io';

import '../models/writing_task.dart';

class WritingTaskManager {
  static const _file = 'writing_tasks.json';

  final Directory _root;
  List<WritingTask> _tasks = [];

  WritingTaskManager(this._root);

  List<WritingTask> get tasks => List.unmodifiable(_tasks);

  Future<void> load() async {
    try {
      final f = File('${_root.path}/$_file');
      if (!await f.exists()) return;
      final text = await f.readAsString();
      if (text.trim().isEmpty) return;
      final data = jsonDecode(text);
      if (data is List) {
        _tasks = data
            .whereType<Map>()
            .map((e) => WritingTask.fromJson(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final f = File('${_root.path}/$_file');
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        _tasks.map((t) => t.toJson()).toList(),
      ),
    );
  }

  Future<WritingTask> create({
    required String title,
    String topic = '',
    String outline = '',
    String draft = '',
    String articleId = '',
    WritingTaskStatus status = WritingTaskStatus.topic,
  }) async {
    final task = WritingTask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      topic: topic,
      outline: outline,
      draft: draft,
      articleId: articleId,
      status: status,
    );
    _tasks.insert(0, task);
    await _save();
    return task;
  }

  Future<WritingTask?> update(String id, WritingTask task) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return null;
    _tasks[idx] = task;
    _tasks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _save();
    return task;
  }

  Future<WritingTask?> saveTask(WritingTask task) {
    final idx = _tasks.indexWhere((t) => t.id == task.id);
    if (idx < 0) {
      _tasks.insert(0, task);
    } else {
      _tasks[idx] = task;
    }
    _tasks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _save().then((_) => task);
  }

  /// 状态机流转：推进到下一阶段
  Future<WritingTask?> advance(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return null;
    final current = _tasks[idx];
    final next = current.status.next;
    if (next == null) return null;
    final updated = current.copyWith(status: next);
    _tasks[idx] = updated;
    _tasks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _save();
    return updated;
  }

  Future<void> delete(String id) async {
    _tasks = _tasks.where((t) => t.id != id).toList();
    await _save();
  }

  List<WritingTask> byStatus(WritingTaskStatus status) =>
      _tasks.where((t) => t.status == status).toList();
}
