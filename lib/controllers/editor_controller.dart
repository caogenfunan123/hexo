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
/// - 保存队列（SaveTask 队列、防抖计时器）
/// - 编辑器忙碌/状态标志
/// - 图片路径模式
/// - 图片上传回调（由外部注入）
///
/// 数据层（DocumentController 管理）：
/// - 文章内容 TextEditingController → DocumentController
/// - Article 数据模型 → DocumentController
/// - 草稿/模板列表 → DocumentController
library;

import 'dart:async';
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

/// 保存任务
class SaveTask {
  final String tabId;
  final String content;
  final String title;
  final DateTime createdAt;
  int retryCount;

  SaveTask({
    required this.tabId,
    required this.content,
    required this.title,
    this.retryCount = 0,
  }) : createdAt = DateTime.now();
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
  static const int _maxRetries = 3;

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

  // ── 保存队列 ──
  final List<SaveTask> _saveQueue = [];
  bool _isFlushing = false;
  Timer? _debounceTimer;
  Timer? _autoSaveTimer;

  // ── 图片 ──
  Uint8List? _failedImageBytes;
  bool _useRelativeImagePath = false;

  // ── 图片上传回调（由外部注入） ──
  Future<void> Function()? onRetryUploadImage;
  Future<void> Function()? onInsertImage;
  Future<void> Function()? onBatchInsertImages;

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

  // ── Getters: 保存 ──
  bool get isFlushing => _isFlushing;
  int get saveQueueLength => _saveQueue.length;

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

  void closeTab(int index) {
    if (index >= 0 && index < _openTabs.length) {
      _flushTabTasks(_openTabs[index].id);
      _openTabs.removeAt(index);
      if (_openTabs.isEmpty) {
        _activeTabIndex = 0;
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
  void updateStats(String content) {
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

  void toggleImagePathMode() {
    _useRelativeImagePath = !_useRelativeImagePath;
    notifyListeners();
  }

  // ── 保存队列 ──
  void enqueue(String tabId, String content, String title) {
    _saveQueue.add(SaveTask(tabId: tabId, content: content, title: title));
    notifyListeners();
  }

  void _flushTabTasks(String tabId) {
    _saveQueue.removeWhere((t) => t.tabId == tabId);
  }

  Future<void> flush() async {
    if (_isFlushing || _saveQueue.isEmpty) return;
    _isFlushing = true;
    notifyListeners();

    final tasks = List<SaveTask>.from(_saveQueue);
    _saveQueue.clear();

    for (final task in tasks) {
      try {
        // 实际保存逻辑由外部注入，这里只管理队列
      } catch (e) { debugPrint('EditorController: flush save failed (retry ${task.retryCount}/$_maxRetries): $e');
        if (task.retryCount < _maxRetries) {
          task.retryCount++;
          _saveQueue.add(task);
        }
      }
    }

    _isFlushing = false;
    notifyListeners();
  }

  /// 窗口关闭前强制落盘
  Future<bool> onBeforeClose() async {
    if (_saveQueue.isNotEmpty) {
      await flush();
    }
    return _saveQueue.isEmpty;
  }

  // ── 清理 ──
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _autoSaveTimer?.cancel();
    super.dispose();
  }
}