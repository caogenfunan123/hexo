/// 桌面版自定义标题栏
/// 布局：[汉堡菜单] [应用名] [站点下拉] [同步] [发布] [AI] ── [最小化] [最大化] [关闭]
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
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(0.85),
          border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
        ),
        child: Row(
          children: [
            // 汉堡菜单
            _titleBarButton(
              icon: Icons.menu,
              tooltip: '菜单 (Ctrl+L)',
              onTap: onToggleLeftPanel,
            ),
            const SizedBox(width: 8),

            // 应用名称
            Text(
              'AI 博客编辑器',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            // 未保存标记
            if (hasUnsavedChanges)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            const SizedBox(width: 16),

            // 站点下拉
            _siteDropdown(),
            const Spacer(),

            // 快捷操作按钮
            if (onOpenFile != null)
              _titleBarButton(
                icon: Icons.folder_open,
                tooltip: '打开文件 (Ctrl+O)',
                onTap: onOpenFile!,
              ),
            if (onNewArticle != null)
              _titleBarButton(
                icon: Icons.add,
                tooltip: '新建文章 (Ctrl+N)',
                onTap: onNewArticle!,
              ),
            _titleBarButton(
              icon: Icons.sync,
              tooltip: '同步 (Ctrl+S)',
              onTap: onSync,
            ),
            _titleBarButton(
              icon: Icons.send,
              tooltip: '一键发布 (Ctrl+P)',
              onTap: onPublish,
            ),
            _titleBarButton(
              icon: Icons.auto_awesome,
              tooltip: 'AI 助手',
              onTap: onAi,
            ),
            _titleBarButton(
              icon: Icons.dark_mode_outlined,
              tooltip: '切换主题',
              onTap: onThemeToggle,
            ),

            // 窗口控件
            _windowButton(
              icon: Icons.minimize,
              onTap: () => windowManager.minimize(),
            ),
            _windowButton(
              icon: Icons.crop_square,
              onTap: () => windowManager.maximize(),
            ),
            _windowButton(
              icon: Icons.close,
              onTap: () => windowManager.close(),
              isClose: true,
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
            child: Icon(icon, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _windowButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isClose = false,
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
            size: 16,
            color: isClose ? Colors.redAccent : null,
          ),
        ),
      ),
    );
  }

  Widget _siteDropdown() {
    if (repos.isEmpty || onSiteChange == null) {
      return Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(width: 6),
            Text(siteName, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      );
    }
    return PopupMenuButton<RepoConfig>(
      offset: const Offset(0, 34),
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(width: 6),
            Text(siteName, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
      itemBuilder: (ctx) => repos.map((r) => PopupMenuItem<RepoConfig>(
        value: r,
        child: Row(
          children: [
            Icon(
              r.isDefault ? Icons.star : Icons.hexagon_outlined,
              size: 16,
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
              Text('默认', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ],
        ),
      )).toList(),
      onSelected: onSiteChange,
    );
  }
}