/// 左侧面板动作通知器
/// 替代 left_panel.dart 中 43 个回调参数，统一由 ActionNotifier 管理
/// 对标：VS Code 的 IMenuService / ActionRegistry 模式
library;

import 'package:flutter/material.dart';

/// 面板动作类型
enum PanelAction {
  newArticle,
  openDrafts,
  openRemote,
  openSync,
  openDashboard,
  openHistory,
  openRss,
  openBatchUpload,
  openPreview,
  openSettings,
  openSyncSettings,
  openLogs,
  openThemeMigration,
  showTemplateManager,
  showSnippetManager,
  showConfigEditor,
  showAiArticleChat,
  showAiPageChat,
  showAiThemeChat,
  showAiAudit,
  showAiModelManager,
  showToolLibrary,
  showBlogSiteManager,
  showSiteEditor,
  showHelp,
  openRecycleBin,
  openImageBedManager,
  openProxySettings,
  openCacheCleanup,
  exportLogs,
  openLinkChecker,
  openBatchTools,
  openAiPromptTemplates,
}

/// 左侧面板动作通知器
/// 通过 ChangeNotifier 模式，left_panel 只需持有一个 ActionNotifier 引用
/// 替代原来的 43 个独立回调参数
class LeftPanelActionNotifier extends ChangeNotifier {
  final Map<PanelAction, VoidCallback> _actions = {};
  final Map<PanelAction, ValueChanged<dynamic>> _valueActions = {};

  /// 注册动作
  void register(PanelAction action, VoidCallback callback) {
    _actions[action] = callback;
  }

  /// 注册带参数的动作
  void registerValue<T>(PanelAction action, ValueChanged<T> callback) {
    _valueActions[action] = (dynamic v) => callback(v as T);
  }

  /// 触发动作
  void invoke(PanelAction action) {
    final callback = _actions[action];
    if (callback != null) {
      callback();
    }
  }

  /// 触发带参数的动作
  void invokeValue(PanelAction action, dynamic value) {
    final callback = _valueActions[action];
    if (callback != null) {
      callback(value);
    }
  }

  /// 批量注册常用动作
  void registerAll({
    VoidCallback? onNewArticle,
    VoidCallback? onOpenDrafts,
    VoidCallback? onOpenRemote,
    VoidCallback? onOpenSync,
    VoidCallback? onOpenDashboard,
    VoidCallback? onOpenHistory,
    VoidCallback? onOpenRss,
    VoidCallback? onOpenBatchUpload,
    VoidCallback? onOpenPreview,
    VoidCallback? onOpenSettings,
    VoidCallback? onOpenSyncSettings,
    VoidCallback? onOpenLogs,
    VoidCallback? onOpenThemeMigration,
    VoidCallback? onShowTemplateManager,
    VoidCallback? onShowSnippetManager,
    VoidCallback? onShowConfigEditor,
    VoidCallback? onShowAiArticleChat,
    VoidCallback? onShowAiPageChat,
    VoidCallback? onShowAiThemeChat,
    VoidCallback? onShowAiAudit,
    VoidCallback? onShowAiModelManager,
    VoidCallback? onShowToolLibrary,
    VoidCallback? onShowBlogSiteManager,
    VoidCallback? onShowSiteEditor,
    VoidCallback? onShowHelp,
    VoidCallback? onOpenRecycleBin,
    VoidCallback? onOpenImageBedManager,
    VoidCallback? onOpenProxySettings,
    VoidCallback? onOpenCacheCleanup,
    VoidCallback? onExportLogs,
    VoidCallback? onOpenLinkChecker,
    VoidCallback? onOpenBatchTools,
    VoidCallback? onOpenAiPromptTemplates,
  }) {
    _registerIfNotNull(PanelAction.newArticle, onNewArticle);
    _registerIfNotNull(PanelAction.openDrafts, onOpenDrafts);
    _registerIfNotNull(PanelAction.openRemote, onOpenRemote);
    _registerIfNotNull(PanelAction.openSync, onOpenSync);
    _registerIfNotNull(PanelAction.openDashboard, onOpenDashboard);
    _registerIfNotNull(PanelAction.openHistory, onOpenHistory);
    _registerIfNotNull(PanelAction.openRss, onOpenRss);
    _registerIfNotNull(PanelAction.openBatchUpload, onOpenBatchUpload);
    _registerIfNotNull(PanelAction.openPreview, onOpenPreview);
    _registerIfNotNull(PanelAction.openSettings, onOpenSettings);
    _registerIfNotNull(PanelAction.openSyncSettings, onOpenSyncSettings);
    _registerIfNotNull(PanelAction.openLogs, onOpenLogs);
    _registerIfNotNull(PanelAction.openThemeMigration, onOpenThemeMigration);
    _registerIfNotNull(PanelAction.showTemplateManager, onShowTemplateManager);
    _registerIfNotNull(PanelAction.showSnippetManager, onShowSnippetManager);
    _registerIfNotNull(PanelAction.showConfigEditor, onShowConfigEditor);
    _registerIfNotNull(PanelAction.showAiArticleChat, onShowAiArticleChat);
    _registerIfNotNull(PanelAction.showAiPageChat, onShowAiPageChat);
    _registerIfNotNull(PanelAction.showAiThemeChat, onShowAiThemeChat);
    _registerIfNotNull(PanelAction.showAiAudit, onShowAiAudit);
    _registerIfNotNull(PanelAction.showAiModelManager, onShowAiModelManager);
    _registerIfNotNull(PanelAction.showToolLibrary, onShowToolLibrary);
    _registerIfNotNull(PanelAction.showBlogSiteManager, onShowBlogSiteManager);
    _registerIfNotNull(PanelAction.showSiteEditor, onShowSiteEditor);
    _registerIfNotNull(PanelAction.showHelp, onShowHelp);
    _registerIfNotNull(PanelAction.openRecycleBin, onOpenRecycleBin);
    _registerIfNotNull(PanelAction.openImageBedManager, onOpenImageBedManager);
    _registerIfNotNull(PanelAction.openProxySettings, onOpenProxySettings);
    _registerIfNotNull(PanelAction.openCacheCleanup, onOpenCacheCleanup);
    _registerIfNotNull(PanelAction.exportLogs, onExportLogs);
    _registerIfNotNull(PanelAction.openLinkChecker, onOpenLinkChecker);
    _registerIfNotNull(PanelAction.openBatchTools, onOpenBatchTools);
    _registerIfNotNull(PanelAction.openAiPromptTemplates, onOpenAiPromptTemplates);
  }

  void _registerIfNotNull(PanelAction action, VoidCallback? callback) {
    if (callback != null) {
      _actions[action] = callback;
    }
  }

  /// 检查动作是否已注册
  bool hasAction(PanelAction action) => _actions.containsKey(action);
}