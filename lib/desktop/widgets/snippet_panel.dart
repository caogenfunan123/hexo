/// 片段素材面板
/// 快速插入常用 Markdown 片段：友链模板、公告、版权声明、代码块等
library;

import 'package:flutter/material.dart';
import '../../services/storage_service.dart';

/// 片段素材面板
class SnippetPanel extends StatefulWidget {
  final List<SnippetItem> snippets;
  final ValueChanged<String> onInsert;
  final ValueChanged<SnippetItem>? onDelete;
  final VoidCallback? onAddNew;
  final bool isDark;

  const SnippetPanel({
    super.key,
    required this.snippets,
    required this.onInsert,
    this.onDelete,
    this.onAddNew,
    this.isDark = false,
  });

  @override
  State<SnippetPanel> createState() => _SnippetPanelState();
}

class _SnippetPanelState extends State<SnippetPanel> {
  final _searchCtrl = TextEditingController();
  String _activeCategory = '全部';
  List<SnippetItem> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.snippets);
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void didUpdateWidget(SnippetPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snippets != widget.snippets) {
      _applyFilter();
    }
  }

  void _onSearch() {
    _applyFilter();
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = widget.snippets.where((s) {
        final matchCategory = _activeCategory == '全部' || s.category == _activeCategory;
        final matchSearch = query.isEmpty ||
            s.name.toLowerCase().contains(query) ||
            s.content.toLowerCase().contains(query);
        return matchCategory && matchSearch;
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearch);
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _categories {
    final cats = <String>{'全部'};
    for (final s in widget.snippets) {
      cats.add(s.category);
    }
    return cats.toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = widget.isDark;

    return Column(
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF374151)),
            decoration: InputDecoration(
              hintText: '搜索片段...',
              hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white.withOpacity(0.2) : const Color(0xFFD1D5DB)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              prefixIcon: Icon(Icons.search, size: 16, color: isDark ? Colors.white.withOpacity(0.3) : const Color(0xFF9CA3AF)),
              filled: true,
              fillColor: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // 分类标签
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (_, i) {
              final cat = _categories[i];
              final active = cat == _activeCategory;
              return GestureDetector(
                onTap: () {
                  setState(() => _activeCategory = cat);
                  _applyFilter();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: active
                        ? cs.primary.withOpacity(isDark ? 0.25 : 0.12)
                        : (isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF3F4F6)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active
                          ? cs.primary
                          : (isDark ? Colors.white.withOpacity(0.5) : const Color(0xFF6B7280)),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 4),

        // 片段列表
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.content_paste_off, size: 32, color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFD1D5DB)),
                      const SizedBox(height: 8),
                      Text(
                        widget.snippets.isEmpty ? '暂无片段' : '无匹配结果',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white.withOpacity(0.3) : const Color(0xFF9CA3AF)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.snippets.isEmpty ? '点击 + 添加常用片段' : '尝试其他搜索词',
                        style: TextStyle(fontSize: 10, color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFD1D5DB)),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (_, i) {
                    final sn = _filtered[i];
                    return _SnippetCard(
                      snippet: sn,
                      onInsert: () => widget.onInsert(sn.content),
                      onDelete: widget.onDelete != null ? () => widget.onDelete!(sn) : null,
                      isDark: isDark,
                      cs: cs,
                    );
                  },
                ),
        ),

        // 底部添加按钮
        if (widget.onAddNew != null)
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE5E5EA)),
              ),
            ),
            child: InkWell(
              onTap: widget.onAddNew,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 16, color: isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF9CA3AF)),
                    const SizedBox(width: 4),
                    Text(
                      '添加新片段',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SnippetCard extends StatelessWidget {
  final SnippetItem snippet;
  final VoidCallback onInsert;
  final VoidCallback? onDelete;
  final bool isDark;
  final ColorScheme cs;

  const _SnippetCard({
    required this.snippet,
    required this.onInsert,
    this.onDelete,
    required this.isDark,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final preview = snippet.content.length > 80
        ? '${snippet.content.substring(0, 80)}...'
        : snippet.content;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onInsert,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      snippet.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF374151),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      snippet.category,
                      style: TextStyle(fontSize: 9, color: cs.primary, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onDelete,
                      child: Icon(Icons.close, size: 14, color: isDark ? Colors.white.withOpacity(0.2) : const Color(0xFFD1D5DB)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.4,
                  color: isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}