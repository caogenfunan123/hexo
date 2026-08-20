import 'package:markdown/markdown.dart' as md;

/// 将 Markdown 构建为适合在 WebView 中渲染的 HTML 正文（纯 Dart，无 Flutter 依赖）。
///
/// 渲染管线：
/// 1. 先提取代码块（含 ```mermaid）与数学公式，替换为私有区占位符，避免 markdown
///    转换破坏 `$...$` 中的下划线等标记；
/// 2. 对剩余文本做基础安全过滤（移除 script / iframe / 事件属性等）；
/// 3. 走 `markdown` 包完成 Markdown → HTML；
/// 4. 还原占位符：公式保持 `$...$` / `$$...$$` 原文（交由 KaTeX auto-render 渲染），
///    mermaid 输出为 `<pre class="mermaid">`（交由 mermaid.js 渲染），普通代码块输出
///    为 `<pre><code class="language-xxx">`（交由 highlight.js 渲染）。
class MarkdownPreviewBuilder {
  MarkdownPreviewBuilder._();

  static const String _pStart = '\uE000';
  static const String _pEnd = '\uE001';

  /// 把 Markdown 文本转换为 WebView 中 `#content` 容器内的 HTML 正文。
  static String buildBody(String markdown) {
    final blocks = <int, _SpecialBlock>{};
    var index = 0;

    var text = _sanitize(markdown);

    // 1. 代码块占位符保护（含 mermaid）
    text = text.replaceAllMapped(
      RegExp(r'```(\w*)\n([\s\S]*?)```'),
      (m) {
        final lang = (m.group(1) ?? '').trim().toLowerCase();
        final content = m.group(2) ?? '';
        final placeholder = '$_pStart${index++}$_pEnd';
        if (lang == 'mermaid') {
          blocks[index - 1] = _SpecialBlock(
            '<div class="mermaid-wrap"><pre class="mermaid">'
            '${_escapeHtml(content)}</pre></div>',
            isBlock: true,
          );
        } else {
          final langAttr =
              lang.isEmpty ? '' : ' class="language-${_escapeAttr(lang)}"';
          blocks[index - 1] = _SpecialBlock(
            '<pre><code$langAttr>${_escapeHtml(content)}</code></pre>',
            isBlock: true,
          );
        }
        return placeholder;
      },
    );

    // 2. 块级公式占位符保护
    text = text.replaceAllMapped(
      RegExp(r'\$\$([\s\S]+?)\$\$'),
      (m) {
        final placeholder = '$_pStart${index++}$_pEnd';
        blocks[index - 1] = _SpecialBlock(
          '<span class="math-display">\$\$${_escapeHtml(m.group(1) ?? '')}\$\$</span>',
          isBlock: true,
        );
        return placeholder;
      },
    );

    // 3. 内联公式占位符保护（排除 $ 紧邻场景，避免误伤普通文本中的货币符号）
    text = text.replaceAllMapped(
      RegExp(r'(?<!\$)\$([^$\n]+?)\$(?!\$)'),
      (m) {
        final placeholder = '$_pStart${index++}$_pEnd';
        blocks[index - 1] = _SpecialBlock(
          '\$${_escapeHtml(m.group(1) ?? '')}\$',
          isBlock: false,
        );
        return placeholder;
      },
    );

    // 4. markdown 转换
    final html = md.markdownToHtml(text);

    // 5. 还原占位符
    return html.replaceAllMapped(
      RegExp('$_pStart(\\d+)$_pEnd'),
      (m) {
        final block = blocks[int.parse(m.group(1) ?? '')];
        if (block == null) return '';
        if (!block.isBlock) return block.html;
        return '<div class="md-special-block">${block.html}</div>';
      },
    );
  }

  /// 基础安全过滤：剔除脚本、iframe、事件属性与 javascript: 链接，
  /// 防止 Markdown 中嵌入的原始 HTML 在 WebView 中执行。
  static String _sanitize(String text) {
    var t = text;
    t = t.replaceAll(RegExp(r'(?i)<\s*script\b[\s\S]*?(?:<\s*/\s*script\s*>|$)?'), '');
    t = t.replaceAll(RegExp(r'(?i)<\s*/?\s*script\s*>'), '');
    t = t.replaceAll(RegExp(r'(?i)<\s*iframe\b[\s\S]*?(?:<\s*/\s*iframe\s*>|$)'), '');
    t = t.replaceAll(RegExp(r'(?i)<\s*object\b[\s\S]*?(?:<\s*/\s*object\s*>|$)'), '');
    t = t.replaceAll(RegExp(r'(?i)<\s*embed\b[^>]*>'), '');
    t = t.replaceAll(RegExp(r'(?i)<\s*form\b[\s\S]*?(?:<\s*/\s*form\s*>|$)'), '');
    t = t.replaceAll(
      RegExp(r'''(?i)\s+on[a-z0-9]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)'''),
      '',
    );
    t = t.replaceAll(
      RegExp(r'''(?i)(href|src)\s*=\s*("[^"]*"|'[^']*'|)[^\s>]*\s*javascript:'''),
      r'$1="#"',
    );
    return t;
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _escapeAttr(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

class _SpecialBlock {
  _SpecialBlock(this.html, {required this.isBlock});

  final String html;
  final bool isBlock;
}
