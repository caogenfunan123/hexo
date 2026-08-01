import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/article.dart';

/// 纯阅读预览页 — 打开远程/历史文章优先进入此页面
class ArticleReaderScreen extends StatelessWidget {
  final Article article;
  final VoidCallback onEnterEdit;
  final VoidCallback onClose;

  const ArticleReaderScreen({
    super.key,
    required this.article,
    required this.onEnterEdit,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.close, color: cs.primary, size: 20),
          ),
          tooltip: '关闭',
          onPressed: () => _showExitDialog(context),
        ),
        title: Text(
          article.title.isEmpty ? '阅读' : article.title,
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          FilledButton.icon(
            onPressed: onEnterEdit,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('编辑'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: article.content.isEmpty
          ? const Center(
              child: Text('暂无内容',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15)))
          : Markdown(
              data: article.content,
              selectable: true,
              padding: const EdgeInsets.all(20),
              styleSheet: MarkdownStyleSheet(
                h1: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                    height: 1.4),
                h2: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                    height: 1.4),
                h3: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                    height: 1.4),
                p: const TextStyle(
                    fontSize: 15,
                    height: 1.8,
                    color: Color(0xFF334155)),
                code: TextStyle(
                    fontSize: 13.5,
                    backgroundColor: Colors.grey.shade100,
                    color: const Color(0xFF0EA5E9)),
                codeblockDecoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12)),
                blockquoteDecoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                        left: BorderSide(
                            color: cs.primary.withOpacity(0.3), width: 3))),
              ),
            ),
    );
  }

  void _showExitDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出阅读'),
        content: const Text('确认退出当前文章？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onClose();
            },
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
  }
}