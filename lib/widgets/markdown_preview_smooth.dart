import 'package:flutter/material.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart';

/// 基于 [flutter_smooth_markdown] 的纯原生 Widget Markdown 预览组件。
///
/// 不依赖 WebView，无 Binder / 端口 / cleartext 等平台问题，全平台一致。
/// Mermaid 图表与 KaTeX 公式由 Dart 原生解析，适合 App 内快速预览。
/// 发布到 Hexo 时仍输出原始 Markdown 文本，由 Hexo 的 mermaid.js 保证
/// 线上渲染与网页一致。
///
/// 当 [SmoothMarkdown] 的 Mermaid 渲染结果与预期差异较大时，可切换回
/// [MarkdownPreviewWebView]（基于 WebView 的 100% 还原方案）。
class MarkdownPreviewSmooth extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SmoothMarkdown(
        data: markdown,
        selectable: true,
        styleSheet: darkTheme
            ? MarkdownStyleSheet.dark()
            : MarkdownStyleSheet.light(),
        onTapLink: (url) {
          onOpenLink?.call(url);
        },
        plugins: _plugins,
        builderRegistry: _builderRegistry,
      ),
    );
  }
}