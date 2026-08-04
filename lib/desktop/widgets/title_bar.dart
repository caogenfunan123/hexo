/// 桌面版自定义标题栏
/// 专业桌面端设计：清晰的视觉层次，优雅的暗色/亮色适配
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/repo_config.dart';

class DesktopTitleBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onToggleLeftPanel;
  final VoidCallback onToggleRightDrawer;
  final VoidCallback onThemeToggle;
  final VoidCallback onSync;
  final VoidCallback onPublish;
  final VoidCallback onAi;
  final VoidCallback? onOpenFile;
  final VoidCallback? onNewArticle;
  final VoidCallback? onFocusOverlay;
  final bool focusOverlayEnabled;
  final String siteName;
  final List<RepoConfig> repos;
  final ValueChanged<RepoConfig>? onSiteChange;
  final bool hasUnsavedChanges;

  const DesktopTitleBar({
    super.key,
    required this.onToggleLeftPanel,
    required this.onToggleRightDrawer,
    required this.onThemeToggle,
    required this.onSync,
    required this.onPublish,
    required this.onAi,
    this.onOpenFile,
    this.onNewArticle,
    this.onFocusOverlay,
    this.focusOverlayEnabled = false,
    this.siteName = '当前站点',
    this.repos = const [],
    this.onSiteChange,
    this.hasUnsavedChanges = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF252536)
              : const Color(0xFFFAFAFC),
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
            // 汉堡菜单
            _titleBarButton(
              icon: Icons.menu,
              tooltip: '菜单 (Ctrl+L)',
              onTap: onToggleLeftPanel,
              cs: cs,
              isDark: isDark,
            ),
            const SizedBox(width: 4),

            // 应用名称
            Text(
              'AI 博客编辑器',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withOpacity(0.7)
                    : const Color(0xFF6B7280),
                letterSpacing: 0.3,
              ),
            ),
            // 未保存标记
            if (hasUnsavedChanges)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 16),

            // 站点下拉
            _siteDropdown(context, cs, isDark),
            const Spacer(),

            // 分隔线
            Container(
              width: 1,
              height: 20,
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : const Color(0xFFE5E5EA),
            ),
            const SizedBox(width: 4),

            // 快捷操作按钮
            if (onOpenFile != null)
              _titleBarButton(
                icon: Icons.folder_open,
                tooltip: '打开文件 (Ctrl+O)',
                onTap: onOpenFile!,
                cs: cs,
                isDark: isDark,
              ),
            if (onNewArticle != null)
              _titleBarButton(
                icon: Icons.add,
                tooltip: '新建文章 (Ctrl+N)',
                onTap: onNewArticle!,
                cs: cs,
                isDark: isDark,
              ),
            _titleBarButton(
              icon: Icons.sync,
              tooltip: '同步 (Ctrl+S)',
              onTap: onSync,
              cs: cs,
              isDark: isDark,
            ),
            _titleBarButton(
              icon: Icons.send,
              tooltip: '一键发布 (Ctrl+P)',
              onTap: onPublish,
              cs: cs,
              isDark: isDark,
            ),
            _titleBarButton(
              icon: Icons.auto_awesome,
              tooltip: 'AI 助手',
              onTap: onAi,
              cs: cs,
              isDark: isDark,
            ),
            _titleBarButton(
              icon: Icons.vertical_split,
              tooltip: '右侧面板',
              onTap: onToggleRightDrawer,
              cs: cs,
              isDark: isDark,
            ),
            if (onFocusOverlay != null)
              _titleBarButton(
                icon: focusOverlayEnabled ? Icons.center_focus_strong : Icons.center_focus_weak,
                tooltip: focusOverlayEnabled ? '退出专注覆盖层' : '专注覆盖层',
                onTap: onFocusOverlay!,
                cs: cs,
                isDark: isDark,
              ),
            _titleBarButton(
              icon: isDark ? Icons.light_mode : Icons.dark_mode_outlined,
              tooltip: '切换主题',
              onTap: onThemeToggle,
              cs: cs,
              isDark: isDark,
            ),

            // 窗口控件分隔
            const SizedBox(width: 4),
            Container(
              width: 1,
              height: 20,
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : const Color(0xFFE5E5EA),
            ),
            const SizedBox(width: 2),

            // 窗口控件
            _windowButton(
              icon: Icons.minimize,
              onTap: () => windowManager.minimize(),
              isDark: isDark,
            ),
            _windowButton(
              icon: Icons.crop_square,
              onTap: () => windowManager.maximize(),
              isDark: isDark,
            ),
            _windowButton(
              icon: Icons.close,
              onTap: () => windowManager.close(),
              isClose: true,
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _titleBarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required ColorScheme cs,
    required bool isDark,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 17,
              color: isDark
                  ? Colors.white.withOpacity(0.55)
                  : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }

  Widget _windowButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isClose = false,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Icon(
            icon,
            size: 15,
            color: isClose
                ? Colors.redAccent
                : (isDark
                    ? Colors.white.withOpacity(0.55)
                    : const Color(0xFF6B7280)),
          ),
        ),
      ),
    );
  }

  Widget _siteDropdown(BuildContext context, ColorScheme cs, bool isDark) {
    if (repos.isEmpty || onSiteChange == null) {
      return Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : const Color(0xFFF3F4F6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language,
              size: 14,
              color: isDark
                  ? Colors.white.withOpacity(0.5)
                  : const Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 6),
            Text(
              siteName,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? Colors.white.withOpacity(0.7)
                    : const Color(0xFF4B5563),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isDark
                  ? Colors.white.withOpacity(0.3)
                  : const Color(0xFF9CA3AF),
            ),
          ],
        ),
      );
    }
    return PopupMenuButton<RepoConfig>(
      offset: const Offset(0, 34),
      constraints: const BoxConstraints(maxWidth: 240),
      color: isDark ? const Color(0xFF2D2D3F) : null,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : const Color(0xFFF3F4F6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language,
              size: 14,
              color: isDark
                  ? Colors.white.withOpacity(0.5)
                  : const Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 6),
            Text(
              siteName,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? Colors.white.withOpacity(0.7)
                    : const Color(0xFF4B5563),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isDark
                  ? Colors.white.withOpacity(0.3)
                  : const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
      itemBuilder: (ctx) => repos.map((r) => PopupMenuItem<RepoConfig>(
        value: r,
        height: 36,
        child: Row(
          children: [
            Icon(
              r.isDefault ? Icons.star : Icons.hexagon_outlined,
              size: 15,
              color: r.isDefault ? Colors.amber : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                r.name,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (r.isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '默认',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade700,
                  ),
                ),
              ),
          ],
        ),
      )).toList(),
      onSelected: onSiteChange,
    );
  }
}