/// 桌面版自定义标题栏
/// 阶段1（界面改版）：Mac/Bear 风格——
/// 红绿灯窗口按钮左置、极简动作区、去分隔线（留白分层）、整栏可拖拽移窗
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
      onDoubleTap: () async {
        // 双击标题栏 = 最大化/还原（macOS 惯例）
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: Container(
        height: 44,
        color: AppColor.surfaceRaised(context),
        // Material(transparency)：为栏内 InkWell/PopupMenuButton 提供必需的
        // Material 祖先。缺失时站点下拉渲染为红色错误框（存量 bug，曾表现为
        // 标题栏按钮失效）。
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            children: [
            // ── 红绿灯（macOS 惯例：左置） ──
            const SizedBox(width: 14),
            _trafficLights(),
            const SizedBox(width: 10),

            // 汉堡菜单（左栏开关）
            _titleBarButton(
              context,
              icon: Icons.menu,
              tooltip: '文章栏 (Ctrl+L)',
              onTap: bus.onToggleLeftPanel,
              cs: cs,
            ),
            const SizedBox(width: 8),

            // 应用名 + 站点下拉
            Text(
              '拓墨',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColor.textSecondary(context),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: _siteDropdown(context, cs),
            ),

            // ── 中段留白（拖拽区） ──
            Expanded(child: SizedBox.expand()),

            // ── 极简动作区：窄窗时可横向滚动防溢出 ──
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _titleBarButton(
                    context,
                    icon: Icons.add,
                    tooltip: '新建文章 (Ctrl+N)',
                    onTap: bus.onNewArticle,
                    cs: cs,
                  ),
                  _titleBarButton(
                    context,
                    icon: Icons.save_outlined,
                    tooltip: '存草稿 (Ctrl+S)',
                    onTap: bus.onSaveLocal,
                    cs: cs,
                  ),
                  _titleBarButton(
                    context,
                    icon: Icons.auto_awesome,
                    tooltip: 'AI 助手',
                    onTap: onAi,
                    cs: cs,
                  ),
                  _titleBarButton(
                    context,
                    icon: Icons.send,
                    tooltip: '一键发布 (Ctrl+P)',
                    onTap: bus.onPublish,
                    cs: cs,
                  ),
                  _titleBarButton(
                    context,
                    icon: isDark ? Icons.light_mode : Icons.dark_mode_outlined,
                    tooltip: '切换主题',
                    onTap: bus.onThemeToggle,
                    cs: cs,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// macOS 红绿灯：关闭(红)/最小化(黄)/最大化(绿)，悬停显示符号
  Widget _trafficLights() {
    return _TrafficLightGroup();
  }

  Widget _titleBarButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 18,
              color: AppColor.icon(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _siteDropdown(BuildContext context, ColorScheme cs) {
    if (repos.isEmpty || bus.onSiteChange == null) {
      return Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppColor.surfaceHover(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language,
              size: 15,
              color: AppColor.iconMuted(context),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                siteName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColor.textSecondary(context),
                ),
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
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppColor.surfaceHover(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language,
              size: 15,
              color: AppColor.iconMuted(context),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                siteName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColor.textSecondary(context),
                ),
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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '默认',
                  style: TextStyle(
                    fontSize: 10,
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

/// 红绿灯按钮组（有状态：悬停任一灯时显示符号，macOS 行为）
class _TrafficLightGroup extends StatefulWidget {
  @override
  State<_TrafficLightGroup> createState() => _TrafficLightGroupState();
}

class _TrafficLightGroupState extends State<_TrafficLightGroup> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _light(
            color: const Color(0xFFFF5F57),
            hoveredSymbol: Icons.close,
            onTap: () => windowManager.close(),
            tooltip: '关闭（隐藏到托盘）',
          ),
          const SizedBox(width: 8),
          _light(
            color: const Color(0xFFFEBC2E),
            hoveredSymbol: Icons.remove,
            onTap: () => windowManager.minimize(),
            tooltip: '最小化',
          ),
          const SizedBox(width: 8),
          _light(
            color: const Color(0xFF28C840),
            hoveredSymbol: Icons.crop_square,
            onTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            tooltip: '最大化/还原',
          ),
        ],
      ),
    );
  }

  Widget _light({
    required Color color,
    required IconData hoveredSymbol,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: _hovering
                ? Icon(hoveredSymbol, size: 9, color: Colors.black.withOpacity(0.55))
                : null,
          ),
        ),
      ),
    );
  }
}
