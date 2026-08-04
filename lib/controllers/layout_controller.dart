/// 布局控制器 — 统一管理桌面端和手机端的布局状态
///
/// 桌面端：左面板展开/宽度/折叠、右抽屉开关、工作模式切换、窗口布局记忆
/// 手机端：页面路由索引、侧边栏 Drawer、横竖屏自适应
library;

import 'package:flutter/material.dart';

/// 工作模式（桌面端专用）
enum WorkMode {
  workspace,
  focus,
  source,
}

/// 页面索引（手机端专用，与桌面端 RightDrawerTab 对应）
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
}

/// 右侧抽屉标签页（桌面端专用）
enum RightDrawerTab {
  outline,
  frontMatter,
  snippets,
  aiChat,
  syncLog,
}

/// 布局变化通知
enum LayoutChangeType {
  leftPanelToggled,
  leftPanelResized,
  rightDrawerToggled,
  rightDrawerTabChanged,
  workModeChanged,
  pageChanged,
  orientationChanged,
  collapsed,
}

class LayoutController extends ChangeNotifier {
  // ── 桌面端专用 ──
  bool _leftPanelExpanded = true;
  double _leftPanelWidth = 260;
  bool _rightDrawerOpen = false;
  RightDrawerTab _activeDrawerTab = RightDrawerTab.outline;
  WorkMode _workMode = WorkMode.workspace;

  // ── 手机端专用 ──
  int _currentPage = 0;
  Orientation _orientation = Orientation.portrait;

  // ── 通用 ──
  bool _isCollapsed = false;

  // ── Getters ──
  bool get leftPanelExpanded => _leftPanelExpanded;
  double get leftPanelWidth => _leftPanelWidth;
  bool get rightDrawerOpen => _rightDrawerOpen;
  RightDrawerTab get activeDrawerTab => _activeDrawerTab;
  WorkMode get workMode => _workMode;
  int get currentPage => _currentPage;
  Orientation get orientation => _orientation;
  bool get isCollapsed => _isCollapsed;

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
    _isCollapsed = true;
    notifyListeners();
  }

  void expandLeftPanel() {
    _leftPanelExpanded = true;
    _isCollapsed = false;
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

  // ── 手机端：页面切换 ──
  void navigateTo(int page) {
    if (page >= 0 && page < MobilePage.values.length) {
      _currentPage = page;
      notifyListeners();
    }
  }

  void navigateToPage(MobilePage page) {
    _currentPage = page.index;
    notifyListeners();
  }

  // ── 手机端：横竖屏 ──
  void updateOrientation(Orientation orientation) {
    if (_orientation != orientation) {
      _orientation = orientation;
      notifyListeners();
    }
  }

  // ── 通用 ──
  void toggleCollapse() {
    _isCollapsed = !_isCollapsed;
    notifyListeners();
  }
}