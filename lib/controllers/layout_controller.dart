/// 布局控制器 — 统一管理桌面端的布局状态
///
/// 桌面端：左面板展开/宽度/折叠、右抽屉开关、工作模式切换、窗口布局记忆。
/// 手机端页面路由由 main.dart 的 `_RootShellState` 自持（`_currentPage`），
/// 本控制器原移动端页面/横竖屏 API 因全仓零外部调用已删除
/// （2026-09 全量复盘，见 docs/fixes/codebase-review-2026-09-13.md）。
library;

import 'package:flutter/material.dart';

/// 工作模式（桌面端专用）
enum WorkMode {
  workspace,
  focus,
  source,
}

/// 页面索引（手机端专用，main.dart 侧路由用）
enum MobilePage {
  editor,       // 0
  drafts,       // 1
  remote,       // 2
  dashboard,    // 3
  rss,          // 4
  history,      // 5
  batchUpload,  // 6
  preview,      // 7
  settings,     // 8
  reader,       // 9
  themeMigrate, // 10
  logs,         // 11
  sync,         // 12
  cloudSync,    // 13
  home,         // 14 首页（卷宗文章列表，简易模式默认页）
}

/// 右侧抽屉标签页（桌面端专用）
enum RightDrawerTab {
  outline,
  frontMatter,
  snippets,
  aiChat,
  syncLog,
}

class LayoutController extends ChangeNotifier {
  // ── 桌面端专用 ──
  // 阶段1（界面改版）：左栏默认隐藏，写作即全部界面；
  // 用户展开后经 UiSettings.leftPanelExpanded 记住偏好
  bool _leftPanelExpanded = false;
  double _leftPanelWidth = 260;
  bool _rightDrawerOpen = false;
  RightDrawerTab _activeDrawerTab = RightDrawerTab.outline;
  WorkMode _workMode = WorkMode.workspace;

  // ── Getters ──
  bool get leftPanelExpanded => _leftPanelExpanded;
  double get leftPanelWidth => _leftPanelWidth;
  bool get rightDrawerOpen => _rightDrawerOpen;
  RightDrawerTab get activeDrawerTab => _activeDrawerTab;
  WorkMode get workMode => _workMode;

  // ── 桌面端：左面板 ──
  void toggleLeftPanel() {
    _leftPanelExpanded = !_leftPanelExpanded;
    notifyListeners();
  }

  void setLeftPanelWidth(double width) {
    _leftPanelWidth = width.clamp(200, 400);
    notifyListeners();
  }

  void collapseLeftPanel() {
    _leftPanelExpanded = false;
    notifyListeners();
  }

  void expandLeftPanel() {
    _leftPanelExpanded = true;
    notifyListeners();
  }

  // ── 桌面端：右抽屉 ──
  void toggleRightDrawer() {
    _rightDrawerOpen = !_rightDrawerOpen;
    notifyListeners();
  }

  void openRightDrawer([RightDrawerTab tab = RightDrawerTab.outline]) {
    _rightDrawerOpen = true;
    _activeDrawerTab = tab;
    notifyListeners();
  }

  void closeRightDrawer() {
    _rightDrawerOpen = false;
    notifyListeners();
  }

  void setDrawerTab(RightDrawerTab tab) {
    _activeDrawerTab = tab;
    notifyListeners();
  }

  // ── 桌面端：工作模式 ──
  void switchWorkMode(WorkMode mode) {
    _workMode = mode;
    notifyListeners();
  }
}
