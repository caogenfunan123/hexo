/// 桌面版中央编辑区域
/// 支持多标签页、WYSIWYG/Markdown 双模式、实时预览
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

    return Column(
      children: [
        // ── 标签页栏 ──
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(0.5),
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: tabs.length,
                  itemBuilder: (_, i) {
                    final tab = tabs[i];
                    final isActive = i == activeIndex;
                    return GestureDetector(
                      onTap: () => onTabChange(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isActive ? cs.primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(tab.icon, size: 14, color: isActive ? cs.primary : cs.onSurface.withOpacity(0.5)),
                            const SizedBox(width: 6),
                            Text(
                              tab.title,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                color: isActive ? cs.primary : cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            if (tab.canClose) ...[
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => onTabClose(i),
                                child: Icon(Icons.close, size: 14, color: cs.onSurface.withOpacity(0.3)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // ── 内容区域 ──
        Expanded(
          child: IndexedStack(
            index: activeIndex,
            children: tabs.map((t) => t.content).toList(),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note, size: 64, color: cs.onSurface.withOpacity(0.15)),
          const SizedBox(height: 16),
          Text(
            'AI 博客编辑器',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '从左侧面板打开草稿或新建文章',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _quickAction(context, Icons.add, '新建文章', onNewArticle),
              const SizedBox(width: 16),
              _quickAction(context, Icons.sync, '同步数据', onSync),
              const SizedBox(width: 16),
              _quickAction(context, Icons.settings_outlined, '设置', onSettings),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickAction(BuildContext context, IconData icon, String label, VoidCallback? onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
        ],
      ),
    );
  }
}