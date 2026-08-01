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
  final VoidCallback onNavigateToRemote;
  final VoidCallback onNavigateToHistory;
  final VoidCallback onNavigateToSettings;
  final VoidCallback onNavigateToPreview;
  final VoidCallback onNavigateToDrafts;

  const DashboardScreen({
    super.key,
    required this.drafts,
    required this.remotePosts,
    required this.commits,
    required this.settings,
    required this.activeRepo,
    required this.onNewPost,
    required this.onNavigateToRemote,
    required this.onNavigateToHistory,
    required this.onNavigateToSettings,
    required this.onNavigateToPreview,
    required this.onNavigateToDrafts,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats cards
        Row(children: [
          _statCard(context, '本地草稿', '${drafts.length}', Icons.drafts_outlined,
              const Color(0xFF0EA5E9), onNavigateToDrafts),
          const SizedBox(width: 10),
          _statCard(context, '远程文章', '${remotePosts.length}', Icons.cloud_outlined,
              const Color(0xFF10B981), onNavigateToRemote),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _statCard(context, '提交次数', '${commits.length}', Icons.history,
              const Color(0xFF8B5CF6), onNavigateToHistory),
          const SizedBox(width: 10),
          _statCard(context, '仓库', activeRepo?.name ?? '-',
              Icons.storage_outlined, const Color(0xFFF59E0B), onNavigateToSettings),
        ]),
        const SizedBox(height: 20),
        // Quick actions
        Text('快捷操作',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E))),
        const SizedBox(height: 10),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          child: Column(children: [
            _actionTile(
              icon: Icons.edit,
              color: cs.primary,
              title: '新建文章',
              subtitle: '开始写一篇新文章',
              onTap: onNewPost,
            ),
            _actionTile(
              icon: Icons.drafts_outlined,
              color: const Color(0xFF0EA5E9),
              title: '管理草稿',
              subtitle: '查看和编辑本地草稿',
              onTap: onNavigateToDrafts,
            ),
            _actionTile(
              icon: Icons.cloud_outlined,
              color: const Color(0xFF10B981),
              title: '远程文章',
              subtitle: '查看和管理 GitHub 上的文章',
              onTap: onNavigateToRemote,
            ),
            _actionTile(
              icon: Icons.history,
              color: const Color(0xFF8B5CF6),
              title: '提交历史',
              subtitle: '查看提交记录并回滚文件',
              onTap: onNavigateToHistory,
            ),
            if (activeRepo != null)
              _actionTile(
                icon: Icons.language,
                color: const Color(0xFFF59E0B),
                title: '预览网站',
                subtitle: activeRepo!.siteUrl.isNotEmpty
                    ? activeRepo!.siteUrl
                    : '未配置网址',
                onTap: onNavigateToPreview,
              ),
            _actionTile(
              icon: Icons.settings_outlined,
              color: const Color(0xFF64748B),
              title: '设置',
              subtitle: '配置 Token、仓库、AI、备份等',
              onTap: onNavigateToSettings,
            ),
          ]),
        ),
        const SizedBox(height: 20),
        // Recent commits
        if (commits.isNotEmpty) ...[
          Text('最近提交',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E))),
          const SizedBox(height: 10),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            child: Column(
              children: commits
                  .take(5)
                  .map((c) => ListTile(
                        dense: true,
                        onTap: onNavigateToHistory,
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6)
                                .withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.history,
                              size: 16, color: Color(0xFF8B5CF6)),
                        ),
                        title: Text(c.message.split('\n').first,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(_fmt(c.date),
                            style: const TextStyle(fontSize: 11)),
                      ))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _statCard(BuildContext context, String label, String value,
      IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(height: 10),
              Text(value,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E))),
              const SizedBox(height: 2),
              Text(label,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
      onTap: onTap,
    );
  }

  String _fmt(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}