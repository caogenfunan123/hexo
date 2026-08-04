/// 文章大纲/目录面板
/// 自动解析 Markdown 标题层级，点击跳转到对应位置
library;

import 'package:flutter/material.dart';

/// 大纲条目
class OutlineEntry {
  final String text;
  final int level; // 1-6
  final int lineNumber;

  const OutlineEntry({
    required this.text,
    required this.level,
    required this.lineNumber,
  });
}

/// 文章大纲面板
class OutlinePanel extends StatefulWidget {
  final String markdown;
  final ValueChanged<int>? onJumpToLine;
  final bool isDark;

  const OutlinePanel({
    super.key,
    required this.markdown,
    this.onJumpToLine,
    this.isDark = false,
  });

  /// 从 Markdown 文本解析标题
  static List<OutlineEntry> parse(String markdown) {
    final entries = <OutlineEntry>[];
    final lines = markdown.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final match = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line.trim());
      if (match != null) {
        final level = match.group(1)!.length;
        final text = match.group(2)!.trim();
        entries.add(OutlineEntry(
          text: text,
          level: level,
          lineNumber: i,
        ));
      }
    }
    return entries;
  }

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  int _activeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = widget.isDark;
    final entries = OutlinePanel.parse(widget.markdown);

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.list_alt,
              size: 32,
              color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFD1D5DB),
            ),
            const SizedBox(height: 8),
            Text(
              '暂无标题',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white.withOpacity(0.3) : const Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '使用 # 标题语法自动生成大纲',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFD1D5DB),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final entry = entries[i];
        final isActive = i == _activeIndex;
        final leftPadding = 12.0 + (entry.level - 1) * 16.0;

        return GestureDetector(
          onTap: () {
            setState(() => _activeIndex = i);
            widget.onJumpToLine?.call(entry.lineNumber);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.only(
              left: leftPadding,
              right: 12,
              top: 6,
              bottom: 6,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? cs.primary.withOpacity(isDark ? 0.15 : 0.08)
                  : Colors.transparent,
              border: isActive
                  ? Border(
                      left: BorderSide(
                        color: cs.primary,
                        width: 2.5,
                      ),
                    )
                  : null,
            ),
            child: Text(
              entry.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: entry.level == 1 ? 13 : 12,
                fontWeight: entry.level <= 2 ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? cs.primary
                    : (isDark
                        ? Colors.white.withOpacity(entry.level <= 2 ? 0.6 : 0.4)
                        : Color.lerp(const Color(0xFF1F2937), const Color(0xFF6B7280), (entry.level - 1) / 5.0)!),
              ),
            ),
          ),
        );
      },
    );
  }
}