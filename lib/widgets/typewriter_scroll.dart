/// 打字机滚动模式
///
/// 参考 MarkText 打字机滚动逻辑：
/// - 编辑时光标始终保持在屏幕垂直中间位置
/// - 自动滚动，不跳变
/// - 适配软键盘弹出
/// - 可配置固定行数（默认保持在屏幕中间）
library;

import 'package:flutter/material.dart';

/// 打字机滚动控制器
///
/// 管理编辑区域的滚动位置，使光标始终保持在屏幕垂直中心。
/// 当用户输入时自动调整滚动偏移，避免光标跑到屏幕边缘。
class TypewriterScrollController {
  final ScrollController scrollController;
  final double lineHeight;
  final int visibleLines;

  /// 上一次的滚动偏移
  double _lastScrollOffset = 0.0;

  /// 上一次的光标行号
  int _lastLineNumber = 0;

  /// 是否启用打字机模式
  bool _enabled = true;

  TypewriterScrollController({
    required this.scrollController,
    this.lineHeight = 22.0,
    this.visibleLines = 30,
  });

  /// 是否启用打字机模式
  bool get enabled => _enabled;

  set enabled(bool value) {
    _enabled = value;
    if (!value) {
      _lastScrollOffset = 0.0;
      _lastLineNumber = 0;
    }
  }

  /// 更新光标位置并自动调整滚动
  ///
  /// [lineNumber] 当前光标所在行号（从 0 开始）
  /// [totalLines] 文档总行数
  void updateCursorPosition(int lineNumber, int totalLines) {
    if (!_enabled) return;

    // 如果行号未变化，跳过
    if (lineNumber == _lastLineNumber) return;

    _lastLineNumber = lineNumber;

    if (!scrollController.hasClients) return;

    final maxScrollExtent = scrollController.position.maxScrollExtent;
    final viewportHeight = scrollController.position.viewportDimension;

    // 计算光标在文档中的实际 Y 位置
    final cursorY = lineNumber * lineHeight;

    // 目标：让光标出现在屏幕中心
    // 滚动偏移 = 光标Y - 视口高度/2
    final targetOffset = cursorY - (viewportHeight / 2);

    // 确保不超出边界
    final clampedOffset = targetOffset.clamp(0.0, maxScrollExtent);

    // 计算与当前偏移的差值
    final delta = (clampedOffset - _lastScrollOffset).abs();

    // 如果差值很小（在同一行内），跳过
    if (delta < lineHeight * 0.5) return;

    _lastScrollOffset = clampedOffset;

    // 使用动画滚动到目标位置
    // 如果距离较小，使用较短的动画时长
    final duration = delta > lineHeight * 5
        ? const Duration(milliseconds: 200)
        : const Duration(milliseconds: 80);

    // 使用 animateTo 进行平滑滚动
    scrollController.animateTo(
      clampedOffset,
      duration: duration,
      curve: Curves.easeOut,
    );
  }

  /// 立即跳转到位置（无动画）
  void jumpToLine(int lineNumber, int totalLines) {
    if (!scrollController.hasClients) return;

    final cursorY = lineNumber * lineHeight;
    final viewportHeight = scrollController.position.viewportDimension;
    final maxScrollExtent = scrollController.position.maxScrollExtent;

    final targetOffset = cursorY - (viewportHeight / 2);
    final clampedOffset = targetOffset.clamp(0.0, maxScrollExtent);

    _lastScrollOffset = clampedOffset;
    _lastLineNumber = lineNumber;

    scrollController.jumpTo(clampedOffset);
  }

  /// 适配软键盘弹出时调整滚动
  ///
  /// [keyboardHeight] 键盘高度
  void adjustForKeyboard(double keyboardHeight) {
    if (!_enabled || !scrollController.hasClients) return;

    // 键盘弹出时，可用的视口高度变小
    // 稍微向下滚动以保持光标可见
    if (keyboardHeight > 0) {
      final currentOffset = scrollController.offset;
      final newOffset = currentOffset + keyboardHeight * 0.3;
      final maxScrollExtent = scrollController.position.maxScrollExtent;

      scrollController.animateTo(
        newOffset.clamp(0.0, maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  /// 重置状态
  void reset() {
    _lastScrollOffset = 0.0;
    _lastLineNumber = 0;
  }

  /// 释放资源
  void dispose() {
    // 不 dispose scrollController，因为它是外部传入的
    reset();
  }
}

/// 打字机模式状态指示器
///
/// 一个小型 Widget，显示当前是否处于打字机模式。
class TypewriterModeIndicator extends StatelessWidget {
  final bool isEnabled;
  final VoidCallback? onToggle;

  const TypewriterModeIndicator({
    super.key,
    required this.isEnabled,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isEnabled ? '打字机模式：开启' : '打字机模式：关闭',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isEnabled
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isEnabled
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isEnabled ? Icons.edit_note : Icons.edit_note,
                size: 14,
                color: isEnabled
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                '打字机',
                style: TextStyle(
                  fontSize: 10,
                  color: isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 打字机模式配置弹窗
class TypewriterSettingsDialog extends StatefulWidget {
  final int currentVisibleLines;
  final double currentLineHeight;
  final bool currentEnabled;
  final ValueChanged<int>? onVisibleLinesChanged;
  final ValueChanged<double>? onLineHeightChanged;
  final ValueChanged<bool>? onEnabledChanged;

  const TypewriterSettingsDialog({
    super.key,
    required this.currentVisibleLines,
    required this.currentLineHeight,
    required this.currentEnabled,
    this.onVisibleLinesChanged,
    this.onLineHeightChanged,
    this.onEnabledChanged,
  });

  @override
  State<TypewriterSettingsDialog> createState() => _TypewriterSettingsDialogState();
}

class _TypewriterSettingsDialogState extends State<TypewriterSettingsDialog> {
  late int _visibleLines;
  late double _lineHeight;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _visibleLines = widget.currentVisibleLines;
    _lineHeight = widget.currentLineHeight;
    _enabled = widget.currentEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('打字机模式设置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 开关
          SwitchListTile(
            title: const Text('启用打字机模式'),
            subtitle: const Text('编辑时光标保持在屏幕中央'),
            value: _enabled,
            onChanged: (v) {
              setState(() => _enabled = v);
              widget.onEnabledChanged?.call(v);
            },
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(),
          // 可视行数
          const SizedBox(height: 8),
          const Text('可视行数', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _visibleLines.toDouble(),
                  min: 10,
                  max: 60,
                  divisions: 50,
                  label: '$_visibleLines 行',
                  onChanged: (v) {
                    setState(() => _visibleLines = v.round());
                    widget.onVisibleLinesChanged?.call(v.round());
                  },
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '$_visibleLines',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          // 行高
          const SizedBox(height: 8),
          const Text('行高', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _lineHeight,
                  min: 16,
                  max: 36,
                  divisions: 20,
                  label: '${_lineHeight.toStringAsFixed(1)} px',
                  onChanged: (v) {
                    setState(() => _lineHeight = v);
                    widget.onLineHeightChanged?.call(v);
                  },
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${_lineHeight.toStringAsFixed(1)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}