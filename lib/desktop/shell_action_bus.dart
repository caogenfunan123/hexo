/// 桌面版 Shell 统一回调总线
///
/// 消除原先 37+ 个回调参数层层传递的"回调地狱"。
/// 所有桌面组件（LeftPanel、TitleBar、RightDrawer、EditorArea、StatusBar）
/// 共享同一个 ShellActionBus 实例，通过方法引用而非独立参数传递回调。
library;

import 'package:flutter/material.dart';
import '../models/repo_config.dart';
import '../models/article.dart';

/// 桌面 Shell 统一操作总线
///
/// 将原本分散在 DesktopLeftPanel（37 个）、DesktopTitleBar（12 个）、
/// DesktopEditorArea（6 个）、DesktopStatusBar（2 个）的回调参数
/// 统一收口到一个对象中，消除参数层层传递。
///
/// ## 新增功能入口的固定清单（四处必须同步，缺一即功能失效）
///
/// 1. `lib/desktop/feature_entries.dart` — 注册入口 id 与可见性
///    （shown/hidden/optIn）；
/// 2. `lib/desktop/nav_entries_meta.dart` — `kNavEntries` 加展示定义
///    （图标/文案/分组），**并在 `navEntryAction` 加 id → 回调映射**
///    （漏加此处的典型症状：全部功能 Hub 卡片呈灰色不可点）；
/// 3. 本类 — 新增回调字段并在构造参数声明；
/// 4. `desktop_shell.dart` 的 `_bus` 构造处 — 接上具体的处理方法。
class ShellActionBus {
  // ── 导航：文章管理 ──
  final VoidCallback onNewArticle;
  final VoidCallback onOpenDrafts;
  final VoidCallback onOpenRemote;
  final VoidCallback onOpenBatchUpload;
  final VoidCallback onOpenPreview;

  // ── 导航：首页 ──
  final VoidCallback onOpenHome;

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
  final VoidCallback onShowContentStats;
  final VoidCallback onShowBackupRestore;

  // ── 导航：AI ──
  final VoidCallback onShowAgentWorkbench;
  final VoidCallback onShowThemeStore;
  final VoidCallback onShowAiModelManager;
  final VoidCallback onShowAiTemplateChat;
  final VoidCallback onShowToolLibrary;

  // ── 导航：站点 ──
  final VoidCallback onShowBlogSiteManager;
  final VoidCallback onShowSiteEditor;
  final VoidCallback onShowSiteOperations;
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
  final VoidCallback? onOpenFileZone;

  // ── 侧边栏自定义 & 全部功能 ──
  final VoidCallback? onOpenAllFeatures;
  final VoidCallback? onOpenCustomizeSidebar;

  // ── 文章管理（侧边栏 / 首页长按操作） ──
  final ValueChanged<Article>? onOpenArticle;
  final ValueChanged<Article>? onRenameArticle;
  final ValueChanged<Article>? onMoveArticleVolume;
  final ValueChanged<Article>? onExportArticle;
  final ValueChanged<Article>? onDeleteArticle;

  const ShellActionBus({
    // 导航
    required this.onNewArticle,
    required this.onOpenDrafts,
    required this.onOpenRemote,
    required this.onOpenBatchUpload,
    required this.onOpenPreview,
    required this.onOpenHome,
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
    required this.onShowContentStats,
    required this.onShowBackupRestore,
    required this.onShowAgentWorkbench,
    required this.onShowThemeStore,
    required this.onShowAiModelManager,
    required this.onShowAiTemplateChat,
    required this.onShowToolLibrary,
    required this.onShowBlogSiteManager,
    required this.onShowSiteEditor,
    required this.onShowSiteOperations,
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
    this.onOpenFileZone,
    // 侧边栏自定义 & 全部功能
    this.onOpenAllFeatures,
    this.onOpenCustomizeSidebar,
    // 文章管理
    this.onOpenArticle,
    this.onRenameArticle,
    this.onMoveArticleVolume,
    this.onExportArticle,
    this.onDeleteArticle,
  });
}
