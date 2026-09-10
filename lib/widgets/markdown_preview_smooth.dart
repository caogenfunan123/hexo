import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart';

/// 基于 [flutter_smooth_markdown] 的纯原生 Widget Markdown 预览组件。
///
/// 不依赖 WebView，无 Binder / 端口 / cleartext 等平台问题，全平台一致。
/// Mermaid 图表与 KaTeX 公式由 Dart 原生解析，适合 App 内快速预览。
/// 发布到 Hexo 时仍输出原始 Markdown 文本，由 Hexo 的 mermaid.js 保证
/// 线上渲染与网页一致。
///
/// 内部对 markdown 文本变化做 200ms 防抖，避免每次击键都触发
/// 整篇 Markdown 解析与重建。
///
/// 当 [SmoothMarkdown] 的 Mermaid 渲染结果与预期差异较大时，可切换回
/// [MarkdownPreviewWebView]（基于 WebView 的 100% 还原方案）。
class MarkdownPreviewSmooth extends StatefulWidget {
  MarkdownPreviewSmooth({
    super.key,
    required this.markdown,
    this.darkTheme = false,
    this.baseFontSize,
    this.lineHeight,
    this.padding = const EdgeInsets.all(16),
    this.onOpenLink,
  }) : _plugins = ParserPluginRegistry()..register(const MermaidPlugin()),
       _builderRegistry = BuilderRegistry()..register('mermaid', const MermaidBuilder());

  final String markdown;
  final bool darkTheme;

  /// 正文基础字号；为空则沿用内置样式表默认值（手机端不变）
  final double? baseFontSize;

  /// 正文行高；为空则沿用内置样式表默认值（手机端不变）
  final double? lineHeight;

  /// 内容内边距
  final EdgeInsetsGeometry padding;

  final ValueChanged<String>? onOpenLink;
  final ParserPluginRegistry _plugins;
  final BuilderRegistry _builderRegistry;

  @override
  State<MarkdownPreviewSmooth> createState() => _MarkdownPreviewSmoothState();
}

class _MarkdownPreviewSmoothState extends State<MarkdownPreviewSmooth> {
  static const Duration _debounce = Duration(milliseconds: 200);
  Timer? _timer;
  late String _displayed;

  @override
  void initState() {
    super.initState();
    _displayed = widget.markdown;
  }

  @override
  void didUpdateWidget(covariant MarkdownPreviewSmooth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown) {
      _timer?.cancel();
      _timer = Timer(_debounce, () {
        if (mounted && widget.markdown != _displayed) {
          setState(() => _displayed = widget.markdown);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.darkTheme
        ? MarkdownStyleSheet.dark()
        : MarkdownStyleSheet.light();
    final fontSize = widget.baseFontSize;
    final lineHeight = widget.lineHeight;
    final MarkdownStyleSheet styleSheet;
    if (fontSize == null && lineHeight == null) {
      styleSheet = base;
    } else {
      // 按基准字号(16)等比缩放所有文本样式：标题/强调/代码/表格跟随正文，
      // 只覆盖 paragraphStyle 会导致标题与代码字号不随设置变化
      TextStyle? scale(TextStyle? s) {
        if (s == null) return null;
        return s.copyWith(
          fontSize: s.fontSize == null
              ? fontSize
              : (fontSize == null ? s.fontSize : s.fontSize! * (fontSize / 16)),
          height: lineHeight ?? s.height,
        );
      }

      styleSheet = base.copyWith(
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
    }
    return SingleChildScrollView(
      padding: widget.padding,
      child: SmoothMarkdown(
        data: _displayed,
        selectable: true,
        styleSheet: styleSheet,
        onTapLink: (url) {
          widget.onOpenLink?.call(url);
        },
        plugins: widget._plugins,
        builderRegistry: widget._builderRegistry,
      ),
    );
  }
}
