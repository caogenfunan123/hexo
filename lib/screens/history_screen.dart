import 'package:flutter/material.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';

class HistoryScreen extends StatelessWidget {
  final List<GitCommitItem> commits;
  final GitHubService github;
  final RepoConfig? effectiveRepo;
  final VoidCallback onRefresh;

  const HistoryScreen({super.key, required this.commits, required this.github, required this.effectiveRepo, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (commits.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('暂无提交历史', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(onPressed: onRefresh, icon: const Icon(Icons.refresh, size: 18), label: const Text('刷新')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: commits.length,
        itemBuilder: (_, i) {
          final c = commits[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: Colors.white,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.history, size: 18, color: Color(0xFF8B5CF6)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.message.split('\n').first, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(c.author, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    const SizedBox(width: 8),
                    Text(c.sha.substring(0, 7), style: TextStyle(fontSize: 11, color: const Color(0xFF0EA5E9), fontFamily: 'monospace')),
                  ]),
                ])),
                Text(_fmt(c.date), style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
              ]),
            ),
          );
        },
      ),
    );
  }

  String _fmt(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}