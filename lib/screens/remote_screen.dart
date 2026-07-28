import 'package:flutter/material.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../widgets/common_widgets.dart';

class RemoteScreen extends StatelessWidget {
  final List<GitHubFileItem> posts;
  final RepoConfig? activeRepo;
  final RepoConfig? effectiveRepo;
  final GitHubService github;
  final Future<void> Function() onRefresh;
  final void Function(GitHubFileItem) onOpen;
  final void Function(GitHubFileItem) onDelete;
  final void Function(String) onRollback;
  final VoidCallback onNew;

  const RemoteScreen({
    super.key,
    required this.posts,
    required this.activeRepo,
    required this.effectiveRepo,
    required this.github,
    required this.onRefresh,
    required this.onOpen,
    required this.onDelete,
    required this.onRollback,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    if (effectiveRepo?.token.isEmpty != false) {
      return EmptyState(icon: Icons.key_outlined, title: '需要 GitHub Token', subtitle: '在设置里登录并保存 Token 后即可拉取与发布');
    }
    if (posts.isEmpty) {
      return EmptyState(icon: Icons.cloud_download_outlined, title: '暂无远程文章', subtitle: '点击刷新从 ${activeRepo?.postsPath ?? "source/_posts"} 拉取 .md', actionLabel: '刷新', onAction: onRefresh);
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: posts.length,
        itemBuilder: (_, i) {
          final f = posts[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onOpen(f),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') onOpen(f);
                  else if (v == 'delete') onDelete(f);
                  else if (v == 'rollback') onRollback(f.path);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'rollback', child: Text('回滚历史')),
                  PopupMenuItem(value: 'delete', child: Text('删除远程')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
