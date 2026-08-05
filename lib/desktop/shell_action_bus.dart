/// 桌面版 Shell 统一回调总线
///
/// 消除原先 37+ 个回调参数层层传递的"回调地狱"。
/// 所有桌面组件（LeftPanel、TitleBar、RightDrawer、EditorArea、StatusBar）
/// 共享同一个 ShellActionBus 实例，通过方法引用而非独立参数传递回调。
library;

import 'package:flutter/material.dart';
import '../models/repo_config.dart';

/// 桌面 Shell 统一操作总线
///
/// 将原本分散在 DesktopLeftPanel（37 个）、DesktopTitleBar（12 个）、
/// DesktopEditorArea（6 个）、DesktopStatusBar（2 个）的回调参数
/// 统一收口到一个对象中，消除参数层层传递。
class ShellActionBus {
  // ── 导航：文章管理 ──
  final VoidCallback onNewArticle;
  final VoidCallback onOpenDrafts;
  final VoidCallback onOpenRemote;
  final VoidCallback onOpenBatchUpload;
  final VoidCallback onOpenPreview;

  // ── 导航：工具 & 设置 ──
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenSyncSettings;
  final VoidCallback onOpenLogs;
  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenRss;
  final VoidCallback onOpenSync;

  // ── 导航：高级功能 ──
  final VoidCallback onOpenThemeMigration;
  final VoidCallback onShowTemplateManager;
  final VoidCallback onShowSnippetManager;
  final VoidCallback onShowConfigEditor;
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

  // ── 导航：AI ──
  final VoidCallback onShowAiArticleChat;
  final VoidCallback onShowAiPageChat;
  final VoidCallback onShowAiThemeChat;
  final VoidCallback onShowAiAudit;
  final VoidCallback onShowAiAppDesign;
  final VoidCallback onShowAiModelManager;
  final VoidCallback onShowToolLibrary;

  // ── 导航：站点 ──
  final VoidCallback onShowBlogSiteManager;
  final VoidCallback onShowSiteEditor;
  final ValueChanged<RepoConfig>? onSiteChange;

  // ── 布局 ──
  final VoidCallback onToggleLeftPanel;
  final VoidCallback onToggleRightDrawer;
  final VoidCallback onThemeToggle;

  // ── 同步 & 发布 ──
  final VoidCallback onSync;
  final VoidCallback onPublish;

  // ── 文件操作 ──
  final VoidCallback? onOpenFile;

  const ShellActionBus({
    // 导航
    required this.onNewArticle,
    required this.onOpenDrafts,
    required this.onOpenRemote,
    required this.onOpenBatchUpload,
    required this.onOpenPreview,
    required this.onOpenSettings,
    required this.onOpenSyncSettings,
    required this.onOpenLogs,
    required this.onOpenDashboard,
    required this.onOpenHistory,
    required this.onOpenRss,
    required this.onOpenSync,
    required this.onOpenThemeMigration,
    required this.onShowTemplateManager,
    required this.onShowSnippetManager,
    required this.onShowConfigEditor,
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
    required this.onShowAiArticleChat,
    required this.onShowAiPageChat,
    required this.onShowAiThemeChat,
    required this.onShowAiAudit,
    required this.onShowAiAppDesign,
    required this.onShowAiModelManager,
    required this.onShowToolLibrary,
    required this.onShowBlogSiteManager,
    required this.onShowSiteEditor,
    this.onSiteChange,
    // 布局
    required this.onToggleLeftPanel,
    required this.onToggleRightDrawer,
    required this.onThemeToggle,
    // 同步 & 发布
    required this.onSync,
    required this.onPublish,
    // 文件操作
    this.onOpenFile,
  });
}