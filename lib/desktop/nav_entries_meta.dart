/// 侧边栏入口展示元数据与动作映射（供置顶区/全部功能 Hub/自定义对话框共用）
library;

import 'package:flutter/material.dart';
import 'shell_action_bus.dart';

/// 入口展示定义
class NavEntryDef {
  final String id;
  final IconData icon;
  final String label;
  final String group;

  const NavEntryDef(this.id, this.icon, this.label, this.group);
}

/// 入口分组顺序
const List<String> kNavGroups = ['创作', '站点', '管理', '工具', 'AI 工具', '系统'];

/// 全部入口展示定义（id 与 feature_entries.dart 注册表保持一致）
const List<NavEntryDef> kNavEntries = [
  // 创作
  NavEntryDef('home', Icons.home_outlined, '首页', '创作'),
  NavEntryDef('new_article', Icons.add_circle_outline, '新建文章', '创作'),
  NavEntryDef('drafts', Icons.drafts_outlined, '草稿箱', '创作'),
  NavEntryDef('create_site', Icons.rocket_launch_outlined, '一键建站', '创作'),
  // 站点
  NavEntryDef('site_manager', Icons.storage_outlined, '站点管理', '站点'),
  NavEntryDef('add_site', Icons.add, '添加站点', '站点'),
  NavEntryDef('site_operations', Icons.monitor_heart_outlined, '运维与监控', '站点'),
  NavEntryDef('blog_site_manager', Icons.dns_outlined, '动态博客登录', '站点'),
  // 管理
  NavEntryDef('cloud_sync', Icons.cloud_sync, '同步中心', '管理'),
  NavEntryDef('p2p_sync', Icons.wifi, 'P2P 同步', '管理'),
  NavEntryDef('remote_posts', Icons.cloud_outlined, '远程文章', '管理'),
  NavEntryDef('sync_status', Icons.sync, '同步状态', '管理'),
  NavEntryDef('history', Icons.history_outlined, '提交历史', '管理'),
  NavEntryDef('dashboard', Icons.dashboard_outlined, '仪表盘', '管理'),
  // 工具
  NavEntryDef('batch_upload', Icons.drive_folder_upload, '批量上传', '工具'),
  NavEntryDef('preview', Icons.language, '网站预览', '工具'),
  NavEntryDef('rss', Icons.rss_feed_outlined, 'RSS 订阅', '工具'),
  NavEntryDef('template_manager', Icons.view_quilt_outlined, '模板管理', '工具'),
  NavEntryDef('snippets', Icons.content_paste, '片段素材库', '工具'),
  NavEntryDef('config_editor', Icons.settings_applications, '配置编辑器', '工具'),
  NavEntryDef('theme_migration', Icons.swap_horiz, 'AI 批量迁移', '工具'),
  NavEntryDef('image_bed', Icons.photo_library_outlined, '图床管理', '工具'),
  NavEntryDef('link_checker', Icons.link_off, '链接检测', '工具'),
  NavEntryDef('batch_tools', Icons.build_circle, '批量工具箱', '工具'),
  NavEntryDef('content_stats', Icons.insights_outlined, '内容统计', '工具'),
  NavEntryDef('backup_restore', Icons.settings_backup_restore, '备份与恢复', '工具'),
  NavEntryDef('local_file_zone', Icons.folder_open_outlined, '本地文件区', '工具'),
  NavEntryDef('proxy_settings', Icons.vpn_lock_outlined, '代理设置', '工具'),
  // AI 工具
  NavEntryDef('agent_workbench', Icons.assistant_direction_outlined, 'Agent 工作台', 'AI 工具'),
  NavEntryDef('theme_store', Icons.store_outlined, '主题商店', 'AI 工具'),
  NavEntryDef('ai_model_manager', Icons.psychology_outlined, 'AI 模型管理', 'AI 工具'),
  NavEntryDef('ai_prompt_templates', Icons.text_snippet_outlined, 'AI 提示词模板', 'AI 工具'),
  NavEntryDef('ai_template_chat', Icons.forum_outlined, 'AI 模板对话', 'AI 工具'),
  NavEntryDef('tool_library', Icons.handyman_outlined, '工具库', 'AI 工具'),
  // 系统
  NavEntryDef('settings', Icons.settings_outlined, '设置', '系统'),
  NavEntryDef('logs', Icons.history, '操作日志', '系统'),
  NavEntryDef('recycle_bin', Icons.delete_outline, '回收站', '系统'),
  NavEntryDef('cache_cleanup', Icons.cleaning_services_outlined, '缓存清理', '系统'),
  NavEntryDef('export_logs', Icons.bug_report_outlined, '导出日志', '系统'),
  NavEntryDef('help', Icons.help_outline, '帮助 / 快捷键', '系统'),
];

/// id → 定义
NavEntryDef? navEntryById(String id) {
  for (final e in kNavEntries) {
    if (e.id == id) return e;
  }
  return null;
}

/// 入口 id → 动作回调（置顶项与 Hub 点击）
VoidCallback? navEntryAction(ShellActionBus bus, String id) {
  return switch (id) {
    'home' => bus.onOpenHome,
    'new_article' => bus.onNewArticle,
    'drafts' => bus.onOpenDrafts,
    'cloud_sync' => bus.onOpenSyncSettings,
    'p2p_sync' => bus.onOpenP2PSync,
    'site_manager' => bus.onShowSiteEditor,
    'add_site' => bus.onShowSiteEditor,
    'remote_posts' => bus.onOpenRemote,
    'sync_status' => bus.onOpenSync,
    'history' => bus.onOpenHistory,
    'batch_upload' => bus.onOpenBatchUpload,
    'preview' => bus.onOpenPreview,
    'rss' => bus.onOpenRss,
    'template_manager' => bus.onShowTemplateManager,
    'snippets' => bus.onShowSnippetManager,
    'config_editor' => bus.onShowConfigEditor,
    'theme_migration' => bus.onOpenThemeMigration,
    'image_bed' => bus.onOpenImageBedManager,
    'link_checker' => bus.onOpenLinkChecker,
    'batch_tools' => bus.onOpenBatchTools,
    'content_stats' => bus.onShowContentStats,
    'backup_restore' => bus.onShowBackupRestore,
    'local_file_zone' => bus.onOpenFileZone,
    'proxy_settings' => bus.onOpenProxySettings,
    'agent_workbench' => bus.onShowAgentWorkbench,
    'theme_store' => bus.onShowThemeStore,
    'ai_model_manager' => bus.onShowAiModelManager,
    'ai_template_chat' => bus.onShowAiTemplateChat,
    'ai_prompt_templates' => bus.onOpenAiPromptTemplates,
    'tool_library' => bus.onShowToolLibrary,
    'help' => bus.onShowHelp,
    'settings' => bus.onOpenSettings,
    'logs' => bus.onOpenLogs,
    'recycle_bin' => bus.onOpenRecycleBin,
    'cache_cleanup' => bus.onOpenCacheCleanup,
    'export_logs' => bus.onExportLogs,
    'blog_site_manager' => bus.onShowBlogSiteManager,
    'site_operations' => bus.onShowSiteOperations,
    'create_site' => bus.onShowSiteEditor,
    'dashboard' => bus.onOpenDashboard,
    'all_features' => bus.onOpenAllFeatures,
    _ => null,
  };
}