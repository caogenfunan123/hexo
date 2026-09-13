/// 编辑器视图状态控制器 — 管理 UI 交互状态和视觉配置
///
/// 对标：super_editor 的 Composer（选择/光标/交互状态）
/// 参考：VS Code ViewModel（视图状态与数据分离）
///
/// 职责：
/// - 标签页管理（openTabs, activeTabIndex）
/// - 光标位置和选择状态（CursorPosition）
/// - 编辑器统计（字数、字符数）
/// - 编辑器外观配置（字体、行高、主题、CSS）
/// - 编辑器忙碌/状态标志
/// - 图片路径模式
///
/// 保存不在本控制器：草稿落盘走 shell 自动保存链路（防抖 + 会话快照 + flushAllPendingSaves），
/// 数据层（DocumentController 管理）：
/// - 文章内容 TextEditingController → DocumentController
/// - Article 数据模型 → DocumentController
/// - 草稿/模板列表 → DocumentController
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 编辑器标签页数据模型
class EditorTab {
  final String id;
  final String title;
  final IconData icon;
  final bool canClose;
  final String contentKey;
  final WidgetBuilder? contentBuilder;

  const EditorTab({
    required this.id,
    required this.title,
    this.icon = Icons.article_outlined,
    this.canClose = true,
    this.contentKey = '',
    this.contentBuilder,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorTab && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 光标位置
class CursorPosition {
  final int line;
  final int column;
  final int totalLines;
  const CursorPosition({required this.line, required this.column, this.totalLines = 0});

  @override
  String toString() => '行 $line 列 $column';
}

class EditorController extends ChangeNotifier {
  // ── 标签页 ──
  final List<EditorTab> _openTabs = [];
  int _activeTabIndex = 0;

  // ── 光标/选择状态 ──
  CursorPosition _cursorPos = const CursorPosition(line: 1, column: 1);

  // ── 编辑器统计 ──
  int _wordCount = 0;
  int _charCount = 0;

  // ── 编辑器外观配置 ──
  double _editorFontSize = 16.0;
  double _editorLineHeight = 1.6;
  String _editorFontFamily = 'System';
  String _editorTheme = 'default';
  String _customCss = '';
  Map<String, String> _customShortcuts = {};

  // ── 编辑器忙碌状态 ──
  bool _editorBusy = false;
  String? _editorStatus;

  // ── 图片 ──
  Uint8List? _failedImageBytes;
  bool _useRelativeImagePath = false;

  // ── Getters: 标签页 ──
  List<EditorTab> get openTabs => List.unmodifiable(_openTabs);
  int get activeTabIndex => _activeTabIndex;
  EditorTab? get activeTab =>
      _openTabs.isNotEmpty && _activeTabIndex < _openTabs.length
          ? _openTabs[_activeTabIndex]
          : null;

  // ── Getters: 光标 ──
  CursorPosition get cursorPos => _cursorPos;

  // ── Getters: 统计 ──
  int get wordCount => _wordCount;
  int get charCount => _charCount;

  // ── Getters: 外观 ──
  double get editorFontSize => _editorFontSize;
  double get editorLineHeight => _editorLineHeight;
  String get editorFontFamily => _editorFontFamily;
  String get editorTheme => _editorTheme;
  String get customCss => _customCss;
  Map<String, String> get customShortcuts => Map.unmodifiable(_customShortcuts);

  // ── Getters: 忙碌 ──
  bool get editorBusy => _editorBusy;
  String? get editorStatus => _editorStatus;

  // ── Getters: 图片 ──
  Uint8List? get failedImageBytes => _failedImageBytes;
  bool get useRelativeImagePath => _useRelativeImagePath;

  // ── 标签页管理 ──
  void addTab(EditorTab tab) {
    final existingIndex = _openTabs.indexWhere((t) => t.id == tab.id);
    if (existingIndex >= 0) {
      _activeTabIndex = existingIndex;
      notifyListeners();
      return;
    }
    _openTabs.add(tab);
    _activeTabIndex = _openTabs.length - 1;
    notifyListeners();
  }

  void switchTab(int index) {
    if (index >= 0 && index < _openTabs.length) {
      _activeTabIndex = index;
      notifyListeners();
    }
  }

  /// 更新指定标签的标题（标题栏/标签栏同步用）
  void updateTabTitle(String id, String title) {
    final index = _openTabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final t = _openTabs[index];
    if (t.title == title) return;
    _openTabs[index] = EditorTab(
      id: t.id,
      title: title,
      icon: t.icon,
      canClose: t.canClose,
      contentKey: t.contentKey,
      contentBuilder: t.contentBuilder,
    );
    notifyListeners();
  }

  void closeTab(int index) {
    if (index >= 0 && index < _openTabs.length) {
      _openTabs.removeAt(index);
      if (_openTabs.isEmpty) {
        _activeTabIndex = 0;
      } else if (index < _activeTabIndex) {
        // 关闭的是激活标签左侧的标签，激活索引需左移保持指向同一标签
        _activeTabIndex--;
      } else if (_activeTabIndex >= _openTabs.length) {
        _activeTabIndex = _openTabs.length - 1;
      }
      notifyListeners();
    }
  }

  void closeAllTabs() {
    _openTabs.clear();
    _activeTabIndex = 0;
    notifyListeners();
  }

  // ── 光标 ──
  void updateCursorPosition(int line, int column, {int totalLines = 0}) {
    _cursorPos = CursorPosition(line: line, column: column, totalLines: totalLines);
    notifyListeners();
  }

  // ── 统计 ──
  // 内容哈希防抖：光标移动/无键帧重复调用不重复 notify，状态栏只在内容真正变化时重建
  int _lastStatsHash = 0;

  void updateStats(String content) {
    final h = content.hashCode;
    if (h == _lastStatsHash) return;
    _lastStatsHash = h;
    _charCount = content.length;
    _wordCount = content.isEmpty
        ? 0
        : content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    notifyListeners();
  }

  // ── 外观配置 ──
  void setEditorFontSize(double size) {
    _editorFontSize = size.clamp(12, 32);
    notifyListeners();
  }

  void setEditorLineHeight(double height) {
    _editorLineHeight = height.clamp(1.2, 2.5);
    notifyListeners();
  }

  void setEditorFontFamily(String family) {
    _editorFontFamily = family;
    notifyListeners();
  }

  void setEditorTheme(String theme) {
    _editorTheme = theme;
    notifyListeners();
  }

  void setCustomCss(String css) {
    _customCss = css;
    notifyListeners();
  }

  void setCustomShortcuts(Map<String, String> shortcuts) {
    _customShortcuts = Map<String, String>.from(shortcuts);
    notifyListeners();
  }

  /// 更新单个快捷键绑定
  void setCustomShortcut(String action, String shortcut) {
    final updated = Map<String, String>.from(_customShortcuts);
    if (shortcut.isEmpty) {
      updated.remove(action);
    } else {
      updated[action] = shortcut;
    }
    _customShortcuts = updated;
    notifyListeners();
  }

  // ── 忙碌 ──
  void setEditorBusy(bool busy) {
    _editorBusy = busy;
    notifyListeners();
  }

  void setEditorStatus(String? status) {
    _editorStatus = status;
    notifyListeners();
  }

  // ── 图片 ──
  void setFailedImageBytes(Uint8List? bytes) {
    _failedImageBytes = bytes;
    notifyListeners();
  }

  void setImagePathMode(bool relative) {
    _useRelativeImagePath = relative;
    notifyListeners();
  }

  // ── 清理 ──
  @override
  void dispose() {
    super.dispose();
  }
}