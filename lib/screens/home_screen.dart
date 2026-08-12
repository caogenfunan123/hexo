/// 首页 — 卷宗文章列表
///
/// 简易普通用户模式的默认首页：按卷宗（Article.volume）分组展示文章，
/// 自动过滤系统诊断日志文件（如 llama_diag_log 前缀），空值文章归「未分类」。
library;

import 'package:flutter/material.dart';
import '../models/article.dart';
import '../desktop/feature_entries.dart';

class HomeScreen extends StatelessWidget {
  final List<Article> articles;
  final ValueChanged<Article> onOpenArticle;
  final VoidCallback onNewArticle;

  /// 卷宗内新建：传入卷宗名，空字符串表示「未分类」
  final ValueChanged<String>? onNewArticleInVolume;

  const HomeScreen({
    super.key,
    this.articles = const [],
    required this.onOpenArticle,
    required this.onNewArticle,
    this.onNewArticleInVolume,
  });

  /// 过滤系统诊断日志后的文章
  List<Article> get _userArticles {
    return articles
        .where((a) {
          final name = a.title.trim();
          if (SystemLogFiles.isSystemLogFileName(name)) return false;
          final fn = a.fileName();
          if (SystemLogFiles.isSystemLogFileName(fn)) return false;
          return true;
        })
        .toList();
  }

  /// 按卷宗分组（未分类置后）
  List<(String, List<Article>)> get _grouped {
    final groups = <String, List<Article>>{};
    for (final a in _userArticles) {
      final vol = (a.volume == null || a.volume!.trim().isEmpty)
          ? '未分类'
          : a.volume!.trim();
      groups.putIfAbsent(vol, () => []).add(a);
    }
    final sorted = groups.entries.toList()
      ..sort((x, y) {
        if (x.key == '未分类') return 1;
        if (y.key == '未分类') return -1;
        return x.key.compareTo(y.key);
      });
    return sorted.map((e) => (e.key, e.value)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grouped = _grouped;
    final total = _userArticles.length;

    return Column(
      children: [
        // 顶部工具栏：新建文稿 + 统计
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Text(
                '首页',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '共 $total 篇文章',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF9CA3AF),
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: onNewArticle,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建文稿'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 卷宗分组列表
        Expanded(
          child: grouped.isEmpty
              ? _emptyState(cs, isDark)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: grouped.length,
                  itemBuilder: (context, gi) {
                    final (vol, items) = grouped[gi];
                    return _volumeSection(cs, isDark, vol, items);
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyState(ColorScheme cs, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined,
              size: 44, color: isDark ? Colors.white.withOpacity(0.2) : const Color(0xFFD1D5DB)),
          const SizedBox(height: 12),
          Text(
            '还没有文章',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white.withOpacity(0.6) : const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '点击「新建文稿」开始写作',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white.withOpacity(0.35) : const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _volumeSection(
      ColorScheme cs, bool isDark, String vol, List<Article> items) {
    final volKey = vol == '未分类' ? '' : vol;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined,
                    size: 14, color: isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF9CA3AF)),
                const SizedBox(width: 6),
                Text(
                  vol,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF374151),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${items.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white.withOpacity(0.3) : const Color(0xFFB0B7C3),
                  ),
                ),
                const Spacer(),
                if (onNewArticleInVolume != null)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => onNewArticleInVolume!(volKey),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.add,
                          size: 15,
                          color: isDark ? Colors.white.withOpacity(0.45) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...items.map((a) => _articleCard(cs, isDark, a)),
        ],
      ),
    );
  }

  Widget _articleCard(ColorScheme cs, bool isDark, Article a) {
    final preview = a.content.replaceAll(RegExp(r'[#*>`\-\n]'), ' ').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onOpenArticle(a),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title.isEmpty ? '(无标题)' : a.title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF1F2937),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (preview.isNotEmpty)
                        Text(
                          preview.length > 60 ? '${preview.substring(0, 60)}…' : preview,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF9CA3AF),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _fmtDate(a.updatedAt),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white.withOpacity(0.3) : const Color(0xFFB0B7C3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
