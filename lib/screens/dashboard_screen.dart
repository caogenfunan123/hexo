import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../models/article.dart';
import '../models/repo_config.dart';
import '../services/github_service.dart';

class DashboardScreen extends StatelessWidget {
  final List<Article> drafts;
  final List<GitHubFileItem> remotePosts;
  final List<GitCommitItem> commits;
  final AppSettings settings;
  final RepoConfig? activeRepo;
  final VoidCallback onNewPost;

  const DashboardScreen({super.key, required this.drafts, required this.remotePosts, required this.commits, required this.settings, required this.activeRepo, required this.onNewPost});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats cards
        Row(children: [
          _statCard(context, '本地草稿', '${drafts.length}', Icons.drafts_outlined, const Color(0xFF0EA5E9)),
          const SizedBox(width: 10),
          _statCard(context, '远程文章', '${remotePosts.length}', Icons.cloud_outlined, const Color(0xFF10B981)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _statCard(context, '提交次数', '${commits.length}', Icons.history, const Color(0xFF8B5CF6)),
          const SizedBox(width: 10),
          _statCard(context, '仓库', activeRepo?.name ?? '-', Icons.storage_outlined, const Color(0xFFF59E0B)),
        ]),
        const SizedBox(height: 20),
        // Quick actions
        Text('快捷操作', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E))),
        const SizedBox(height: 10),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          child: Column(children: [
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: cs.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.edit, size: 20, color: cs.primary),
              ),
              title: const Text('新建文章', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('开始写一篇新文章', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
              onTap: onNewPost,
            ),
            if (activeRepo != null)
              ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.language, size: 20, color: Color(0xFF10B981)),
                ),
                title: const Text('预览网站', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(activeRepo!.siteUrl.isNotEmpty ? activeRepo!.siteUrl : '未配置网址', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
              ),
          ]),
        ),
        const SizedBox(height: 20),
        // Recent commits
        if (commits.isNotEmpty) ...[
          Text('最近提交', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E))),
          const SizedBox(height: 10),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            child: Column(
              children: commits.take(5).map((c) => ListTile(
                dense: true,
                leading: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.history, size: 16, color: Color(0xFF8B5CF6)),
                ),
                title: Text(c.message.split('\n').first, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_fmt(c.date), style: const TextStyle(fontSize: 11)),
              )).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _statCard(BuildContext context, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 10),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E))),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}