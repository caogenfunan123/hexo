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
    this.onOpenLink,
  }) : _plugins = ParserPluginRegistry()..register(const MermaidPlugin()),
       _builderRegistry = BuilderRegistry()..register('mermaid', const MermaidBuilder());

  final String markdown;
  final bool darkTheme;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SmoothMarkdown(
        data: _displayed,
        selectable: true,
        styleSheet: widget.darkTheme
            ? MarkdownStyleSheet.dark()
            : MarkdownStyleSheet.light(),
        onTapLink: (url) {
          widget.onOpenLink?.call(url);
        },
        plugins: widget._plugins,
        builderRegistry: widget._builderRegistry,
      ),
    );
  }
}
