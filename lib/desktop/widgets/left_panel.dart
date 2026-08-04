/// 桌面端左侧导航面板
/// 专业桌面端设计：分组折叠式导航，清晰的视觉层次
library;

import 'package:flutter/material.dart';
import '../../models/repo_config.dart';
import '../../models/article.dart';
import '../../core/site_manager.dart';

class DesktopLeftPanel extends StatefulWidget {
  final double width;
  final ValueChanged<double> onResize;
  final VoidCallback onCollapse;

  // 实时数据
  final List<RepoConfig> repos;
  final List<Article> drafts;
  final SiteManager siteManager;

  // 导航回调
  final VoidCallback onNewArticle;
  final VoidCallback onOpenDrafts;
  final VoidCallback onOpenRemote;
  final VoidCallback onOpenSync;
  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenRss;
  final VoidCallback onOpenBatchUpload;
  final VoidCallback onOpenPreview;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenSyncSettings;
  final VoidCallback onOpenLogs;
  final VoidCallback onOpenThemeMigration;
  final VoidCallback onShowTemplateManager;
  final VoidCallback onShowSnippetManager;
  final VoidCallback onShowConfigEditor;
  final VoidCallback onShowAiArticleChat;
  final VoidCallback onShowAiPageChat;
  final VoidCallback onShowAiThemeChat;
  final VoidCallback onShowAiAudit;
  final VoidCallback onShowAiModelManager;
  final VoidCallback onShowToolLibrary;
  final VoidCallback onShowBlogSiteManager;
  final VoidCallback onShowSiteEditor;
  final ValueChanged<RepoConfig>? onSiteChange;
  final VoidCallback onShowHelp;
  final VoidCallback onOpenRecycleBin;
  final VoidCallback onOpenP2PSync;
  final VoidCallback onOpenImageBedManager;
  final VoidCallback onOpenProxySettings;
  final VoidCallback onOpenCacheCleanup;
  final VoidCallback onExportLogs;
  final VoidCallback onOpenLinkChecker;
  final VoidCallback onOpenBatchTools;
  final VoidCallback onOpenAiPromptTemplates;

  const DesktopLeftPanel({
    super.key,
    required this.width,
    required this.onResize,
    required this.onCollapse,
    this.repos = const [],
    this.drafts = const [],
    required this.siteManager,
    required this.onNewArticle,
    required this.onOpenDrafts,
    required this.onOpenRemote,
    required this.onOpenSync,
    required this.onOpenDashboard,
    required this.onOpenHistory,
    required this.onOpenRss,
    required this.onOpenBatchUpload,
    required this.onOpenPreview,
    required this.onOpenSettings,
    required this.onOpenSyncSettings,
    required this.onOpenLogs,
    required this.onOpenThemeMigration,
    required this.onShowTemplateManager,
    required this.onShowSnippetManager,
    required this.onShowConfigEditor,
    required this.onShowAiArticleChat,
    required this.onShowAiPageChat,
    required this.onShowAiThemeChat,
    required this.onShowAiAudit,
    required this.onShowAiModelManager,
    required this.onShowToolLibrary,
    required this.onShowBlogSiteManager,
    required this.onShowSiteEditor,
    this.onSiteChange,
    required this.onShowHelp,
    required this.onOpenRecycleBin,
    required this.onOpenP2PSync,
    required this.onOpenImageBedManager,
    required this.onOpenProxySettings,
    required this.onOpenCacheCleanup,
    required this.onExportLogs,
    required this.onOpenLinkChecker,
    required this.onOpenBatchTools,
    required this.onOpenAiPromptTemplates,
  });

  @override
  State<DesktopLeftPanel> createState() => _DesktopLeftPanelState();
}

class _DesktopLeftPanelState extends State<DesktopLeftPanel> {
  // 折叠的分组
  final Set<String> _collapsedSections = {};

  // 拖拽调整宽度
  bool _resizing = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: widget.width.clamp(200, 400),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E2E)
            : const Color(0xFFF5F5F7),
        border: Border(
          right: BorderSide(
            color: isDark
                ? cs.outlineVariant.withOpacity(0.15)
                : const Color(0xFFE0E0E5),
          ),
        ),
      ),
      child: Stack(
        children: [
          // 主内容
          Column(
            children: [
              // 面板头部
              _buildHeader(cs, isDark),
              const SizedBox(height: 4),

              // 滚动内容
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  children: [
                    // 创作
                    _buildSection(
                      key: 'create',
                      title: '创作',
                      icon: Icons.edit_square,
                      collapsed: _collapsedSections.contains('create'),
                      onToggle: () => _toggleSection('create'),
                      children: [
                        _navItem(
                          icon: Icons.add_circle_outline,
                          label: '新建文章',
                          onTap: widget.onNewArticle,
                          isPrimary: true,
                          shortcut: 'Ctrl+N',
                        ),
                        _navItem(
                          icon: Icons.drafts_outlined,
                          label: '草稿箱',
                          onTap: widget.onOpenDrafts,
                          badge: widget.drafts.where((d) => !d.published).length,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // 站点
                    _buildSection(
                      key: 'sites',
                      title: '站点',
                      icon: Icons.folder_outlined,
                      collapsed: _collapsedSections.contains('sites'),
                      onToggle: () => _toggleSection('sites'),
                      children: [
                        ...widget.repos.map((r) => _siteItem(
                          name: r.name,
                          subtitle: r.fullName,
                          icon: r.isDefault ? Icons.star : Icons.hexagon_outlined,
                          isDefault: r.isDefault,
                          isActive: false,
                          onTap: () => widget.onSiteChange?.call(r),
                        )),
                        ...widget.siteManager.dynamicSites.map((s) => _siteItem(
                          name: s.name,
                          subtitle: s.siteUrl,
                          icon: Icons.language,
                          isActive: false,
                          onTap: () {
                            // 动态站点点击：打开站点管理
                            widget.onShowBlogSiteManager();
                          },
                        )),
                        _navItem(
                          icon: Icons.add,
                          label: '添加站点',
                          onTap: widget.onShowSiteEditor,
                          isSubtle: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // 管理
                    _buildSection(
                      key: 'manage',
                      title: '管理',
                      icon: Icons.settings,
                      collapsed: _collapsedSections.contains('manage'),
                      onToggle: () => _toggleSection('manage'),
                      children: [
                        _navItem(icon: Icons.cloud_outlined, label: '远程文章', onTap: widget.onOpenRemote),
                        _navItem(icon: Icons.sync, label: '同步状态', onTap: widget.onOpenSync),
                        _navItem(icon: Icons.dashboard_outlined, label: '仪表盘', onTap: widget.onOpenDashboard),
                        _navItem(icon: Icons.history_outlined, label: '提交历史', onTap: widget.onOpenHistory),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // 工具
                    _buildSection(
                      key: 'tools',
                      title: '工具',
                      icon: Icons.build_outlined,
                      collapsed: _collapsedSections.contains('tools'),
                      onToggle: () => _toggleSection('tools'),
                      children: [
                        _navItem(icon: Icons.drive_folder_upload, label: '批量上传', onTap: widget.onOpenBatchUpload),
                        _navItem(icon: Icons.language, label: '网站预览', onTap: widget.onOpenPreview),
                        _navItem(icon: Icons.rss_feed_outlined, label: 'RSS 订阅', onTap: widget.onOpenRss),
                        _navItem(icon: Icons.view_quilt_outlined, label: '模板管理', onTap: widget.onShowTemplateManager),
                        _navItem(icon: Icons.content_paste, label: '片段素材库', onTap: widget.onShowSnippetManager),
                        _navItem(icon: Icons.settings_applications, label: '配置编辑器', onTap: widget.onShowConfigEditor),
                        _navItem(icon: Icons.swap_horiz, label: 'AI 批量迁移', onTap: widget.onOpenThemeMigration),
                        _navItem(icon: Icons.photo_library_outlined, label: '图床管理', onTap: widget.onOpenImageBedManager),
                        _navItem(icon: Icons.link_off, label: '链接检测', onTap: widget.onOpenLinkChecker),
                        _navItem(icon: Icons.build_circle, label: '批量工具箱', onTap: widget.onOpenBatchTools),
                        _navItem(icon: Icons.vpn_lock_outlined, label: '代理设置', onTap: widget.onOpenProxySettings),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // AI 工具
                    _buildSection(
                      key: 'ai',
                      title: 'AI 工具',
                      icon: Icons.auto_awesome,
                      collapsed: _collapsedSections.contains('ai'),
                      onToggle: () => _toggleSection('ai'),
                      children: [
                        _navItem(icon: Icons.article_outlined, label: 'AI 博文创作', onTap: widget.onShowAiArticleChat),
                        _navItem(icon: Icons.web_outlined, label: 'AI 页面创作', onTap: widget.onShowAiPageChat),
                        _navItem(icon: Icons.palette_outlined, label: 'AI 主题开发', onTap: widget.onShowAiThemeChat),
                        _navItem(icon: Icons.fact_check_outlined, label: 'AI 站点巡检', onTap: widget.onShowAiAudit),
                        _navItem(icon: Icons.psychology_outlined, label: 'AI 模型管理', onTap: widget.onShowAiModelManager),
                        _navItem(icon: Icons.text_snippet_outlined, label: 'AI 提示词模板', onTap: widget.onOpenAiPromptTemplates),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // 系统
                    _buildSection(
                      key: 'system',
                      title: '系统',
                      icon: Icons.dns_outlined,
                      collapsed: _collapsedSections.contains('system'),
                      onToggle: () => _toggleSection('system'),
                      children: [
                        _navItem(icon: Icons.cloud_sync, label: '云同步', onTap: widget.onOpenSyncSettings),
                        _navItem(icon: Icons.wifi, label: 'P2P 同步', onTap: widget.onOpenP2PSync),
                        _navItem(icon: Icons.settings_outlined, label: '设置', onTap: widget.onOpenSettings),
                        _navItem(icon: Icons.history, label: '操作日志', onTap: widget.onOpenLogs),
                        _navItem(icon: Icons.delete_outline, label: '回收站', onTap: widget.onOpenRecycleBin),
                        _navItem(icon: Icons.cleaning_services_outlined, label: '缓存清理', onTap: widget.onOpenCacheCleanup),
                        _navItem(icon: Icons.bug_report_outlined, label: '导出日志', onTap: widget.onExportLogs),
                        _navItem(icon: Icons.dns_outlined, label: '动态博客登录', onTap: widget.onShowBlogSiteManager),
                        _navItem(icon: Icons.storage_outlined, label: '站点管理', onTap: widget.onShowSiteEditor),
                        _navItem(icon: Icons.help_outline, label: '帮助 / 快捷键', onTap: widget.onShowHelp),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),

          // 右侧拖拽调整宽度手柄
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _buildResizeHandle(isDark),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 面板头部
  // ============================================================
  Widget _buildHeader(ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            Icons.auto_stories,
            size: 18,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '导航',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? cs.onSurface.withOpacity(0.5)
                  : const Color(0xFF6B7280),
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          _iconButton(
            Icons.chevron_left,
            tooltip: '折叠面板',
            onTap: widget.onCollapse,
            cs: cs,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 可折叠分组
  // ============================================================
  Widget _buildSection({
    required String key,
    required String title,
    required IconData icon,
    required bool collapsed,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组标题
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            child: Row(
              children: [
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 14,
                  color: isDark
                      ? Colors.white.withOpacity(0.3)
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 4),
                Icon(
                  icon,
                  size: 12,
                  color: isDark
                      ? Colors.white.withOpacity(0.3)
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Colors.white.withOpacity(0.3)
                        : const Color(0xFF9CA3AF),
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 分组内容
        if (!collapsed) ...children,
      ],
    );
  }

  // ============================================================
  // 导航项
  // ============================================================
  Widget _navItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
    bool isSubtle = false,
    String? shortcut,
    int badge = 0,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isPrimary
                      ? cs.primary
                      : isSubtle
                          ? (isDark ? Colors.white.withOpacity(0.35) : const Color(0xFF9CA3AF))
                          : (isDark ? Colors.white.withOpacity(0.6) : const Color(0xFF4B5563)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w400,
                      color: isPrimary
                          ? cs.primary
                          : (isDark ? Colors.white.withOpacity(0.8) : const Color(0xFF374151)),
                    ),
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ),
                if (shortcut != null)
                  Text(
                    shortcut,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white.withOpacity(0.2) : const Color(0xFFD1D5DB),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 站点项
  // ============================================================
  Widget _siteItem({
    required String name,
    String? subtitle,
    required IconData icon,
    bool isDefault = false,
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: isActive
            ? (isDark ? Colors.white.withOpacity(0.08) : cs.primary.withOpacity(0.08))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: isDefault
                      ? Colors.amber.shade600
                      : (isDark ? Colors.white.withOpacity(0.5) : const Color(0xFF6B7280)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF374151),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white.withOpacity(0.35) : const Color(0xFF9CA3AF),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '默认',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.amber.shade700),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 图标按钮
  // ============================================================
  Widget _iconButton(
    IconData icon, {
    String? tooltip,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 15, color: cs.onSurface.withOpacity(0.4)),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 拖拽调整宽度手柄
  // ============================================================
  Widget _buildResizeHandle(bool isDark) {
    return GestureDetector(
      onHorizontalDragStart: (_) => setState(() => _resizing = true),
      onHorizontalDragUpdate: (d) {
        widget.onResize(widget.width + d.delta.dx);
      },
      onHorizontalDragEnd: (_) => setState(() => _resizing = false),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 4,
          color: _resizing
              ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
              : Colors.transparent,
          child: Center(
            child: Container(
              width: 1,
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.08),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 切换分组折叠
  // ============================================================
  void _toggleSection(String key) {
    setState(() {
      if (_collapsedSections.contains(key)) {
        _collapsedSections.remove(key);
      } else {
        _collapsedSections.add(key);
      }
    });
  }
}