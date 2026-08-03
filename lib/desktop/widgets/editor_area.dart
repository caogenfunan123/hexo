/// 桌面端中央编辑区域
/// 专业桌面端设计：优雅的标签栏，清晰的空状态引导
library;

import 'package:flutter/material.dart';
import 'work_mode.dart';

/// 编辑器标签页数据
class EditorTab {
  final String id;
  final String title;
  final IconData icon;
  final Widget content;
  final bool canClose;

  const EditorTab({
    required this.id,
    required this.title,
    required this.icon,
    required this.content,
    this.canClose = true,
  });
}

class DesktopEditorArea extends StatelessWidget {
  final List<EditorTab> tabs;
  final int activeIndex;
  final WorkMode workMode;
  final ValueChanged<int> onTabChange;
  final ValueChanged<int> onTabClose;
  final VoidCallback? onNewArticle;
  final VoidCallback? onSync;
  final VoidCallback? onSettings;

  const DesktopEditorArea({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.workMode,
    required this.onTabChange,
    required this.onTabClose,
    this.onNewArticle,
    this.onSync,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) {
      return _emptyState(context);
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      child: Column(
        children: [
          // 标签页栏
          _buildTabBar(cs, isDark),
          // 内容区域
          Expanded(
            child: IndexedStack(
              index: activeIndex.clamp(0, tabs.length - 1),
              children: tabs.map((t) => t.content).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs, bool isDark) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E2E)
            : const Color(0xFFF5F5F7),
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
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              padding: const EdgeInsets.only(left: 4),
              itemBuilder: (_, i) {
                final tab = tabs[i];
                final isActive = i == activeIndex;
                return GestureDetector(
                  onTap: () => onTabChange(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isActive
                          ? (isDark ? const Color(0xFF1A1A2E) : Colors.white)
                          : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      border: isActive
                          ? Border(
                              top: BorderSide(
                                color: cs.primary,
                                width: 2,
                              ),
                              left: BorderSide(
                                color: isDark
                                    ? Colors.white.withOpacity(0.06)
                                    : const Color(0xFFE5E5EA),
                              ),
                              right: BorderSide(
                                color: isDark
                                    ? Colors.white.withOpacity(0.06)
                                    : const Color(0xFFE5E5EA),
                              ),
                            )
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab.icon,
                          size: 14,
                          color: isActive
                              ? cs.primary
                              : (isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF9CA3AF)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tab.title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                            color: isActive
                                ? (isDark ? Colors.white : const Color(0xFF1F2937))
                                : (isDark ? Colors.white.withOpacity(0.5) : const Color(0xFF6B7280)),
                          ),
                        ),
                        if (tab.canClose) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => onTabClose(i),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: isDark
                                    ? Colors.white.withOpacity(0.2)
                                    : const Color(0xFFD1D5DB),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // 新建标签按钮
          if (onNewArticle != null)
            GestureDetector(
              onTap: onNewArticle,
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.add,
                  size: 16,
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

  Widget _emptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 大图标
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.03)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.edit_note,
                size: 48,
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : const Color(0xFFD1D5DB),
              ),
            ),
            const SizedBox(height: 24),

            // 标题
            Text(
              '欢迎使用 AI 博客编辑器',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withOpacity(0.6)
                    : const Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),

            // 副标题
            Text(
              '创建新文章开始写作，或从左侧面板打开已有内容',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? Colors.white.withOpacity(0.3)
                    : const Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 32),

            // 快捷操作按钮
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _quickAction(
                  context,
                  icon: Icons.add_circle_outline,
                  label: '新建文章',
                  shortcut: 'Ctrl+N',
                  onTap: onNewArticle,
                  isDark: isDark,
                ),
                const SizedBox(width: 16),
                _quickAction(
                  context,
                  icon: Icons.sync,
                  label: '同步数据',
                  shortcut: 'Ctrl+S',
                  onTap: onSync,
                  isDark: isDark,
                ),
                const SizedBox(width: 16),
                _quickAction(
                  context,
                  icon: Icons.settings_outlined,
                  label: '设置',
                  shortcut: 'Ctrl+,',
                  onTap: onSettings,
                  isDark: isDark,
                ),
              ],
            ),

            const SizedBox(height: 32),

            // 快捷键提示
            Text(
              'Ctrl+N 新建 · Ctrl+S 保存 · Ctrl+P 发布 · Ctrl+L 菜单',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? Colors.white.withOpacity(0.15)
                    : const Color(0xFFD1D5DB),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String shortcut,
    required VoidCallback? onTap,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.03)
              : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: cs.primary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? Colors.white.withOpacity(0.7)
                    : const Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              shortcut,
              style: TextStyle(
                fontSize: 10,
                color: isDark
                    ? Colors.white.withOpacity(0.2)
                    : const Color(0xFFD1D5DB),
              ),
            ),
          ],
        ),
      ),
    );
  }
}