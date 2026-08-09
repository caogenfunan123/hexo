import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/ai/ai_session_manager.dart';
import '../core/task/task_model.dart';
import '../models/app_settings.dart';
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
  final AiService aiService;
  final AiModelManager modelManager;
  final AiRequestDispatcher dispatcher;
  final AiSelfChecker? selfChecker;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final GitHubService? gitHubService;
  final StorageService storageService;

  const AgentWorkbenchScreen({
    super.key,
    required this.settings,
    this.activeRepo,
    required this.aiService,
    required this.modelManager,
    required this.dispatcher,
    this.selfChecker,
    required this.onSettingsChanged,
    this.gitHubService,
    required this.storageService,
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
  final TextEditingController _objectiveCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();

  // 附件列表
  final List<String> _attachments = [];

  // 工作台底部标签
  int _tabIndex = 0; // 0=对话, 1=工具时间线, 2=文件变更

  String get _siteId => widget.settings.effectiveActiveSiteId;

  @override
  void initState() {
    super.initState();
    _taskRepo = TaskRepository(widget.storageService);
    _loadRecentTasks();
  }

  @override
  void dispose() {
    _objectiveCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecentTasks() async {
    final tasks = await _taskRepo.listTasks(_siteId);
    if (!mounted) return;
    setState(() => _recentTasks = tasks);
  }

  /// 新建任务
  void _newTask() {
    final objective = _objectiveCtrl.text.trim();
    if (objective.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写任务目标')),
      );
      return;
    }
    final task = AgentTask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      siteId: _siteId,
      title: _titleCtrl.text.trim().isEmpty
          ? objective.length > 20
              ? '${objective.substring(0, 20)}...'
              : objective
          : _titleCtrl.text.trim(),
      objective: objective,
      workspacePath: widget.activeRepo?.fullName,
      attachmentPaths: List.of(_attachments),
    );
    setState(() => _task = task);
    _saveTask(task);
  }

  /// 恢复任务
  void _resumeTask(AgentTask task) {
    setState(() => _task = task);
  }

  /// 保存任务（断点）
  Future<void> _saveTask(AgentTask task) async {
    await _taskRepo.saveTask(task);
    _loadRecentTasks();
  }

  /// 任务完成时保存
  Future<void> _markTaskDone(AgentTask task) async {
    await _taskRepo.saveTask(task.copyWith(status: 'done'));
    _loadRecentTasks();
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
              _chip(
                icon: Icons.link,
                label: repo == null
                    ? '未绑定工作区'
                    : '工作区: ${repo.owner}/${repo.repo}',
              ),
              _chip(
                icon: Icons.attach_file,
                label: '附件 ${_attachments.length}',
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

  /// 新建/恢复任务面板
  Widget _buildTaskSetup() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Agent 任务工作台',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(
            '给 AI 一个完整任务：附加文件、绑定工作区，实时查看工具执行与文件变更，支持多轮续跑与断点恢复。',
            style: TextStyle(fontSize: 12.5, color: cs.outline),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: '任务标题（可选）',
              border: OutlineInputBorder(),
              hintText: '例如：为博客编写 SEO 优化文章',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _objectiveCtrl,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '任务目标 *',
              border: OutlineInputBorder(),
              hintText: '描述你希望 AI 完成的任务，例如：\n分析我的 Hexo 仓库现有文章风格，围绕"Flutter 开发"写一篇 2000 字的文章并生成 frontmatter',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.attach_file, size: 16),
                label: const Text('添加附件'),
                onPressed: _pickAttachments,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.rocket_launch_outlined, size: 16),
                label: const Text('创建任务'),
                onPressed: _newTask,
              ),
            ],
          ),
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._attachments.map((p) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.insert_drive_file, size: 18),
                  title: Text(p.split('/').last,
                      style: const TextStyle(fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () =>
                        setState(() => _attachments.remove(p)),
                  ),
                )),
          ],
          const SizedBox(height: 20),
          if (_recentTasks.isNotEmpty) ...[
            Divider(color: cs.outlineVariant.withOpacity(0.4)),
            const SizedBox(height: 8),
            Text('历史任务',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            ..._recentTasks.take(10).map((t) => Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: Icon(_statusColor(t.status) == Colors.green
                        ? Icons.check_circle
                        : Icons.history,
                        color: _statusColor(t.status),
                        size: 18),
                    title: Text(t.title,
                        style: const TextStyle(fontSize: 13.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${t.objective.length > 40 ? t.objective.substring(0, 40) + '...' : t.objective} · ${_statusLabel(t.status)}',
                      style: const TextStyle(fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_arrow, size: 20),
                      tooltip: '恢复任务',
                      onPressed: () => _resumeTask(t),
                    ),
                  ),
                )),
          ],
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
    final task = _task;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent 工作台'),
        actions: [
          if (task != null)
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
        bottom: task == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: const [
                    Tab(text: '对话', icon: Icon(Icons.chat_bubble_outline, size: 18)),
                    Tab(text: '工具', icon: Icon(Icons.handyman_outlined, size: 18)),
                    Tab(text: '文件', icon: Icon(Icons.difference_outlined, size: 18)),
                  ],
                ),
              ),
      ),
      body: task == null
          ? _buildTaskSetup()
          : Column(
              children: [
                _buildTaskHeader(),
                Expanded(
                  child: IndexedStack(
                    index: _tabIndex,
                    children: [
                      _buildChatArea(task),
                      _buildToolTimeline(),
                      _buildFileChanges(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildChatArea(AgentTask task) {
    final repo = widget.activeRepo;
    final fw = repo?.frameworkId;
    return AiChatPanel(
      key: _chatKey,
      settings: widget.settings,
      aiService: widget.aiService,
      modelManager: widget.modelManager,
      dispatcher: widget.dispatcher,
      selfChecker: widget.selfChecker,
      sessionType: AiSessionType.article,
      blogFramework: fw,
      postsPath: repo?.postsPath,
      pagesPath: repo?.pagesPath,
      gitHubService: widget.gitHubService,
      activeRepo: repo,
      storageService: widget.storageService,
      initialMessage: '欢迎使用 Agent 任务工作台！\n\n'
          '任务目标：${task.objective}\n'
          '${task.attachmentPaths.isNotEmpty ? '已附加 ${task.attachmentPaths.length} 个文件。\n' : ''}'
          '${repo != null ? '工作区：${repo.owner}/${repo.repo}（${fw ?? "未知框架"}）\n' : ''}'
          '请开始执行任务，可调用工具读取仓库、分析内容并产出结果。',
      onSettingsChanged: widget.onSettingsChanged,
    );
  }
}
