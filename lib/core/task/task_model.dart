import 'dart:convert';
import 'dart:io';

import '../../services/storage_service.dart';

/// 工具执行记录（工作台时间线）
class ToolExecRecord {
  final String toolName;
  final String argsSummary;
  final String resultSummary;
  final int durationMs;
  final String status; // success / failed
  final DateTime time;

  ToolExecRecord({
    required this.toolName,
    required this.argsSummary,
    required this.resultSummary,
    required this.durationMs,
    required this.status,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        'argsSummary': argsSummary,
        'resultSummary': resultSummary,
        'durationMs': durationMs,
        'status': status,
        'time': time.toIso8601String(),
      };

  factory ToolExecRecord.fromJson(Map<String, dynamic> j) => ToolExecRecord(
        toolName: j['toolName']?.toString() ?? '',
        argsSummary: j['argsSummary']?.toString() ?? '',
        resultSummary: j['resultSummary']?.toString() ?? '',
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        status: j['status']?.toString() ?? 'success',
        time: DateTime.tryParse(j['time']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// 文件变更记录（工作台 Diff 预览）
class FileChange {
  final String path;
  final String op; // add / modify / delete
  final String diffPreview;
  final DateTime time;

  FileChange({
    required this.path,
    required this.op,
    required this.diffPreview,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'path': path,
        'op': op,
        'diffPreview': diffPreview,
        'time': time.toIso8601String(),
      };

  factory FileChange.fromJson(Map<String, dynamic> j) => FileChange(
        path: j['path']?.toString() ?? '',
        op: j['op']?.toString() ?? 'modify',
        diffPreview: j['diffPreview']?.toString() ?? '',
        time: DateTime.tryParse(j['time']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// Agent 任务模型：面向任务的代理工作台核心数据。
///
/// 包含任务目标、附件、绑定的工作区、多轮对话上下文、
/// 工具执行时间线与文件变更清单，支持序列化与断点恢复。
class AgentTask {
  final String id;
  final String siteId;
  String title;
  String objective;
  List<String> attachmentPaths; // 工作区相对路径
  String? workspacePath; // 绑定的工作区/仓库根路径
  List<Map<String, dynamic>> messages; // 多轮对话（含工具记录）
  List<ToolExecRecord> toolRecords; // 工具执行时间线
  List<FileChange> fileChanges; // 文件变更追踪
  final DateTime createdAt;
  DateTime updatedAt;
  String status; // running / paused / done / failed

  AgentTask({
    required this.id,
    required this.siteId,
    required this.title,
    required this.objective,
    List<String>? attachmentPaths,
    this.workspacePath,
    List<Map<String, dynamic>>? messages,
    List<ToolExecRecord>? toolRecords,
    List<FileChange>? fileChanges,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.status = 'running',
  })  : attachmentPaths = attachmentPaths ?? [],
        messages = messages ?? [],
        toolRecords = toolRecords ?? [],
        fileChanges = fileChanges ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  AgentTask copyWith({
    String? title,
    String? objective,
    List<String>? attachmentPaths,
    String? workspacePath,
    List<Map<String, dynamic>>? messages,
    List<ToolExecRecord>? toolRecords,
    List<FileChange>? fileChanges,
    DateTime? updatedAt,
    String? status,
  }) {
    return AgentTask(
      id: id,
      siteId: siteId,
      title: title ?? this.title,
      objective: objective ?? this.objective,
      attachmentPaths: attachmentPaths ?? this.attachmentPaths,
      workspacePath: workspacePath ?? this.workspacePath,
      messages: messages ?? this.messages,
      toolRecords: toolRecords ?? this.toolRecords,
      fileChanges: fileChanges ?? this.fileChanges,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'siteId': siteId,
        'title': title,
        'objective': objective,
        'attachmentPaths': attachmentPaths,
        'workspacePath': workspacePath,
        'messages': messages,
        'toolRecords': toolRecords.map((e) => e.toJson()).toList(),
        'fileChanges': fileChanges.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'status': status,
      };

  factory AgentTask.fromJson(Map<String, dynamic> j) => AgentTask(
        id: j['id']?.toString() ?? '',
        siteId: j['siteId']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        objective: j['objective']?.toString() ?? '',
        attachmentPaths: (j['attachmentPaths'] as List?)?.cast<String>() ?? [],
        workspacePath: j['workspacePath']?.toString(),
        messages: (j['messages'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [],
        toolRecords: (j['toolRecords'] as List?)
                ?.whereType<Map>()
                .map((e) => ToolExecRecord.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
        fileChanges: (j['fileChanges'] as List?)
                ?.whereType<Map>()
                .map((e) => FileChange.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
                DateTime.now(),
        updatedAt:
            DateTime.tryParse(j['updatedAt']?.toString() ?? '') ??
                DateTime.now(),
        status: j['status']?.toString() ?? 'running',
      );
}

/// Agent 任务持久化仓库：按站点序列化任务，支持断点恢复。
class TaskRepository {
  final StorageService storage;

  TaskRepository(this.storage);

  String _key(String siteId, String taskId) => 'task_${siteId}_$taskId.json';

  String get _indexKey => 'task_index.json';

  /// 保存任务
  Future<void> saveTask(AgentTask task) async {
    final root = (await storage.root).path;
    final file = File('$root/${_key(task.siteId, task.id)}');
    await file.writeAsString(jsonEncode(task.toJson()));
    await _updateIndex(task);
  }

  /// 加载任务
  Future<AgentTask?> loadTask(String siteId, String taskId) async {
    final root = (await storage.root).path;
    final file = File('$root/${_key(siteId, taskId)}');
    if (!await file.exists()) return null;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return null;
      return AgentTask.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  /// 列出指定站点的全部任务（按更新时间倒序）
  Future<List<AgentTask>> listTasks(String siteId) async {
    final root = (await storage.root).path;
    final files = Directory(root)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json') &&
            f.uri.pathSegments.last.startsWith('task_${siteId}_'))
        .toList();
    final tasks = <AgentTask>[];
    for (final f in files) {
      try {
        final data = jsonDecode(await f.readAsString());
        if (data is Map) {
          tasks.add(AgentTask.fromJson(Map<String, dynamic>.from(data)));
        }
      } catch (_) {}
    }
    tasks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return tasks;
  }

  /// 更新索引（用于快速列出站点任务，兼容目录扫描兜底）
  Future<void> _updateIndex(AgentTask task) async {
    final root = (await storage.root).path;
    final file = File('$root/$_indexKey');
    try {
      Map<String, dynamic> index = {};
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) index = Map<String, dynamic>.from(data);
      }
      final entries = index['tasks'] as List? ?? [];
      final list = entries.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      list.removeWhere((e) => e['id'] == task.id && e['siteId'] == task.siteId);
      list.add({
        'id': task.id,
        'siteId': task.siteId,
        'title': task.title,
        'updatedAt': task.updatedAt.toIso8601String(),
      });
      index['tasks'] = list;
      await file.writeAsString(jsonEncode(index));
    } catch (_) {}
  }

  /// 删除任务
  Future<void> deleteTask(String siteId, String taskId) async {
    final root = (await storage.root).path;
    final file = File('$root/${_key(siteId, taskId)}');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
