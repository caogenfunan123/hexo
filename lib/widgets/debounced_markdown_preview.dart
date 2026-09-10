import 'dart:async';

import 'package:characters/characters.dart';
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
    this.maxRenderChars = 60000,
  });

  final DebouncedMarkdownPreviewState state;
  final bool isDark;
  final MarkdownStyleSheet? styleSheet;

  /// 单次渲染的字符上限：超长文档（如 5w 字）截断预览，
  /// 避免一次性全量解析造成的卡顿；编辑区与保存内容不受影响。
  /// 计数按 Unicode 字素簇（grapheme）而非 UTF-16 code unit，
  /// 避免把 emoji / 组合字符从中间切开。
  final int maxRenderChars;

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
        final chars = text.characters;
        if (chars.length > maxRenderChars) {
          // 先按字素簇预算截取，再尽量回退到最近的换行，保持段落完整
          final head = chars.take(maxRenderChars).toString();
          final cut = head.lastIndexOf('\n');
          final safe = cut > maxRenderChars ~/ 2 ? head.substring(0, cut) : head;
          final safeLen = safe.characters.length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Markdown(
                data: safe,
                selectable: true,
                styleSheet: styleSheet,
                builders: buildHighlightedBuilders(isDark),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '内容较长，预览已折叠（仅渲染前 $safeLen 字符），编辑与保存不受影响',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColor.textMuted(context),
                  ),
                ),
              ),
            ],
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
