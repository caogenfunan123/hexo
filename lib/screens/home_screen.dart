import 'package:flutter/material.dart' hide Badge;
import '../models/article.dart';
import '../models/article_template.dart';
import '../widgets/common_widgets.dart';

class HomeScreen extends StatelessWidget {
  final List<Article> drafts;
  final List<ArticleTemplate> templates;
  final void Function(Article) onOpen;
  final void Function(Article) onDelete;
  final VoidCallback onNew;
  final void Function(ArticleTemplate) onNewFromTemplate;
  final VoidCallback onImport;

  const HomeScreen({
    super.key,
    required this.drafts,
    required this.templates,
    required this.onOpen,
    required this.onDelete,
    required this.onNew,
    required this.onNewFromTemplate,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    if (drafts.isEmpty) {
      return EmptyState(
        icon: Icons.note_add_outlined,
        title: '还没有草稿',
        subtitle: '支持离线编辑，写完后一键发布',
        actionLabel: '新建文章',
        onAction: onNew,
        child: Column(children: [
          OutlinedButton.icon(onPressed: onImport, icon: const Icon(Icons.file_open_outlined, size: 16), label: const Text('导入 .md 文件')),
          if (templates.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('或从模板开始：', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: templates.map((t) => ActionChip(
              avatar: const Icon(Icons.article_outlined, size: 16),
              label: Text(t.name, style: const TextStyle(fontSize: 12)),
              onPressed: () => onNewFromTemplate(t),
            )).toList()),
          ],
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: drafts.length,
        itemBuilder: (_, i) {
          final a = drafts[i];
          final wordCount = a.content.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z]'), '').length;
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onOpen(a),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(a.title.isEmpty ? '未命名' : a.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Badge(a.published ? '已发布' : '草稿', color: a.published ? const Color(0xFF059669) : const Color(0xFFD97706)),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      a.content.replaceAll(RegExp(r'\s+'), ' ').trim(),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.access_time, size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text(formatDateTime(a.updatedAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      if (wordCount > 0) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.text_fields, size: 13, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text('$wordCount 字', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ],
                      const Spacer(),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'delete') {
                            final ok = await showConfirm(context, title: '删除草稿', message: '确认删除「${a.title}」？', confirmColor: Colors.red);
                            if (ok) onDelete(a);
                          }
                        },
                        icon: const Icon(Icons.more_horiz, size: 18),
                        itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('删除草稿'))],
                      ),
                    ]),
                    if (a.tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(spacing: 4, runSpacing: 4, children: a.tags.take(4).map((t) => Badge('#$t', color: const Color(0xFF0EA5E9))).toList()),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
