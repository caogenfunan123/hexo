/// 右侧悬浮抽屉面板
/// 专业桌面端设计：清晰的标签页切换，优雅的布局
library;

import 'package:flutter/material.dart';
import '../../controllers/layout_controller.dart' show RightDrawerTab;
export '../../controllers/layout_controller.dart' show RightDrawerTab;

class DesktopRightDrawer extends StatelessWidget {
  final RightDrawerTab activeTab;
  final ValueChanged<RightDrawerTab> onTabChange;
  final VoidCallback onClose;

  final List<OutlineItem> outlineItems;
  final TextEditingController? titleCtrl;
  final TextEditingController? tagsCtrl;
  final TextEditingController? categoriesCtrl;
  final TextEditingController? coverCtrl;
  final TextEditingController? dateCtrl;
  final Widget? aiChatPanel;
  final List<String> syncLogs;

  const DesktopRightDrawer({
    super.key,
    required this.activeTab,
    required this.onTabChange,
    required this.onClose,
    this.outlineItems = const [],
    this.titleCtrl,
    this.tagsCtrl,
    this.categoriesCtrl,
    this.coverCtrl,
    this.dateCtrl,
    this.aiChatPanel,
    this.syncLogs = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFFAFAFC),
        border: Border(
          left: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : const Color(0xFFE5E5EA),
          ),
        ),
      ),
      child: Column(
        children: [
          // 顶部标签栏
          _buildTabBar(cs, isDark),
          // 内容区
          Expanded(
            child: _buildContent(context, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs, bool isDark) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : const Color(0xFFE5E5EA),
          ),
        ),
      ),
      child: Row(
        children: [
          _tabButton(RightDrawerTab.outline, Icons.list_alt, '大纲', cs, isDark),
          _tabButton(RightDrawerTab.frontMatter, Icons.tune, '属性', cs, isDark),
          _tabButton(RightDrawerTab.aiChat, Icons.auto_awesome, 'AI', cs, isDark),
          _tabButton(RightDrawerTab.syncLog, Icons.sync, '日志', cs, isDark),
          const Spacer(),
          GestureDetector(
            onTap: onClose,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.close,
                size: 15,
                color: isDark
                    ? Colors.white.withOpacity(0.4)
                    : const Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(RightDrawerTab tab, IconData icon, String label, ColorScheme cs, bool isDark) {
    final isActive = activeTab == tab;
    return GestureDetector(
      onTap: () => onTabChange(tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isActive
                ? (isDark ? Colors.white.withOpacity(0.08) : cs.primary.withOpacity(0.08))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive
                    ? cs.primary
                    : (isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF9CA3AF)),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive
                      ? cs.primary
                      : (isDark ? Colors.white.withOpacity(0.5) : const Color(0xFF6B7280)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isDark) {
    switch (activeTab) {
      case RightDrawerTab.outline:
        return _buildOutline(context, isDark);
      case RightDrawerTab.frontMatter:
        return _buildFrontMatter(context, isDark);
      case RightDrawerTab.aiChat:
        return _buildAiChat(context, isDark);
      case RightDrawerTab.syncLog:
        return _buildSyncLog(context, isDark);
    }
  }

  Widget _buildOutline(BuildContext context, bool isDark) {
    if (outlineItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.list_alt,
              size: 36,
              color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE5E7EB),
            ),
            const SizedBox(height: 8),
            Text(
              '暂无大纲',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white.withOpacity(0.3) : const Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '在文章中使用标题即可生成大纲',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFD1D5DB),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: outlineItems.length,
      itemBuilder: (_, i) {
        final item = outlineItems[i];
        return Padding(
          padding: EdgeInsets.only(left: (item.level - 1) * 16.0),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: item.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      item.level == 1 ? Icons.title : Icons.subdirectory_arrow_right,
                      size: 12,
                      color: isDark
                          ? Colors.white.withOpacity(0.3)
                          : const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 12 + (3 - item.level).clamp(0, 2).toDouble(),
                          fontWeight: item.level == 1 ? FontWeight.w600 : FontWeight.w400,
                          color: isDark
                              ? Colors.white.withOpacity(0.8)
                              : const Color(0xFF374151),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFrontMatter(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fmField(context, '标题', titleCtrl, isDark: isDark),
          const SizedBox(height: 10),
          _fmField(context, '标签', tagsCtrl, hint: '逗号分隔', isDark: isDark),
          const SizedBox(height: 10),
          _fmField(context, '分类', categoriesCtrl, hint: '逗号分隔', isDark: isDark),
          const SizedBox(height: 10),
          _fmField(context, '封面图', coverCtrl, hint: '图片 URL', isDark: isDark),
          const SizedBox(height: 10),
          _fmField(context, '日期', dateCtrl, hint: 'YYYY-MM-DD', isDark: isDark),
        ],
      ),
    );
  }

  Widget _fmField(BuildContext context, String label, TextEditingController? ctrl, {String? hint, bool isDark = false}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark
                ? Colors.white.withOpacity(0.4)
                : const Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF374151),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white.withOpacity(0.2) : const Color(0xFFD1D5DB),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: isDark
                ? Colors.white.withOpacity(0.04)
                : const Color(0xFFF9FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: cs.primary.withOpacity(0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiChat(BuildContext context, bool isDark) {
    if (aiChatPanel != null) return aiChatPanel!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 40,
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : const Color(0xFFE5E7EB),
          ),
          const SizedBox(height: 12),
          Text(
            'AI 助手',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Colors.white.withOpacity(0.4)
                  : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '选择文章后可使用 AI 辅助写作',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? Colors.white.withOpacity(0.25)
                  : const Color(0xFFD1D5DB),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncLog(BuildContext context, bool isDark) {
    if (syncLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sync,
              size: 36,
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : const Color(0xFFE5E7EB),
            ),
            const SizedBox(height: 8),
            Text(
              '暂无同步日志',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? Colors.white.withOpacity(0.3)
                    : const Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: syncLogs.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          syncLogs[i],
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: isDark
                ? Colors.white.withOpacity(0.5)
                : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}

/// 大纲条目
class OutlineItem {
  final int level;
  final String title;
  final VoidCallback? onTap;

  const OutlineItem({
    required this.level,
    required this.title,
    this.onTap,
  });
}

/// 从 Markdown 内容解析大纲
List<OutlineItem> parseOutline(String markdown) {
  final items = <OutlineItem>[];
  final lines = markdown.split('\n');
  for (final line in lines) {
    final match = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line.trim());
    if (match != null) {
      items.add(OutlineItem(
        level: match.group(1)!.length,
        title: match.group(2)!.trim(),
      ));
    }
  }
  return items;
}