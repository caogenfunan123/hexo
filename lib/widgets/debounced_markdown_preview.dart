import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart';

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
/// 渲染引擎与手机端预览（MarkdownPreviewSmooth）一致，基于
/// flutter_smooth_markdown：表格 / 数学公式 / mermaid 全平台原生渲染，
/// 不再走 flutter_markdown（后者不支持公式）。
///
/// 外层仍需自行包裹滚动容器（本组件不内建 ScrollView）。
class DebouncedMarkdownPreview extends StatelessWidget {
  const DebouncedMarkdownPreview({
    super.key,
    required this.state,
    this.isDark = false,
    this.baseFontSize = 16,
    this.lineHeight = 1.6,
    this.maxRenderChars = 60000,
  });

  final DebouncedMarkdownPreviewState state;
  final bool isDark;

  /// 正文基础字号，标题/代码/表格按 16 基准等比缩放（对标手机端预览）
  final double baseFontSize;

  /// 正文行高
  final double lineHeight;

  /// 单次渲染的字符上限：超长文档（如 5w 字）截断预览，
  /// 避免一次性全量解析造成的卡顿；编辑区与保存内容不受影响。
  /// 计数按 Unicode 字素簇（grapheme）而非 UTF-16 code unit，
  /// 避免把 emoji / 组合字符从中间切开。
  final int maxRenderChars;

  static final ParserPluginRegistry _plugins = ParserPluginRegistry()
    ..register(const MermaidPlugin());
  static final BuilderRegistry _builders = BuilderRegistry()
    ..register('mermaid', const MermaidBuilder());

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
              _buildSmooth(safe),
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
        return _buildSmooth(text);
      },
    );
  }

  Widget _buildSmooth(String markdown) {
    final base = isDark
        ? MarkdownStyleSheet.dark()
        : MarkdownStyleSheet.light();
    // 按基准字号(16)等比缩放所有文本样式：标题/强调/代码/表格跟随正文，
    // 只覆盖 paragraphStyle 会导致标题与代码字号不随设置变化
    TextStyle? scale(TextStyle? s) {
      if (s == null) return null;
      return s.copyWith(
        fontSize: s.fontSize == null
            ? baseFontSize
            : baseFontSize * (s.fontSize! / 16),
        height: lineHeight,
      );
    }

    final styleSheet = base.copyWith(
      textStyle: scale(base.textStyle),
      paragraphStyle: scale(base.paragraphStyle),
      h1Style: scale(base.h1Style),
      h2Style: scale(base.h2Style),
      h3Style: scale(base.h3Style),
      h4Style: scale(base.h4Style),
      h5Style: scale(base.h5Style),
      h6Style: scale(base.h6Style),
      blockquoteStyle: scale(base.blockquoteStyle),
      codeBlockStyle: scale(base.codeBlockStyle),
      inlineCodeStyle: scale(base.inlineCodeStyle),
      linkStyle: scale(base.linkStyle),
      boldStyle: scale(base.boldStyle),
      italicStyle: scale(base.italicStyle),
      strikethroughStyle: scale(base.strikethroughStyle),
      listBulletStyle: scale(base.listBulletStyle),
      tableHeaderStyle: scale(base.tableHeaderStyle),
      tableCellStyle: scale(base.tableCellStyle),
    );
    // SmoothMarkdown 无内建滚动：外层 SingleChildScrollView 负责滚动，
    // 直接用内建 ListView 的形态会在滚动容器内高度无界崩溃
    return SmoothMarkdown(
      data: markdown,
      selectable: true,
      styleSheet: styleSheet,
      plugins: _plugins,
      builderRegistry: _builders,
    );
  }
}
