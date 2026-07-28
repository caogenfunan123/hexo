import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../widgets/common_widgets.dart';

class HistoryScreen extends StatelessWidget {
  final List<GitCommitItem> commits;
  final GitHubService github;
  final RepoConfig? effectiveRepo;
  final Future<void> Function() onRefresh;
  final void Function(String) onRollback;

  const HistoryScreen({
    super.key,
    required this.commits,
    required this.github,
    required this.effectiveRepo,
    required this.onRefresh,
    required this.onRollback,
  });

  @override
  Widget build(BuildContext context) {
    if (commits.isEmpty) {
      return EmptyState(
        icon: Icons.history,
        title: '提交历史',
        subtitle: '查看 GitHub 提交记录；可对单文件恢复到历史版本',
        actionLabel: '加载历史',
        onAction: onRefresh,
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: commits.length,
        itemBuilder: (_, i) {
          final c = commits[i];
          return Card(
            child: ListTile(
              title: Text(c.message.split('\n').first, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${c.author} · ${formatDateTime(c.date)} · ${c.sha.substring(0, 7)}'),
              trailing: IconButton(
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: c.sha));
                  showToast(context, '已复制 commit sha');
                },
              ),
              onTap: () => _showCommitActions(context, c),
            ),
          );
        },
      ),
    );
  }

  void _showCommitActions(BuildContext context, GitCommitItem commit) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.copy_all), title: Text(commit.sha.substring(0, 7)), subtitle: Text(commit.message.split('\n').first)),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('回滚文件到此版本'),
            subtitle: const Text('选择文件恢复到该 commit 并创建新提交'),
            onTap: () async {
              Navigator.pop(ctx);
              final path = await _pickFile(context);
              if (path != null) onRollback(path);
            },
          ),
        ]),
      ),
    );
  }

  Future<String?> _pickFile(BuildContext context) async {
    if (effectiveRepo == null) { showToast(context, '请先配置仓库'); return null; }
    try {
      final files = await github.listPosts(effectiveRepo!);
      if (!context.mounted) return null;
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择要回滚的文件'),
          children: files.map((f) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, f.path),
            child: Text(f.name),
          )).toList(),
        ),
      );
      return result;
    } catch (e) {
      if (context.mounted) showToast(context, '加载文件列表失败');
      return null;
    }
  }
}
