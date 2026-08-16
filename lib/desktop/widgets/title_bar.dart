/// 桌面版自定义标题栏
/// 专业桌面端设计：清晰的视觉层次，优雅的暗色/亮色适配
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/repo_config.dart';
import '../../theme/app_color.dart';
import '../shell_action_bus.dart';

class DesktopTitleBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onAi;
  final String siteName;
  final List<RepoConfig> repos;

  final ShellActionBus bus;

  const DesktopTitleBar({
    super.key,
    required this.bus,
    required this.onAi,
    this.siteName = '当前站点',
    this.repos = const [],
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
          color: AppColor.surfaceRaised(context),
          border: Border(
            bottom: BorderSide(color: AppColor.border(context)),
          ),
        ),
        child: Row(
          children: [
            // 汉堡菜单
            _titleBarButton(
              icon: Icons.menu,
              tooltip: '菜单 (Ctrl+L)',
              onTap: bus.onToggleLeftPanel,
              cs: cs,
            ),
            const SizedBox(width: 4),

            // 应用名称
            Text(
              '拓墨',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColor.textSecondary(context),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 16),

            // 站点下拉
            _siteDropdown(context, cs),
            const Spacer(),

            // 分隔线
            Container(
              width: 1,
              height: 20,
              color: AppColor.border(context),
            ),
            const SizedBox(width: 4),

            // 快捷操作按钮
            if (bus.onOpenFile != null)
              _titleBarButton(
                icon: Icons.folder_open,
                tooltip: '打开文件 (Ctrl+O)',
                onTap: bus.onOpenFile!,
                cs: cs,
              ),
            _titleBarButton(
              icon: Icons.add,
              tooltip: '新建文章 (Ctrl+N)',
              onTap: bus.onNewArticle,
              cs: cs,
            ),
            _titleBarButton(
              icon: Icons.sync,
              tooltip: '同步 (Ctrl+S)',
              onTap: bus.onSync,
              cs: cs,
            ),
            _titleBarButton(
              icon: Icons.send,
              tooltip: '一键发布 (Ctrl+P)',
              onTap: bus.onPublish,
              cs: cs,
            ),
            _titleBarButton(
              icon: Icons.auto_awesome,
              tooltip: 'AI 助手',
              onTap: onAi,
              cs: cs,
            ),
            _titleBarButton(
              icon: Icons.vertical_split,
              tooltip: '右侧面板',
              onTap: bus.onToggleRightDrawer,
              cs: cs,
            ),
            _titleBarButton(
              icon: isDark ? Icons.light_mode : Icons.dark_mode_outlined,
              tooltip: '切换主题',
              onTap: bus.onThemeToggle,
              cs: cs,
            ),

            // 窗口控件分隔
            const SizedBox(width: 4),
            Container(
              width: 1,
              height: 20,
              color: AppColor.border(context),
            ),
            const SizedBox(width: 2),

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
    required ColorScheme cs,
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
              color: AppColor.icon(context),
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
            color: isClose ? Colors.redAccent : AppColor.icon(context),
          ),
        ),
      ),
    );
  }

  Widget _siteDropdown(BuildContext context, ColorScheme cs) {
    if (repos.isEmpty || bus.onSiteChange == null) {
      return Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          color: AppColor.surfaceHover(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language,
              size: 14,
              color: AppColor.iconMuted(context),
            ),
            const SizedBox(width: 6),
            Text(
              siteName,
              style: TextStyle(
                fontSize: 12,
                color: AppColor.textSecondary(context),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: AppColor.iconMuted(context),
            ),
          ],
        ),
      );
    }
    return PopupMenuButton<RepoConfig>(
      offset: const Offset(0, 34),
      constraints: const BoxConstraints(maxWidth: 240),
      color: Theme.of(context).brightness == Brightness.dark
          ? AppColor.surfaceOverlay(context)
          : null,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          color: AppColor.surfaceHover(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language,
              size: 14,
              color: AppColor.iconMuted(context),
            ),
            const SizedBox(width: 6),
            Text(
              siteName,
              style: TextStyle(
                fontSize: 12,
                color: AppColor.textSecondary(context),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: AppColor.iconMuted(context),
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
      onSelected: bus.onSiteChange,
    );
  }
}