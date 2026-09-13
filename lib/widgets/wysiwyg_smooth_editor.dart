import 'package:flutter/material.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart';

/// 实验性所见即所得编辑器（路线 B：flutter_smooth_markdown 的 formatted 模式）。
///
/// 未聚焦的块按渲染后的样子显示，点进去的块进入可编辑——Notion/实时预览式
/// 混合所见即所得。与既有 contentCtrl 数据流双向桥接：
/// - 组件内编辑 → onChanged → controller.text（沿用 _onContentChanged 的
///   自动保存/字数统计/预览链路，不另起炉灶）；
/// - 外部程序化改动（AI 润色/片段插入/切文章）→ 监听 controller → editor.text；
/// - 图床/工具栏写 contentCtrl 的路径同样经此外部桥接进来。
///
/// 实验性：块焦点/键盘弹出滚动/长文性能待真机验证；关闭开关即回到
/// 源码 TextField，内容已实时同步不会丢字。
class WysiwygSmoothEditor extends StatefulWidget {
  const WysiwygSmoothEditor({
    super.key,
    required this.controller,
    this.baseFontSize = 15,
    this.lineHeight = 1.7,
    this.onAfterWriteBack,
  });

  final TextEditingController controller;
  final double baseFontSize;
  final double lineHeight;

  /// 每次把组件内编辑写回 [controller] 后回调（宿主借此触发
  /// _onContentChanged：未保存标记 + 自动保存防抖，所见即所得模式下
  /// 没有源码 TextField 的 onChanged，缺了这条链路内容只靠周期兜底保存）
  final VoidCallback? onAfterWriteBack;

  @override
  State<WysiwygSmoothEditor> createState() => _WysiwygSmoothEditorState();
}

class _WysiwygSmoothEditorState extends State<WysiwygSmoothEditor> {
  late final MarkdownEditorController _editor;
  bool _writingBack = false;

  @override
  void initState() {
    super.initState();
    _editor = MarkdownEditorController(text: widget.controller.text);
    widget.controller.addListener(_onExternalChanged);
  }

  @override
  void didUpdateWidget(covariant WysiwygSmoothEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onExternalChanged);
      widget.controller.addListener(_onExternalChanged);
      _editor.text = widget.controller.text;
    }
  }

  void _onExternalChanged() {
    if (_writingBack) return;
    if (widget.controller.text != _editor.text) {
      _editor.text = widget.controller.text;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternalChanged);
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? MarkdownStyleSheet.dark()
        : MarkdownStyleSheet.light();
    // 按基准字号等比缩放（与 DebouncedMarkdownPreview 同策略），
    // 保证所见即所得的排版与预览一致
    TextStyle? scale(TextStyle? s) {
      if (s == null) return null;
      return s.copyWith(
        fontSize: s.fontSize == null
            ? widget.baseFontSize
            : widget.baseFontSize * (s.fontSize! / 16),
        height: widget.lineHeight,
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

    return SmoothMarkdownEditor(
      controller: _editor,
      initialMode: MarkdownEditorMode.formatted,
      showToolbar: true,
      styleSheet: styleSheet,
      // 透明背景：不画组件默认的 surface 色块，让手机端壁纸/纸面底色透出
      decoration: const BoxDecoration(),
      plugins: ParserPluginRegistry()..register(const MermaidPlugin()),
      builderRegistry: BuilderRegistry()
        ..register('mermaid', const MermaidBuilder()),
      placeholder: '开始写作，支持 Markdown 语法...',
      onChanged: (md) {
        if (md == widget.controller.text) return;
        _writingBack = true;
        try {
          widget.controller.text = md;
        } finally {
          _writingBack = false;
        }
        widget.onAfterWriteBack?.call();
      },
    );
  }
}
