import 'package:flutter/material.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';

class RemoteScreen extends StatelessWidget {
  final List<GitHubFileItem> posts;
  final RepoConfig? activeRepo;
  final RepoConfig? effectiveRepo;
  final GitHubService github;
  final VoidCallback onRefresh;
  final void Function(GitHubFileItem) onOpen;

  const RemoteScreen({super.key, required this.posts, required this.activeRepo, required this.effectiveRepo, required this.github, required this.onRefresh, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('暂无远程文章', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text(activeRepo?.fullName ?? '', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(onPressed: onRefresh, icon: const Icon(Icons.refresh, size: 18), label: const Text('刷新')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: posts.length,
        itemBuilder: (_, i) {
          final p = posts[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: Colors.white,
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onOpen(p),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.description_outlined, size: 20, color: Color(0xFF0EA5E9)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(p.path, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}