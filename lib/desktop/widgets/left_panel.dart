/// 桌面端左侧导航面板
/// 专业桌面端设计：分组折叠式导航，清晰的视觉层次
library;

import 'package:flutter/material.dart';
import '../../models/repo_config.dart';
import '../../models/article.dart';
import '../../models/ui_settings.dart';
import '../../core/site_manager.dart';
import '../../widgets/article_action_menu.dart';
import '../shell_action_bus.dart';
import '../feature_entries.dart';

class DesktopLeftPanel extends StatefulWidget {
  final double width;
  final ValueChanged<double> onResize;
  final VoidCallback onCollapse;

  // 实时数据
  final List<RepoConfig> repos;
  final List<Article> drafts;
  final SiteManager siteManager;

  // 界面模式（简易/标准）
  final AppMode mode;
  final List<String> simpleModeExtras;

  // 折叠状态持久化（保持上次状态）
  final List<String> collapsedSections;
  final ValueChanged<List<String>>? onCollapsedSectionsChanged;

  // 统一回调总线
  final ShellActionBus bus;

  const DesktopLeftPanel({
    super.key,
    required this.width,
    required this.onResize,
    required this.onCollapse,
    this.repos = const [],
    this.drafts = const [],
    required this.siteManager,
    required this.bus,
    this.mode = AppMode.simple,
    this.simpleModeExtras = const [],
    this.collapsedSections = const [],
    this.onCollapsedSectionsChanged,
  });

  @override
  State<DesktopLeftPanel> createState() => _DesktopLeftPanelState();
}

class _DesktopLeftPanelState extends State<DesktopLeftPanel> {
  // 折叠的分组（默认全折叠，保持上次状态）
  late final Set<String> _collapsedSections;

  // 拖拽调整宽度
  bool _resizing = false;

  /// 所有可折叠分组的 key（含内嵌文章列表分组）
  static const List<String> _sectionKeys = [
    'create',
    'articles',
    'sites',
    'manage',
    'tools',
    'ai',
    'system',
  ];

  @override
  void initState() {
    super.initState();
    _collapsedSections =
        (widget.collapsedSections.isNotEmpty
                ? widget.collapsedSections
                : _sectionKeys)
            .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: widget.width.clamp(200, 400),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F7),
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
                        ..._nav(
                          id: 'home',
                          icon: Icons.home_outlined,
                          label: '首页',
                          onTap: widget.bus.onOpenHome,
                        ),
                        ..._nav(
                          id: 'new_article',
                          icon: Icons.add_circle_outline,
                          label: '新建文章',
                          onTap: widget.bus.onNewArticle,
                          isPrimary: true,
                          shortcut: 'Ctrl+N',
                        ),
                        ..._nav(
                          id: 'drafts',
                          icon: Icons.drafts_outlined,
                          label: '草稿箱',
                          onTap: widget.bus.onOpenDrafts,
                          badge: widget.drafts
                              .where((d) => !d.published)
                              .length,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // 文章（平铺标题列表，仿 Notion 内嵌，可折叠）
                    _buildSection(
                      key: 'articles',
                      title: '文章',
                      icon: Icons.article_outlined,
                      collapsed: _collapsedSections.contains('articles'),
                      onToggle: () => _toggleSection('articles'),
                      children: _buildArticleItems(),
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
                        ...widget.repos.map(
                          (r) => _siteItem(
                            name: r.name,
                            subtitle: r.fullName,
                            icon: r.isDefault
                                ? Icons.star
                                : Icons.hexagon_outlined,
                            isDefault: r.isDefault,
                            isActive: false,
                            onTap: () => widget.bus.onSiteChange?.call(r),
                          ),
                        ),
                        ...widget.siteManager.dynamicSites.map(
                          (s) => _siteItem(
                            name: s.name,
                            subtitle: s.siteUrl,
                            icon: Icons.language,
                            isActive: false,
                            onTap: () {
                              // 动态站点点击：打开站点管理
                              widget.bus.onShowBlogSiteManager();
                            },
                          ),
                        ),
                        _navItem(
                          icon: Icons.add,
                          label: '添加站点',
                          onTap: widget.bus.onShowSiteEditor,
                          isSubtle: true,
                        ),
                        _navItem(
                          icon: Icons.monitor_heart_outlined,
                          label: '运维与监控',
                          onTap: widget.bus.onShowSiteOperations,
                          isSubtle: true,
                        ),
                      ],
                    ),
                    _buildSection(
                      key: 'manage',
                      title: '管理',
                      icon: Icons.settings,
                      collapsed: _collapsedSections.contains('manage'),
                      onToggle: () => _toggleSection('manage'),
                      children: [
                        ..._nav(
                          id: 'remote_posts',
                          icon: Icons.cloud_outlined,
                          label: '远程文章',
                          onTap: widget.bus.onOpenRemote,
                        ),
                        ..._nav(
                          id: 'sync_status',
                          icon: Icons.sync,
                          label: '同步状态',
                          onTap: widget.bus.onOpenSync,
                        ),
                        ..._nav(
                          id: 'dashboard',
                          icon: Icons.dashboard_outlined,
                          label: '仪表盘',
                          onTap: widget.bus.onOpenDashboard,
                        ),
                        ..._nav(
                          id: 'history',
                          icon: Icons.history_outlined,
                          label: '提交历史',
                          onTap: widget.bus.onOpenHistory,
                        ),
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
                        ..._nav(
                          id: 'batch_upload',
                          icon: Icons.drive_folder_upload,
                          label: '批量上传',
                          onTap: widget.bus.onOpenBatchUpload,
                        ),
                        ..._nav(
                          id: 'preview',
                          icon: Icons.language,
                          label: '网站预览',
                          onTap: widget.bus.onOpenPreview,
                        ),
                        ..._nav(
                          id: 'rss',
                          icon: Icons.rss_feed_outlined,
                          label: 'RSS 订阅',
                          onTap: widget.bus.onOpenRss,
                        ),
                        ..._nav(
                          id: 'template_manager',
                          icon: Icons.view_quilt_outlined,
                          label: '模板管理',
                          onTap: widget.bus.onShowTemplateManager,
                        ),
                        ..._nav(
                          id: 'snippets',
                          icon: Icons.content_paste,
                          label: '片段素材库',
                          onTap: widget.bus.onShowSnippetManager,
                        ),
                        ..._nav(
                          id: 'config_editor',
                          icon: Icons.settings_applications,
                          label: '配置编辑器',
                          onTap: widget.bus.onShowConfigEditor,
                        ),
                        ..._nav(
                          id: 'theme_migration',
                          icon: Icons.swap_horiz,
                          label: 'AI 批量迁移',
                          onTap: widget.bus.onOpenThemeMigration,
                        ),
                        ..._nav(
                          id: 'image_bed',
                          icon: Icons.photo_library_outlined,
                          label: '图床管理',
                          onTap: widget.bus.onOpenImageBedManager,
                        ),
                        ..._nav(
                          id: 'link_checker',
                          icon: Icons.link_off,
                          label: '链接检测',
                          onTap: widget.bus.onOpenLinkChecker,
                        ),
                        ..._nav(
                          id: 'batch_tools',
                          icon: Icons.build_circle,
                          label: '批量工具箱',
                          onTap: widget.bus.onOpenBatchTools,
                        ),
                        ..._nav(
                          id: 'content_stats',
                          icon: Icons.insights_outlined,
                          label: '内容统计',
                          onTap: widget.bus.onShowContentStats,
                        ),
                        ..._nav(
                          id: 'backup_restore',
                          icon: Icons.settings_backup_restore,
                          label: '备份与恢复',
                          onTap: widget.bus.onShowBackupRestore,
                        ),
                        ..._nav(
                          id: 'proxy_settings',
                          icon: Icons.vpn_lock_outlined,
                          label: '代理设置',
                          onTap: widget.bus.onOpenProxySettings,
                        ),
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
                        ..._nav(
                          id: 'agent_workbench',
                          icon: Icons.assistant_direction_outlined,
                          label: 'Agent 工作台',
                          onTap: widget.bus.onShowAgentWorkbench,
                        ),
                        ..._nav(
                          id: 'theme_store',
                          icon: Icons.store_outlined,
                          label: '主题商店',
                          onTap: widget.bus.onShowThemeStore,
                        ),
                        ..._nav(
                          id: 'ai_model_manager',
                          icon: Icons.psychology_outlined,
                          label: 'AI 模型管理',
                          onTap: widget.bus.onShowAiModelManager,
                        ),
                        ..._nav(
                          id: 'ai_prompt_templates',
                          icon: Icons.text_snippet_outlined,
                          label: 'AI 提示词模板',
                          onTap: widget.bus.onOpenAiPromptTemplates,
                        ),
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
                        ..._nav(
                          id: 'cloud_sync',
                          icon: Icons.cloud_sync,
                          label: '云同步',
                          onTap: widget.bus.onOpenSyncSettings,
                        ),
                        ..._nav(
                          id: 'p2p_sync',
                          icon: Icons.wifi,
                          label: 'P2P 同步',
                          onTap: widget.bus.onOpenP2PSync,
                        ),
                        ..._nav(
                          id: 'settings',
                          icon: Icons.settings_outlined,
                          label: '设置',
                          onTap: widget.bus.onOpenSettings,
                        ),
                        ..._nav(
                          id: 'logs',
                          icon: Icons.history,
                          label: '操作日志',
                          onTap: widget.bus.onOpenLogs,
                        ),
                        ..._nav(
                          id: 'recycle_bin',
                          icon: Icons.delete_outline,
                          label: '回收站',
                          onTap: widget.bus.onOpenRecycleBin,
                        ),
                        ..._nav(
                          id: 'cache_cleanup',
                          icon: Icons.cleaning_services_outlined,
                          label: '缓存清理',
                          onTap: widget.bus.onOpenCacheCleanup,
                        ),
                        ..._nav(
                          id: 'export_logs',
                          icon: Icons.bug_report_outlined,
                          label: '导出日志',
                          onTap: widget.bus.onExportLogs,
                        ),
                        ..._nav(
                          id: 'blog_site_manager',
                          icon: Icons.dns_outlined,
                          label: '动态博客登录',
                          onTap: widget.bus.onShowBlogSiteManager,
                        ),
                        ..._nav(
                          id: 'site_manager',
                          icon: Icons.storage_outlined,
                          label: '站点管理',
                          onTap: widget.bus.onShowSiteEditor,
                        ),
                        ..._nav(
                          id: 'help',
                          icon: Icons.help_outline,
                          label: '帮助 / 快捷键',
                          onTap: widget.bus.onShowHelp,
                        ),
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
          Text(
            '拓墨',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
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
    // 简易模式下分组内无可见项时整组隐藏
    if (children.isEmpty) return const SizedBox.shrink();
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
  /// 按入口 id 过滤后展开导航项（简易模式下隐藏专业入口）
  List<Widget> _nav({
    required String id,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
    bool isSubtle = false,
    String? shortcut,
    int badge = 0,
  }) {
    final visible = NavEntries.visibleEntry(
      id,
      widget.mode,
      widget.simpleModeExtras,
    );
    if (!visible) return const [];
    return [
      _navItem(
        icon: icon,
        label: label,
        onTap: onTap,
        isPrimary: isPrimary,
        isSubtle: isSubtle,
        shortcut: shortcut,
        badge: badge,
      ),
    ];
  }

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
                      ? (isDark
                            ? Colors.white.withOpacity(0.35)
                            : const Color(0xFF9CA3AF))
                      : (isDark
                            ? Colors.white.withOpacity(0.6)
                            : const Color(0xFF4B5563)),
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
                          : (isDark
                                ? Colors.white.withOpacity(0.8)
                                : const Color(0xFF374151)),
                    ),
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
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
                      color: isDark
                          ? Colors.white.withOpacity(0.2)
                          : const Color(0xFFD1D5DB),
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
  // 文章列表（平铺标题，点击打开，长按管理）
  // ============================================================
  List<Widget> _buildArticleItems() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final articles = widget.drafts.where((a) {
      final name = a.title.trim();
      if (SystemLogFiles.isSystemLogFileName(name)) return false;
      final fn = a.fileName();
      if (SystemLogFiles.isSystemLogFileName(fn)) return false;
      return true;
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (articles.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            '暂无文章',
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? Colors.white.withOpacity(0.3)
                  : const Color(0xFF9CA3AF),
            ),
          ),
        ),
      ];
    }

    return articles.map((a) => _articleItem(a)).toList();
  }

  Widget _articleItem(Article a) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => widget.bus.onOpenArticle?.call(a),
          onLongPress: (a.volume == null || a.volume!.trim().isEmpty)
              ? null
              : () => _showArticleMenu(a),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 13,
                  color: isDark
                      ? Colors.white.withOpacity(0.35)
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.title.isEmpty ? '(无标题)' : a.title,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white.withOpacity(0.75)
                          : const Color(0xFF374151),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showArticleMenu(Article a) async {
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final bus = widget.bus;
    await showArticleActionMenu(
      context: context,
      anchor: anchor,
      article: a,
      onRename: bus.onRenameArticle,
      onMoveVolume: bus.onMoveArticleVolume,
      onExport: bus.onExportArticle,
      onDelete: bus.onDeleteArticle,
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
            ? (isDark
                  ? Colors.white.withOpacity(0.08)
                  : cs.primary.withOpacity(0.08))
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
                      : (isDark
                            ? Colors.white.withOpacity(0.5)
                            : const Color(0xFF6B7280)),
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
                          color: isDark
                              ? Colors.white.withOpacity(0.85)
                              : const Color(0xFF374151),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? Colors.white.withOpacity(0.35)
                                : const Color(0xFF9CA3AF),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
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
    // 持久化折叠状态（保持上次状态）
    widget.onCollapsedSectionsChanged?.call(
      _collapsedSections.toList()..sort(),
    );
  }
}
