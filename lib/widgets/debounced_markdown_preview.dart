import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../desktop/widgets/code_highlight.dart';
import '../theme/app_color.dart';

/// 防抖版 Markdown 预览状态。
///
/// 文本变化后等待 [debounce] 静默期才提交并通知重建，
/// 避免每次击键都触发 Markdown 全文解析。
class DebouncedMarkdownPreviewState extends ChangeNotifier {
  DebouncedMarkdownPreviewState({
    Duration debounce = const Duration(milliseconds: 200),
  }) : _debounce = debounce;

  final Duration _debounce;
  Timer? _timer;
  String _pendingText = '';
  String _committedText = '';

  /// 已提交（当前正在渲染）的文本
  String get currentText => _committedText;

  /// 更新待渲染文本（防抖）
  void updateText(String text) {
    _pendingText = text;
    _timer?.cancel();
    _timer = Timer(_debounce, _commit);
  }

  void _commit() {
    if (_pendingText != _committedText) {
      _committedText = _pendingText;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// 使用 [DebouncedMarkdownPreviewState] 的只读预览，仅在提交后重建。
///
/// 外层仍需自行包裹滚动容器（本组件不内建 ScrollView）。
class DebouncedMarkdownPreview extends StatelessWidget {
  const DebouncedMarkdownPreview({
    super.key,
    required this.state,
    this.isDark = false,
    this.styleSheet,
  });

  final DebouncedMarkdownPreviewState state;
  final bool isDark;
  final MarkdownStyleSheet? styleSheet;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, child) {
        final text = state.currentText;
        if (text.isEmpty) {
          return Text(
            '暂无内容',
            style: TextStyle(
              color: AppColor.borderStrong(context),
              fontSize: 14,
            ),
          );
        }
        return Markdown(
          data: text,
          selectable: true,
          styleSheet: styleSheet,
          builders: buildHighlightedBuilders(isDark),
        );
      },
    );
  }
}
