import 'package:flutter/material.dart';
import '../models/article.dart';

class DraftsScreen extends StatelessWidget {
  final List<Article> drafts;
  final void Function(Article) onOpen;
  final void Function(Article) onDelete;

  const DraftsScreen({super.key, required this.drafts, required this.onOpen, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (drafts.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.drafts_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('暂无草稿', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: drafts.length,
      itemBuilder: (_, i) {
        final a = drafts[i];
        final wordCount = a.content.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z]'), '').length;
        final preview = a.content.replaceAll(RegExp(r'\s+'), ' ').trim();
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: Colors.white,
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onOpen(a),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(a.title.isEmpty ? '未命名' : a.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: a.published ? const Color(0xFF059669).withOpacity(0.1) : const Color(0xFFD97706).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(a.published ? '已发布' : '草稿', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: a.published ? const Color(0xFF059669) : const Color(0xFFD97706))),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'delete') {
                        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                          title: const Text('删除草稿'),
                          content: Text('确认删除「${a.title}」？'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                            FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
                          ],
                        ));
                        if (ok == true) onDelete(a);
                      }
                    },
                    icon: const Icon(Icons.more_horiz, size: 18, color: Color(0xFF64748B)),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('删除草稿'))],
                  ),
                ]),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.access_time, size: 13, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text(_fmt(a.updatedAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  if (wordCount > 0) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.text_fields, size: 13, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text('$wordCount 字', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  ],
                ]),
                if (a.tags.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 4, runSpacing: 4, children: a.tags.take(4).map((t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                    child: Text('#$t', style: const TextStyle(fontSize: 11, color: Color(0xFF0EA5E9))),
                  )).toList())),
              ]),
            ),
          ),
        );
      },
    );
  }

  String _fmt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}