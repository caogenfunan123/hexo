import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart';

import '../theme/app_color.dart';

/// 公式渲染兜底 builder。
///
/// flutter_math_fork 比 KaTeX JS 严格：部分合法 LaTeX（如数组类环境外使用
/// `\\` 换行，解析期会留下 CrNode 临时节点活到构建期）会抛
/// BuildException，包内默认 fallback 显示整段报错文本，观感差。
/// 这里覆盖默认 block_math / inline_math builder，出错时回落为
/// LaTeX 原文（等宽字体），与 WebView 编辑端 math-raw 行为一致。
class SafeInlineMathBuilder extends MarkdownWidgetBuilder {
  const SafeInlineMathBuilder();

  @override
  bool canBuild(MarkdownNode node) => node is InlineMathNode;

  @override
  Widget build(
    MarkdownNode node,
    MarkdownStyleSheet styleSheet,
    MarkdownRenderContext context,
  ) {
    final mathNode = node as InlineMathNode;
    return Builder(
      builder: (ctx) => Math.tex(
        mathNode.latex,
        textStyle: styleSheet.textStyle,
        mathStyle: MathStyle.text,
        options: MathOptions(
          fontSize: styleSheet.textStyle?.fontSize ?? 16,
          color: styleSheet.textStyle?.color ?? AppColor.textPrimary(ctx),
        ),
        onErrorFallback: (_) =>
            _latexFallback(mathNode.latex, styleSheet.textStyle),
      ),
    );
  }
}

class SafeBlockMathBuilder extends MarkdownWidgetBuilder {
  const SafeBlockMathBuilder();

  @override
  bool canBuild(MarkdownNode node) => node is BlockMathNode;

  @override
  Widget build(
    MarkdownNode node,
    MarkdownStyleSheet styleSheet,
    MarkdownRenderContext context,
  ) {
    final mathNode = node as BlockMathNode;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Builder(
          builder: (ctx) => Math.tex(
            mathNode.latex,
            textStyle: styleSheet.textStyle,
            mathStyle: MathStyle.display,
            options: MathOptions(
              fontSize: (styleSheet.textStyle?.fontSize ?? 16) * 1.25,
              color: styleSheet.textStyle?.color ?? AppColor.textPrimary(ctx),
            ),
            onErrorFallback: (_) =>
                _latexFallback(mathNode.latex, styleSheet.textStyle),
          ),
        ),
      ),
    );
  }
}

Widget _latexFallback(String latex, TextStyle? base) {
  final style = base ?? const TextStyle();
  return Text(
    latex.trim(),
    style: style.copyWith(fontFamily: 'monospace'),
    textAlign: TextAlign.center,
  );
}
