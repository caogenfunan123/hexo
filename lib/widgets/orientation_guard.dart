/// 横竖屏状态保持
///
/// 监听设备方向变化并在方向切换后恢复编辑状态：
/// - 保存当前编辑状态（光标位置、滚动位置）
/// - 方向切换后恢复编辑状态
/// - 适配不同布局
library;

import 'package:flutter/material.dart';

/// 编辑器状态快照
///
/// 记录方向切换前的编辑状态，用于方向切换后恢复。
class EditorStateSnapshot {
  final int cursorPosition;
  final int cursorLine;
  final int cursorColumn;
  final double scrollOffset;
  final double maxScrollExtent;
  final String? selectedText;
  final int selectionStart;
  final int selectionEnd;
  final DateTime timestamp;

  const EditorStateSnapshot({
    required this.cursorPosition,
    required this.cursorLine,
    required this.cursorColumn,
    required this.scrollOffset,
    required this.maxScrollExtent,
    this.selectedText,
    this.selectionStart = -1,
    this.selectionEnd = -1,
    required this.timestamp,
  });

  bool get hasSelection => selectionStart >= 0 && selectionEnd >= 0;

  @override
  String toString() =>
      'EditorState(line: $cursorLine, col: $cursorColumn, pos: $cursorPosition, '
      'scroll: ${scrollOffset.toStringAsFixed(1)})';
}

/// 横竖屏状态保持 Widget
///
/// 包装编辑器内容，监听设备方向变化。
/// 在方向切换前保存编辑状态，方向切换后自动恢复。
class OrientationGuard extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 当前编辑器状态的构建器
  final EditorStateSnapshot Function()? stateBuilder;

  /// 状态恢复回调
  final void Function(EditorStateSnapshot snapshot)? onRestore;

  /// 方向变化回调
  final void Function(Orientation newOrientation)? onOrientationChanged;

  /// 是否启用状态保持
  final bool enabled;

  const OrientationGuard({
    super.key,
    required this.child,
    this.stateBuilder,
    this.onRestore,
    this.onOrientationChanged,
    this.enabled = true,
  });

  @override
  State<OrientationGuard> createState() => _OrientationGuardState();
}

class _OrientationGuardState extends State<OrientationGuard>
    with WidgetsBindingObserver {
  Orientation? _currentOrientation;
  EditorStateSnapshot? _savedState;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentOrientation = MediaQuery.of(context).orientation;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!widget.enabled) return;

    final newOrientation = MediaQuery.of(context).orientation;
    if (newOrientation != _currentOrientation) {
      _handleOrientationChange(newOrientation);
    }
  }

  void _handleOrientationChange(Orientation newOrientation) {
    final oldOrientation = _currentOrientation;
    _currentOrientation = newOrientation;

    // 保存当前状态
    if (oldOrientation != null) {
      _savedState = widget.stateBuilder?.call();
    }

    widget.onOrientationChanged?.call(newOrientation);

    // 方向切换后延迟恢复状态
    if (_savedState != null && !_isRestoring) {
      _isRestoring = true;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _savedState != null) {
          widget.onRestore?.call(_savedState!);
          _isRestoring = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// 方向感知布局
///
/// 根据设备方向自动切换布局模式。
class OrientationAwareLayout extends StatelessWidget {
  final Widget portraitLayout;
  final Widget landscapeLayout;
  final bool useOrientation;

  const OrientationAwareLayout({
    super.key,
    required this.portraitLayout,
    required this.landscapeLayout,
    this.useOrientation = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!useOrientation) return portraitLayout;

    final orientation = MediaQuery.of(context).orientation;
    return orientation == Orientation.portrait
        ? portraitLayout
        : landscapeLayout;
  }
}

/// 方向切换过渡动画
///
/// 在方向切换时提供平滑的过渡效果。
class OrientationTransition extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const OrientationTransition({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// 方向信息显示
///
/// 一个小的调试/信息 Widget，显示当前设备方向。
class OrientationIndicator extends StatelessWidget {
  final bool showLabel;

  const OrientationIndicator({
    super.key,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isPortrait = orientation == Orientation.portrait;

    return Tooltip(
      message: isPortrait ? '竖屏模式' : '横屏模式',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPortrait ? Icons.stay_current_portrait : Icons.stay_current_landscape,
              size: 14,
              color: Colors.grey,
            ),
            if (showLabel) ...[
              const SizedBox(width: 4),
              Text(
                isPortrait ? '竖屏' : '横屏',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 编辑器状态管理器
///
/// 管理编辑器状态（光标位置、滚动位置、选择状态），
/// 支持保存和恢复状态，用于方向切换、模式切换等场景。
class EditorStateManager {
  int _cursorPosition = 0;
  int _cursorLine = 0;
  int _cursorColumn = 0;
  double _scrollOffset = 0.0;
  double _maxScrollExtent = 0.0;
  String? _selectedText;
  int _selectionStart = -1;
  int _selectionEnd = -1;

  final ScrollController? _scrollController;
  final TextEditingController? _textController;

  EditorStateManager({
    ScrollController? scrollController,
    TextEditingController? textController,
  })  : _scrollController = scrollController,
        _textController = textController;

  /// 更新当前状态
  void updateFromEditor({
    required int cursorPosition,
    required int cursorLine,
    required int cursorColumn,
    double? scrollOffset,
    double? maxScrollExtent,
    String? selectedText,
    int selectionStart = -1,
    int selectionEnd = -1,
  }) {
    _cursorPosition = cursorPosition;
    _cursorLine = cursorLine;
    _cursorColumn = cursorColumn;
    _scrollOffset = scrollOffset ?? _scrollOffset;
    _maxScrollExtent = maxScrollExtent ?? _maxScrollExtent;
    _selectedText = selectedText;
    _selectionStart = selectionStart;
    _selectionEnd = selectionEnd;
  }

  /// 从当前绑定的控制器自动更新
  void updateFromControllers() {
    if (_scrollController?.hasClients == true) {
      _scrollOffset = _scrollController!.offset;
      _maxScrollExtent = _scrollController!.position.maxScrollExtent;
    }
    if (_textController != null) {
      _cursorPosition = _textController!.selection.baseOffset;
      final text = _textController!.text;
      if (_cursorPosition <= text.length) {
        final before = text.substring(0, _cursorPosition);
        _cursorLine = '\n'.allMatches(before).length;
        final lastNewline = before.lastIndexOf('\n');
        _cursorColumn = _cursorPosition - (lastNewline + 1);
      }
      if (_textController!.selection.isValid) {
        _selectionStart = _textController!.selection.start;
        _selectionEnd = _textController!.selection.end;
        if (_selectionStart != _selectionEnd) {
          _selectedText = _textController!.selection.textInside(text);
        }
      }
    }
  }

  /// 创建状态快照
  EditorStateSnapshot createSnapshot() {
    updateFromControllers();
    return EditorStateSnapshot(
      cursorPosition: _cursorPosition,
      cursorLine: _cursorLine,
      cursorColumn: _cursorColumn,
      scrollOffset: _scrollOffset,
      maxScrollExtent: _maxScrollExtent,
      selectedText: _selectedText,
      selectionStart: _selectionStart,
      selectionEnd: _selectionEnd,
      timestamp: DateTime.now(),
    );
  }

  /// 恢复到快照状态
  Future<void> restoreFromSnapshot(EditorStateSnapshot snapshot) async {
    // 恢复滚动位置
    if (_scrollController?.hasClients == true) {
      final targetOffset = snapshot.scrollOffset.clamp(
        0.0,
        snapshot.maxScrollExtent,
      );
      _scrollController!.jumpTo(targetOffset);
    }

    // 恢复光标位置和选择
    if (_textController != null) {
      final text = _textController!.text;
      final safePosition = snapshot.cursorPosition.clamp(0, text.length);

      if (snapshot.hasSelection) {
        final safeStart = snapshot.selectionStart.clamp(0, text.length);
        final safeEnd = snapshot.selectionEnd.clamp(0, text.length);
        _textController!.selection = TextSelection(
          baseOffset: safeStart,
          extentOffset: safeEnd,
        );
      } else {
        _textController!.selection = TextSelection.collapsed(
          offset: safePosition,
        );
      }
    }

    _cursorPosition = snapshot.cursorPosition;
    _cursorLine = snapshot.cursorLine;
    _cursorColumn = snapshot.cursorColumn;
    _scrollOffset = snapshot.scrollOffset;
    _maxScrollExtent = snapshot.maxScrollExtent;
    _selectedText = snapshot.selectedText;
    _selectionStart = snapshot.selectionStart;
    _selectionEnd = snapshot.selectionEnd;
  }

  void dispose() {
    // 不 dispose 外部传入的控制器
  }
}