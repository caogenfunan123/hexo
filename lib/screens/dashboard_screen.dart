import 'dart:math';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../models/article.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';
import '../widgets/common_widgets.dart';

class DashboardScreen extends StatelessWidget {
  final List<Article> drafts;
  final List<GitHubFileItem> remotePosts;
  final List<GitCommitItem> commits;
  final AppSettings settings;
  final RepoConfig? activeRepo;
  final VoidCallback onNewPost;

  const DashboardScreen({
    super.key,
    required this.drafts,
    required this.remotePosts,
    required this.commits,
    required this.settings,
    required this.activeRepo,
    required this.onNewPost,
  });

  @override
  Widget build(BuildContext context) {
    final publishedDrafts = drafts.where((d) => d.published).length;
    final unpublished = drafts.where((d) => !d.published).length;
    final totalWords = drafts.fold<int>(0, (sum, d) => sum + d.content.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z]'), '').length);
    final recentDrafts = drafts.take(5).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(title: '写作概览'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: StatCard(label: '草稿', value: '$unpublished', icon: Icons.drafts_outlined, color: const Color(0xFFD97706))),
          const SizedBox(width: 8),
          Expanded(child: StatCard(label: '已发布', value: '$publishedDrafts', icon: Icons.cloud_done_outlined, color: const Color(0xFF059669))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: StatCard(label: '远程文章', value: '${remotePosts.length}', icon: Icons.cloud_outlined, color: const Color(0xFF0EA5E9))),
          const SizedBox(width: 8),
          Expanded(child: StatCard(label: '总字数', value: _formatNumber(totalWords), icon: Icons.text_fields, color: const Color(0xFF7C3AED))),
        ]),
        if (activeRepo != null) ...[
          const SizedBox(height: 8),
          StatCard(label: '提交次数', value: '${commits.length}', icon: Icons.history, color: const Color(0xFF6366F1)),
        ],
        const SizedBox(height: 20),
        const SectionTitle(title: '最近草稿'),
        if (recentDrafts.isEmpty)
          Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('暂无草稿', style: TextStyle(color: Colors.grey.shade500))))
        else
          ...recentDrafts.map((a) => Card(
            child: ListTile(
              leading: const Icon(Icons.article_outlined, color: Color(0xFF0EA5E9)),
              title: Text(a.title.isEmpty ? '未命名' : a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatDateTime(a.updatedAt), style: const TextStyle(fontSize: 12)),
              trailing: Badge(a.published ? '已发布' : '草稿'),
            ),
          )),
        const SizedBox(height: 20),
        const SectionTitle(title: '快捷操作'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('写文章'), onPressed: onNewPost),
          ActionChip(avatar: const Icon(Icons.auto_awesome, size: 18), label: const Text('AI 灵感'), onPressed: onNewPost),
        ]),
        const SizedBox(height: 40),
      ],
    );
  }

  String _formatNumber(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
