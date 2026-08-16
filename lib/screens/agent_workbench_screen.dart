import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/task/agent_context.dart';
import '../core/task/agent_task_type.dart';
import '../core/task/task_model.dart';
import '../core/tools/tool_entity.dart';
import '../models/app_settings.dart';
import '../models/ai_chat_message.dart';
import '../models/repo_config.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import '../widgets/ai_chat_panel.dart';

/// Agent 任务工作台：面向任务的代理工作台。
///
/// 复用 AiChatPanel 的对话能力，在其外层增加任务头：
/// 任务目标、附件、绑定的工作区、文件变更清单与任务状态，
/// 支持多轮任务管理、工具执行过程展示与断点恢复。
class AgentWorkbenchScreen extends StatefulWidget {
  final AppSettings settings;
  final RepoConfig? activeRepo;
  final List<RepoConfig> repos;
  final AiService aiService;
  final AiModelManager modelManager;
  final AiRequestDispatcher dispatcher;
  final AiSelfChecker? selfChecker;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final GitHubService? gitHubService;
  final StorageService storageService;

  /// 入口预设的任务类型：由场景入口（文章/页面/主题/巡检/应用设计）传入，
  /// 打开工作台后自动选中对应任务类型，实现「场景屏被工作台接管」。
  final AgentTaskType initialTaskType;

  const AgentWorkbenchScreen({
    super.key,
    required this.settings,
    this.activeRepo,
    this.repos = const [],
    required this.aiService,
    required this.modelManager,
    required this.dispatcher,
    this.selfChecker,
    required this.onSettingsChanged,
    this.gitHubService,
    required this.storageService,
    this.initialTaskType = AgentTaskType.general,
  });

  @override
  State<AgentWorkbenchScreen> createState() => _AgentWorkbenchScreenState();
}

class _AgentWorkbenchScreenState extends State<AgentWorkbenchScreen> {
  late TaskRepository _taskRepo;
  final GlobalKey<AiChatPanelState> _chatKey = GlobalKey();

  // 当前任务
  AgentTask? _task;
  List<AgentTask> _recentTasks = [];
  AgentTaskType _taskType = AgentTaskType.general;

  // 附件列表
  final List<String> _attachments = [];

  String get _siteId => widget.settings.effectiveActiveSiteId;

  @override
  void initState() {
    super.initState();
    _taskRepo = TaskRepository(widget.storageService);
    _taskType = widget.initialTaskType;
    // 打开工作台即进入对话：直接创建空白任务，用户对话里描述需求
    _task = _createBlankTask();
    _loadRecentTasks();
  }

  /// 创建空白任务（无前置表单，直接进入对话）
  AgentTask _createBlankTask() {
    return AgentTask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      siteId: _siteId,
      taskType: _taskType,
      title: '',
      objective: '',
      workspacePath: widget.activeRepo?.fullName,
      context: AgentContext.fromRepo(
        repo: widget.activeRepo,
        taskType: _taskType,
      ),
    );
  }

  Future<void> _loadRecentTasks() async {
    final tasks = await _taskRepo.listTasks(_siteId);
    if (!mounted) return;
    setState(() => _recentTasks = tasks);
  }

  /// 新建对话：重置为空白任务（无前置表单，直接在对话里描述需求）
  void _newTask() {
    _chatKey.currentState?.clearHistory();
    setState(() {
      _task = _createBlankTask();
      _attachments.clear();
    });
    _saveTask(_task!);
  }

  /// 恢复任务
  void _resumeTask(AgentTask task) {
    setState(() {
      _task = task;
      _taskType = task.taskType;
      _attachments
        ..clear()
        ..addAll(task.attachmentPaths);
    });
  }

  /// 历史任务选择对话框（恢复指定任务）
  Future<void> _showHistoryDialog() async {
    final selected = await showDialog<AgentTask>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      const Text('历史任务',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _recentTasks.isEmpty
                      ? Center(
                          child: Text('暂无历史任务',
                              style: TextStyle(color: cs.outline)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _recentTasks.length,
                          itemBuilder: (ctx, i) {
                            final t = _recentTasks[i];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                _statusColor(t.status) == Colors.green
                                    ? Icons.check_circle
                                    : Icons.history,
                                color: _statusColor(t.status),
                                size: 18,
                              ),
                              title: Text(
                                t.title.isEmpty ? '未命名任务' : t.title,
                                style: const TextStyle(fontSize: 13.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${t.taskType.label} · ${t.objective.isEmpty ? '无目标描述' : (t.objective.length > 40 ? t.objective.substring(0, 40) + '...' : t.objective)} · ${_statusLabel(t.status)}',
                                style: const TextStyle(fontSize: 11.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(ctx, t),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) {
      _resumeTask(selected);
    }
  }

  /// 重建任务上下文：将持久化的仓库 fullName 还原为 RepoConfig
  ///
  /// [context] 任务持久化的上下文（activeRepo 可能为空）
  /// [task] 任务（workspacePath 存仓库 fullName）
  AgentContext _restoreContext(AgentContext? context, AgentTask task) {
    final base = context ??
        AgentContext.fromRepo(
          repo: widget.activeRepo,
          taskType: task.taskType,
        );
    if (base.activeRepo != null) return base;

    final fullName = task.workspacePath;
    if (fullName == null || fullName.isEmpty) {
      return base.copyWith(activeRepo: widget.activeRepo);
    }
    // 从仓库列表按 fullName 精确匹配；匹配失败时回退当前仓库
    RepoConfig? matched;
    for (final r in widget.repos) {
      if (r.fullName == fullName) {
        matched = r;
        break;
      }
    }
    if (matched != null) {
      return AgentContext.fromRepo(repo: matched, taskType: task.taskType);
    }
    return base.copyWith(activeRepo: widget.activeRepo);
  }

  /// 保存任务（断点）
  Future<void> _saveTask(AgentTask task) async {
    final current = task.copyWith(
      attachmentPaths: List<String>.from(_attachments),
      workspacePath: widget.activeRepo?.fullName ?? task.workspacePath,
      messages: List<Map<String, dynamic>>.from(widget.dispatcher.chatHistory),
    );
    await _taskRepo.saveTask(current);
    if (mounted && _task?.id == current.id) {
      setState(() => _task = current);
    }
    _loadRecentTasks();
  }

  /// 任务完成时保存
  Future<void> _markTaskDone(AgentTask task) async {
    final updated = task.copyWith(status: 'done');
    setState(() => _task = updated);
    await _saveTask(updated);
  }

  void _recordToolExecutions(
    List<ToolCallRequest> requests,
    List<ToolCallResult> results,
  ) {
    final current = _task;
    if (current == null || requests.isEmpty || results.isEmpty) return;
    final records = List<ToolExecRecord>.from(current.toolRecords);
    for (var i = 0; i < requests.length; i++) {
      final request = requests[i];
      final result = i < results.length ? results[i] : null;
      final argsSummary = request.arguments.isEmpty
          ? '{}'
          : const JsonEncoder.withIndent('  ').convert(request.arguments);
      final resultSummary = result == null
          ? '工具未返回结果'
          : result.success
              ? _truncateText(result.content)
              : _truncateText(result.error ?? result.content);
      records.add(
        ToolExecRecord(
          toolName: request.toolId,
          argsSummary: argsSummary,
          resultSummary: resultSummary,
          durationMs: result?.durationMs ?? 0,
          status: result?.success == false ? 'failed' : 'success',
        ),
      );
    }
    final updated = current.copyWith(toolRecords: records);
    setState(() => _task = updated);
    _saveTask(updated);
  }

  void _recordParsedFileOps(List<ParsedFileOp> files) {
    final current = _task;
    if (current == null || files.isEmpty) return;
    final changes = List<FileChange>.from(current.fileChanges);
    for (final file in files) {
      _upsertFileChange(
        changes,
        FileChange(
          path: file.path,
          op: 'modify',
          diffPreview: _buildFilePreview(file),
        ),
      );
    }
    final updated = current.copyWith(fileChanges: changes);
    setState(() => _task = updated);
    _saveTask(updated);
  }

  void _recordWrittenFiles(List<ParsedFileOp> files) {
    final current = _task;
    if (current == null || files.isEmpty) return;
    final changes = List<FileChange>.from(current.fileChanges);
    for (final file in files) {
      final op = file.written ? 'modify' : 'failed';
      final preview = file.written
          ? _buildFilePreview(file)
          : '${_buildFilePreview(file)}\n\n写入失败: ${file.writeError ?? '未知错误'}';
      _upsertFileChange(
        changes,
        FileChange(path: file.path, op: op, diffPreview: preview),
      );
    }
    final updated = current.copyWith(fileChanges: changes);
    setState(() => _task = updated);
    _saveTask(updated);
  }

  void _upsertFileChange(List<FileChange> changes, FileChange change) {
    final index = changes.lastIndexWhere((item) => item.path == change.path);
    if (index >= 0) {
      changes[index] = change;
    } else {
      changes.add(change);
    }
  }

  String _buildFilePreview(ParsedFileOp file) {
    final content = file.content.trim();
    if (content.isEmpty) return '${file.path}\n<empty>';
    final lines = content.split('\n');
    final previewLines = lines.take(12).join('\n');
    final suffix = lines.length > 12 ? '\n...' : '';
    return '${file.path}\n$previewLines$suffix';
  }

  String _truncateText(String text, {int max = 300}) {
    final normalized = text.trim();
    if (normalized.length <= max) return normalized;
    return '${normalized.substring(0, max)}...';
  }

  /// 选择附件（复制到任务附件目录）
  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final root = (await widget.storageService.root).path;
    final attachmentsDir = Directory('$root/sites/$_siteId/tasks/attachments');
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }
    final paths = <String>[];
    for (final f in result.files) {
      final src = f.path;
      if (src == null) continue;
      final dest = '${attachmentsDir.path}/${f.name}';
      try {
        await File(src).copy(dest);
        paths.add(dest);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('附件复制失败: ${f.name}: $e')),
        );
      }
    }
    if (!mounted) return;
    setState(() => _attachments.addAll(paths));
  }

  /// 构建任务头
  Widget _buildTaskHeader() {
    final task = _task;
    final repo = widget.activeRepo;
    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_outlined,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task?.title ?? '未创建任务',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (task != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor(task.status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(task.status),
                    style: TextStyle(
                        fontSize: 11, color: _statusColor(task.status)),
                  ),
                ),
            ],
          ),
          if (task != null && task.objective.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              task.objective,
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.outline),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (task != null)
                _chip(
                  icon: Icons.category_outlined,
                  label: '类型: ${task.taskType.label}',
                ),
              _chip(
                icon: Icons.link,
                label: repo == null
                    ? '未绑定工作区'
                    : '工作区: ${repo.owner}/${repo.repo}',
              ),
              _chip(
                icon: Icons.attach_file,
                label: '附件 ${task?.attachmentPaths.length ?? _attachments.length}',
              ),
              if (task != null)
                _chip(
                  icon: Icons.history,
                  label: '工具 ${task.toolRecords.length} 次',
                ),
              if (task != null)
                _chip(
                  icon: Icons.difference,
                  label: '文件变更 ${task.fileChanges.length}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'done':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'paused':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'done':
        return '已完成';
      case 'failed':
        return '失败';
      case 'paused':
        return '已暂停';
      default:
        return '执行中';
    }
  }

  Widget _chip({required IconData icon, required String label}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.primary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11.5, color: cs.onSurface)),
        ],
      ),
    );
  }

  /// 工具执行时间线
  Widget _buildToolTimeline() {
    final task = _task;
    final records = task?.toolRecords ?? [];
    if (records.isEmpty) {
      return Center(
        child: Text('暂无工具执行记录',
            style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: records.length,
      itemBuilder: (context, i) {
        final r = records[i];
        final success = r.status == 'success';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? Colors.green : Colors.red,
            ),
            title: Text(r.toolName,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.argsSummary.isNotEmpty)
                  Text('入参: ${r.argsSummary}',
                      style: const TextStyle(fontSize: 12), maxLines: 2),
                if (r.resultSummary.isNotEmpty)
                  Text('结果: ${r.resultSummary}',
                      style: const TextStyle(fontSize: 12), maxLines: 3),
                Text('耗时: ${r.durationMs}ms · ${r.time.toLocal().toString().substring(0, 19)}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 文件变更清单
  Widget _buildFileChanges() {
    final task = _task;
    final changes = task?.fileChanges ?? [];
    if (changes.isEmpty) {
      return Center(
        child: Text('暂无文件变更',
            style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: changes.length,
      itemBuilder: (context, i) {
        final c = changes[i];
        final IconData icon;
        final Color color;
        switch (c.op) {
          case 'add':
            icon = Icons.add_circle_outline;
            color = Colors.green;
            break;
          case 'delete':
            icon = Icons.remove_circle_outline;
            color = Colors.red;
            break;
          default:
            icon = Icons.edit_note;
            color = Colors.blue;
        }
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(icon, color: color),
            title: Text(c.path,
                style: const TextStyle(fontSize: 13.5), maxLines: 1,
                overflow: TextOverflow.ellipsis),
            subtitle: c.diffPreview.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        c.diffPreview,
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace'),
                        maxLines: 8,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = _task ?? _createBlankTask();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Agent 工作台'),
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '历史任务',
              onPressed: _showHistoryDialog,
            ),
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: '新建对话',
              onPressed: _newTask,
            ),
            IconButton(
              icon: const Icon(Icons.fact_check_outlined),
              tooltip: '标记完成',
              onPressed: () => _markTaskDone(task),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空对话',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空聊天记录'),
                    content: const Text('确认清空所有聊天记录？此操作不可撤销。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  _chatKey.currentState?.clearHistory();
                }
              },
            ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(72),
            child: TabBar(
              indicatorSize: TabBarIndicatorSize.label,
              tabs: [
                Tab(text: '对话', icon: Icon(Icons.chat_bubble_outline, size: 18)),
                Tab(text: '工具', icon: Icon(Icons.handyman_outlined, size: 18)),
                Tab(text: '文件', icon: Icon(Icons.difference_outlined, size: 18)),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            _buildTaskHeader(),
            Expanded(
              child: TabBarView(
                children: [
                  _buildChatArea(task),
                  _buildToolTimeline(),
                  _buildFileChanges(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatArea(AgentTask task) {
    // 优先使用任务持久化的场景上下文（activeRepo 按 workspacePath 重建）；
    // 老任务（无 context）从当前仓库重建
    final context = _restoreContext(task.context, task);
    final repo = context.activeRepo ?? widget.activeRepo;
    final starter = task.taskType.starterPrompt(context);
    final objectiveLine =
        task.objective.isEmpty ? '' : '任务目标：${task.objective}\n';
    return AiChatPanel(
      key: _chatKey,
      settings: widget.settings,
      aiService: widget.aiService,
      modelManager: widget.modelManager,
      dispatcher: widget.dispatcher,
      selfChecker: widget.selfChecker,
      sessionType: task.taskType.sessionType,
      blogFramework: context.blogFramework,
      postsPath: context.postsPath,
      pagesPath: context.pagesPath,
      themesPath: context.themesPath,
      gitHubService: widget.gitHubService,
      activeRepo: repo,
      storageService: widget.storageService,
      historyKey: 'task_${task.id}',
      initialMessage: '$starter\n\n$objectiveLine'
          '${task.attachmentPaths.isNotEmpty ? '已附加 ${task.attachmentPaths.length} 个文件。\n' : ''}'
          '${repo != null ? '工作区：${repo.owner}/${repo.repo}（${repo.frameworkId ?? "未知框架"}）\n' : ''}'
          '请描述你的需求，我会调用工具读取仓库、分析内容并产出结果。',
      onSettingsChanged: widget.onSettingsChanged,
      onToolsExecuted: _recordToolExecutions,
      onFileOpsParsed: _recordParsedFileOps,
      onFilesWritten: _recordWrittenFiles,
      onAttach: _pickAttachments,
    );
  }
}
