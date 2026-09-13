import 'package:flutter/material.dart';

import '../models/article.dart';
import '../widgets/markdown_preview_smooth.dart';

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
          : MarkdownPreviewSmooth(
              markdown: article.content,
              baseFontSize: 15,
              lineHeight: 1.8,
              padding: const EdgeInsets.all(20),
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