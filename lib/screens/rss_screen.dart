import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/repo_config.dart';
import '../services/rss_service.dart';
import '../widgets/common_widgets.dart';

class RssScreen extends StatelessWidget {
  final List<RssItem> items;
  final RepoConfig? activeRepo;
  final Future<void> Function() onRefresh;
  final void Function(RssItem) onOpenAsDraft;

  const RssScreen({
    super.key,
    required this.items,
    required this.activeRepo,
    required this.onRefresh,
    required this.onOpenAsDraft,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.rss_feed,
        title: 'RSS 未加载',
        subtitle: '从站点 atom.xml / rss.xml 读取最新文章',
        actionLabel: '加载 RSS',
        onAction: onRefresh,
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final it = items[i];
          return Card(
            child: ListTile(
              title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (it.pubDate != null)
                    Text(formatDateTime(it.pubDate!), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  if (it.description.isNotEmpty)
                    Text(it.description, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ),
              onTap: () {
                Clipboard.setData(ClipboardData(text: it.link));
                showToast(context, '链接已复制: ${it.link}');
              },
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'copy') { Clipboard.setData(ClipboardData(text: it.link)); showToast(context, '链接已复制'); }
                  else if (v == 'draft') onOpenAsDraft(it);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'draft', child: Text('转为草稿编辑')),
                  PopupMenuItem(value: 'copy', child: Text('复制链接')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
