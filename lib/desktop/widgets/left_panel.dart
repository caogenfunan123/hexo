/// 左侧导航面板
/// 复刻手机版侧边栏全部菜单项：
/// 创作（新建文章、草稿箱）、管理（远程文章、同步状态、仪表盘、提交历史）、
/// 工具（批量上传、网站预览、RSS订阅、模板管理、片段素材库、配置编辑器、AI批量迁移）、
/// AI工具（AI博文创作、AI页面创作、AI主题开发、AI主题迁移、AI站点巡检、AI模型管理、工具库）、
/// 系统（云同步、设置、操作日志、动态博客登录、站点管理）
library;

import 'package:flutter/material.dart';
import '../../models/repo_config.dart';
import '../../models/article.dart';
import '../../core/site_manager.dart';

class DesktopLeftPanel extends StatelessWidget {
  final double width;
  final ValueChanged<double> onResize;
  final ValueChanged<String> onOpenDraft;
  final VoidCallback onCollapse;

  // ── 实时数据 ──
  final List<RepoConfig> repos;
  final List<Article> drafts;
  final SiteManager siteManager;

  // ── 导航回调 ──
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
  final VoidCallback onOpenImageBedManager;
  final VoidCallback onOpenProxySettings;
  final VoidCallback onOpenCacheCleanup;
  final VoidCallback onExportLogs;
  final VoidCallback onFixEncoding;
  final VoidCallback onToggleOfflineMode;
  final VoidCallback onToggleNightEye;
  final VoidCallback onOpenLinkChecker;
  final VoidCallback onOpenBatchTools;
  final VoidCallback onOpenAiPromptTemplates;

  const DesktopLeftPanel({
    super.key,
    required this.width,
    required this.onResize,
    required this.onOpenDraft,
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
    required this.onOpenImageBedManager,
    required this.onOpenProxySettings,
    required this.onOpenCacheCleanup,
    required this.onExportLogs,
    required this.onFixEncoding,
    required this.onToggleOfflineMode,
    required this.onToggleNightEye,
    required this.onOpenLinkChecker,
    required this.onOpenBatchTools,
    required this.onOpenAiPromptTemplates,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: width.clamp(200, 400),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.6),
        border: Border(right: BorderSide(color: cs.outlineVariant.withOpacity(0.2))),
      ),
      child: Column(
        children: [
          // 面板头部
          _panelHeader(cs),
          const Divider(height: 1),

          // 站点 & 导航列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                // ── 创作 ──
                _sectionHeader('创作', Icons.edit_square),
                _navButton(Icons.add, '新建文章', onNewArticle, cs, isPrimary: true),
                _navButton(Icons.drafts_outlined, '草稿箱', onOpenDrafts, cs,
                    badge: drafts.where((d) => !d.published).length),
                const SizedBox(height: 6),

                // ── 站点列表 ──
                _sectionHeader('站点', Icons.folder_outlined),
                ...repos.map((r) => _siteItem(r.name, Icons.hexagon_outlined, cs, onTap: () => onSiteChange?.call(r))).toList(),
                if (siteManager.dynamicSites.isNotEmpty)
                  ...siteManager.dynamicSites.map((s) => _siteItem(s.name, Icons.language, cs)).toList(),
                const SizedBox(height: 6),

                // ── 管理 ──
                _sectionHeader('管理', Icons.settings),
                _navButton(Icons.cloud_outlined, '远程文章', onOpenRemote, cs),
                _navButton(Icons.sync, '同步状态', onOpenSync, cs),
                _navButton(Icons.dashboard_outlined, '仪表盘', onOpenDashboard, cs),
                _navButton(Icons.history_outlined, '提交历史', onOpenHistory, cs),
                const SizedBox(height: 6),

                // ── 工具 ──
                _sectionHeader('工具', Icons.build_outlined),
                _navButton(Icons.drive_folder_upload, '批量上传', onOpenBatchUpload, cs),
                _navButton(Icons.language, '网站预览', onOpenPreview, cs),
                _navButton(Icons.rss_feed_outlined, 'RSS 订阅', onOpenRss, cs),
                _navAction(Icons.view_quilt_outlined, '模板管理', onShowTemplateManager, cs),
                _navAction(Icons.content_paste, '片段素材库', onShowSnippetManager, cs),
                _navAction(Icons.settings_applications, '配置编辑器', onShowConfigEditor, cs),
                _navAction(Icons.swap_horiz, 'AI批量迁移', onOpenThemeMigration, cs),
                _navAction(Icons.photo_library_outlined, '图床管理', onOpenImageBedManager, cs),
                _navAction(Icons.link_off, '链接检测', onOpenLinkChecker, cs),
                _navAction(Icons.build_circle, '批量工具箱', onOpenBatchTools, cs),
                _navAction(Icons.vpn_lock_outlined, '代理设置', onOpenProxySettings, cs),
                const SizedBox(height: 6),

                // ── AI 工具 ──
                _sectionHeader('AI 工具', Icons.auto_awesome),
                _navAction(Icons.article_outlined, 'AI 博文创作', onShowAiArticleChat, cs),
                _navAction(Icons.web_outlined, 'AI 页面创作', onShowAiPageChat, cs),
                _navAction(Icons.palette_outlined, 'AI 主题开发', onShowAiThemeChat, cs),
                _navAction(Icons.fact_check_outlined, 'AI 站点巡检', onShowAiAudit, cs),
                _navAction(Icons.psychology_outlined, 'AI 模型管理', onShowAiModelManager, cs),
                _navAction(Icons.build_outlined, '工具库', onShowToolLibrary, cs),
                _navAction(Icons.text_snippet_outlined, 'AI 提示词模板', onOpenAiPromptTemplates, cs),
                const SizedBox(height: 6),

                // ── 系统 ──
                _sectionHeader('系统', Icons.dns_outlined),
                _navButton(Icons.cloud_sync, '云同步', onOpenSyncSettings, cs),
                _navButton(Icons.settings_outlined, '设置', onOpenSettings, cs),
                _navButton(Icons.history, '操作日志', onOpenLogs, cs),
                _navButton(Icons.help_outline, '帮助 / 快捷键', onShowHelp, cs),
                _navButton(Icons.delete_outline, '回收站', onOpenRecycleBin, cs),
                _navButton(Icons.cleaning_services_outlined, '缓存清理', onOpenCacheCleanup, cs),
                _navButton(Icons.bug_report_outlined, '导出日志', onExportLogs, cs),
                _navAction(Icons.dns_outlined, '动态博客登录', onShowBlogSiteManager, cs),
                _navAction(Icons.storage_outlined, '站点管理', onShowSiteEditor, cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelHeader(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.auto_stories, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            'AI 博客编辑器',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.6), letterSpacing: 0.5),
          ),
          const Spacer(),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onCollapse,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.chevron_left, size: 16, color: cs.onSurface.withOpacity(0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade400),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade400, letterSpacing: 0.8)),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, String label, VoidCallback onTap, ColorScheme cs, {int badge = 0, bool isPrimary = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 17, color: isPrimary ? cs.primary : cs.onSurface.withOpacity(0.6)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 13, fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w400, color: cs.onSurface)),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: cs.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text('$badge', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navAction(IconData icon, String label, VoidCallback onTap, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 17, color: cs.onSurface.withOpacity(0.5)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8))),
                ),
                Icon(Icons.open_in_new, size: 12, color: cs.onSurface.withOpacity(0.25)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _siteItem(String name, IconData icon, ColorScheme cs, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: cs.primary.withOpacity(0.6)),
                const SizedBox(width: 10),
                Text(name, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}