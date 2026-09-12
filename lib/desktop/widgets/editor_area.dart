/// 桌面端中央编辑区域
/// 专业桌面端设计：优雅的标签栏，清晰的空状态引导
library;

import 'package:flutter/material.dart';
import '../../controllers/editor_controller.dart';
import '../../theme/app_color.dart';

class DesktopEditorArea extends StatelessWidget {
  final List<EditorTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onTabChange;
  final ValueChanged<int> onTabClose;
  final VoidCallback? onNewArticle;
  final VoidCallback? onSync;
  final VoidCallback? onSettings;

  const DesktopEditorArea({
    super.key,
    required this.tabs,
    required this.activeIndex,
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

    return Container(
      color: AppColor.surfaceBase(context),
      child: Column(
        children: [
          // 标签页栏
          _buildTabBar(context, cs),
          // 内容区域
          Expanded(child: _buildActiveContent()),
        ],
      ),
    );
  }

  /// 仅挂载激活标签：多个标签会共享同一 FocusNode/controller，
  /// 触发 "A FocusNode cannot be used in multiple widgets" 崩溃，
  /// 因此不做跨标签保活（原 IndexedStack 对非激活标签返回空壳，与此等价）。
  Widget _buildActiveContent() {
    final index = activeIndex.clamp(0, tabs.length - 1);
    final t = tabs[index];
    if (t.contentBuilder != null) {
      return Builder(builder: t.contentBuilder!);
    }
    return const SizedBox.shrink();
  }

  Widget _buildTabBar(BuildContext context, ColorScheme cs) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: AppColor.surfaceBase(context),
        border: Border(
          bottom: BorderSide(
            color: AppColor.border(context),
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
                          ? (AppColor.surfaceBase(context))
                          : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      border: isActive
                          ? Border(
                              top: BorderSide(
                                color: cs.primary,
                                width: 2,
                              ),
                              left: BorderSide(
                                color: AppColor.border(context),
                              ),
                              right: BorderSide(
                                color: AppColor.border(context),
                              ),
                            )
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab.icon,
                          size: 15,
                          color: isActive
                              ? cs.primary
                              : (AppColor.textMuted(context)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tab.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                            color: isActive
                                ? AppColor.textPrimary(context)
                                : (AppColor.icon(context)),
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
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: AppColor.borderStrong(context),
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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: AppColor.textMuted(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Container(
      color: AppColor.surfaceBase(context),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // 大图标
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColor.surfaceHover(context),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.edit_note,
                size: 48,
                color: AppColor.borderStrong(context),
              ),
            ),
            const SizedBox(height: 24),

            // 标题
            Text(
              '欢迎使用 AI 博客编辑器',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColor.textSecondary(context),
              ),
            ),
            const SizedBox(height: 8),

            // 副标题
            Text(
              '创建新文章开始写作，或从左侧面板打开已有内容',
              style: TextStyle(
                fontSize: 14,
                color: AppColor.textMuted(context),
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
                  
                ),
                const SizedBox(width: 16),
                _quickAction(
                  context,
                  icon: Icons.sync,
                  label: '同步数据',
                  shortcut: 'Ctrl+S',
                  onTap: onSync,
                  
                ),
                const SizedBox(width: 16),
                _quickAction(
                  context,
                  icon: Icons.settings_outlined,
                  label: '设置',
                  shortcut: 'Ctrl+,',
                  onTap: onSettings,
                  
                ),
              ],
            ),

            const SizedBox(height: 32),

            // 快捷键提示
            Text(
              'Ctrl+N 新建 · Ctrl+S 保存 · Ctrl+P 发布 · Ctrl+L 菜单',
              style: TextStyle(
                fontSize: 11,
                color: AppColor.borderStrong(context),
              ),
            ),
          ],
        ),
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
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColor.surfaceHover(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColor.border(context),
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
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColor.textSecondary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              shortcut,
              style: TextStyle(
                fontSize: 11,
                color: AppColor.borderStrong(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}