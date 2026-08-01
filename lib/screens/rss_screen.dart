import 'package:flutter/material.dart';
import '../models/repo_config.dart';
import '../services/rss_service.dart';

class RssScreen extends StatelessWidget {
  final List<RssItem> items;
  final RepoConfig? activeRepo;
  final VoidCallback onRefresh;

  const RssScreen({super.key, required this.items, required this.activeRepo, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.rss_feed, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('暂无 RSS 内容', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text(activeRepo?.siteUrl ?? '未配置网址', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(onPressed: onRefresh, icon: const Icon(Icons.refresh, size: 18), label: const Text('刷新')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: Colors.white,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.description.replaceAll(RegExp(r'<[^>]+>'), ''), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ],
                const SizedBox(height: 6),
                Text(item.link, style: TextStyle(fontSize: 11, color: const Color(0xFF0EA5E9)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          );
        },
      ),
    );
  }
}