/// Markdown 源码语法高亮控制器
/// 对标 VS Code Markdown 编辑器的语法着色
/// 通过在 TextEditingController.buildTextSpan 中注入样式实现
library;

import 'package:flutter/material.dart';

/// Markdown 语法元素的颜色配置
class MarkdownSyntaxColors {
  final Color heading;
  final Color bold;
  final Color italic;
  final Color boldItalic;
  final Color code;
  final Color codeBlock;
  final Color link;
  final Color linkUrl;
  final Color image;
  final Color listMarker;
  final Color blockquote;
  final Color horizontalRule;
  final Color table;
  final Color strikethrough;
  final Color highlight;
  final Color frontmatter;
  final Color htmlTag;
  final Color comment;
  final Color plainText;

  const MarkdownSyntaxColors({
    required this.heading,
    required this.bold,
    required this.italic,
    required this.boldItalic,
    required this.code,
    required this.codeBlock,
    required this.link,
    required this.linkUrl,
    required this.image,
    required this.listMarker,
    required this.blockquote,
    required this.horizontalRule,
    required this.table,
    required this.strikethrough,
    required this.highlight,
    required this.frontmatter,
    required this.htmlTag,
    required this.comment,
    required this.plainText,
  });

  /// 深色主题配色
  static const dark = MarkdownSyntaxColors(
    heading: Color(0xFF569CD6),
    bold: Color(0xFFDCDCAA),
    italic: Color(0xFFC586C0),
    boldItalic: Color(0xFFD7BA7D),
    code: Color(0xFFCE9178),
    codeBlock: Color(0xFFCE9178),
    link: Color(0xFF4EC9B0),
    linkUrl: Color(0xFF6A9955),
    image: Color(0xFFC586C0),
    listMarker: Color(0xFFD7BA7D),
    blockquote: Color(0xFF6A9955),
    horizontalRule: Color(0xFF808080),
    table: Color(0xFF569CD6),
    strikethrough: Color(0xFF808080),
    highlight: Color(0xFFDCDCAA),
    frontmatter: Color(0xFF608B4E),
    htmlTag: Color(0xFF569CD6),
    comment: Color(0xFF6A9955),
    plainText: Color(0xFFD4D4D4),
  );

  /// 浅色主题配色
  static const light = MarkdownSyntaxColors(
    heading: Color(0xFF0000FF),
    bold: Color(0xFF6A0DAD),
    italic: Color(0xFFA31515),
    boldItalic: Color(0xFF6A0DAD),
    code: Color(0xFFA31515),
    codeBlock: Color(0xFFA31515),
    link: Color(0xFF0451A5),
    linkUrl: Color(0xFF008000),
    image: Color(0xFFA31515),
    listMarker: Color(0xFF098658),
    blockquote: Color(0xFF008000),
    horizontalRule: Color(0xFF808080),
    table: Color(0xFF0000FF),
    strikethrough: Color(0xFF808080),
    highlight: Color(0xFF6A0DAD),
    frontmatter: Color(0xFF008000),
    htmlTag: Color(0xFF0000FF),
    comment: Color(0xFF008000),
    plainText: Color(0xFF1E1E1E),
  );
}

/// 桥接语法高亮控制器
/// 包裹一个普通的 TextEditingController，在 buildTextSpan 中注入语法高亮
/// 双向同步：用户输入 → delegate，delegate 外部变更 → 本控制器
class BridgedSyntaxController extends TextEditingController {
  final TextEditingController _delegate;
  MarkdownSyntaxColors colors;
  final double fontSize;
  final String fontFamily;
  bool _syncing = false;

  BridgedSyntaxController({
    required TextEditingController delegate,
    this.colors = MarkdownSyntaxColors.dark,
    this.fontSize = 14.5,
    this.fontFamily = 'monospace',
  }) : _delegate = delegate, super(text: delegate.text) {
    _delegate.addListener(_onDelegateChanged);
    addListener(_onSelfChanged);
  }

  void _onDelegateChanged() {
    if (_syncing) return;
    _syncing = true;
    if (_delegate.text != text) {
      value = _delegate.value;
    }
    _syncing = false;
  }

  void _onSelfChanged() {
    if (_syncing) return;
    _syncing = true;
    if (text != _delegate.text) {
      _delegate.text = text;
    }
    _syncing = false;
  }

  /// 更新配色
  void updateColors(MarkdownSyntaxColors newColors) {
    if (colors != newColors) {
      colors = newColors;
      notifyListeners();
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) {
      return TextSpan(
        text: '',
        style: (style ?? const TextStyle()).copyWith(
          fontSize: fontSize,
          fontFamily: fontFamily,
          color: colors.plainText,
        ),
      );
    }

    final defaultStyle = (style ?? const TextStyle()).copyWith(
      fontSize: fontSize,
      fontFamily: fontFamily,
      color: colors.plainText,
    );

    final spans = _parseHighlighting(text);
    if (spans.isEmpty) {
      return TextSpan(text: text, style: defaultStyle);
    }

    final children = <TextSpan>[];
    var cursor = 0;

    for (final span in spans) {
      if (span.start > cursor) {
        children.add(TextSpan(
          text: text.substring(cursor, span.start),
          style: defaultStyle,
        ));
      }
      if (span.end > span.start) {
        children.add(TextSpan(
          text: text.substring(span.start, span.end),
          style: defaultStyle.copyWith(
            color: span.color,
            fontWeight: span.fontWeight ?? defaultStyle.fontWeight,
            fontStyle: span.fontStyle ?? defaultStyle.fontStyle,
            decoration: span.decoration ?? defaultStyle.decoration,
          ),
        ));
      }
      cursor = span.end;
    }

    if (cursor < text.length) {
      children.add(TextSpan(
        text: text.substring(cursor),
        style: defaultStyle,
      ));
    }

    return TextSpan(style: defaultStyle, children: children);
  }

  /// 解析 Markdown 文本并返回高亮区间
  List<_HighlightSpan> _parseHighlighting(String text) {
    final spans = <_HighlightSpan>[];
    final lines = text.split('\n');
    var offset = 0;
    var inCodeBlock = false;
    var inFrontmatter = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineStart = offset;
      final lineEnd = offset + line.length;

      // Frontmatter 检测
      if (i == 0 && line.trim() == '---') {
        inFrontmatter = true;
        spans.add(_HighlightSpan(
          start: lineStart,
          end: lineEnd,
          color: colors.frontmatter,
          fontWeight: FontWeight.bold,
        ));
        offset = lineEnd + 1;
        continue;
      }
      if (inFrontmatter) {
        if (line.trim() == '---') {
          inFrontmatter = false;
          spans.add(_HighlightSpan(
            start: lineStart,
            end: lineEnd,
            color: colors.frontmatter,
            fontWeight: FontWeight.bold,
          ));
          offset = lineEnd + 1;
          continue;
        }
        _highlightFrontmatterLine(line, lineStart, spans);
        offset = lineEnd + 1;
        continue;
      }

      // 代码块检测
      if (line.trimLeft().startsWith('```')) {
        if (!inCodeBlock) {
          inCodeBlock = true;
          _highlightCodeBlockDelimiter(line, lineStart, spans);
        } else {
          inCodeBlock = false;
          _highlightCodeBlockDelimiter(line, lineStart, spans);
        }
        offset = lineEnd + 1;
        continue;
      }

      if (inCodeBlock) {
        spans.add(_HighlightSpan(
          start: lineStart,
          end: lineEnd,
          color: colors.codeBlock,
        ));
        offset = lineEnd + 1;
        continue;
      }

      // 空行跳过
      if (line.trim().isEmpty) {
        offset = lineEnd + 1;
        continue;
      }

      // 标题
      final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (headingMatch != null) {
        final hashEnd = lineStart + headingMatch.group(1)!.length;
        spans.add(_HighlightSpan(
          start: lineStart,
          end: hashEnd + 1,
          color: colors.heading.withOpacity(0.5),
          fontWeight: FontWeight.bold,
        ));
        spans.add(_HighlightSpan(
          start: hashEnd + 1,
          end: lineEnd,
          color: colors.heading,
          fontWeight: FontWeight.bold,
        ));
        offset = lineEnd + 1;
        continue;
      }

      // 引用块
      final trimmedLeft = line.trimLeft();
      if (trimmedLeft.startsWith('>')) {
        final indent = line.length - trimmedLeft.length;
        spans.add(_HighlightSpan(
          start: lineStart + indent,
          end: lineStart + indent + 1,
          color: colors.blockquote.withOpacity(0.5),
          fontWeight: FontWeight.bold,
        ));
        spans.add(_HighlightSpan(
          start: lineStart + indent + 1,
          end: lineEnd,
          color: colors.blockquote,
        ));
        offset = lineEnd + 1;
        continue;
      }

      // 水平线
      if (RegExp(r'^(\s*[-*_]\s*){3,}$').hasMatch(line)) {
        spans.add(_HighlightSpan(
          start: lineStart,
          end: lineEnd,
          color: colors.horizontalRule,
        ));
        offset = lineEnd + 1;
        continue;
      }

      // 无序列表
      final ulMatch = RegExp(r'^(\s*)([-*+])\s+(.*)$').firstMatch(line);
      if (ulMatch != null) {
        final indentLen = ulMatch.group(1)!.length;
        spans.add(_HighlightSpan(
          start: lineStart + indentLen,
          end: lineStart + indentLen + 1,
          color: colors.listMarker,
          fontWeight: FontWeight.bold,
        ));
        _highlightInline(
          line.substring(indentLen + 2),
          lineStart + indentLen + 2,
          spans,
        );
        offset = lineEnd + 1;
        continue;
      }

      // 有序列表
      final olMatch = RegExp(r'^(\s*)(\d+\.)\s+(.*)$').firstMatch(line);
      if (olMatch != null) {
        final indentLen = olMatch.group(1)!.length;
        final markerLen = olMatch.group(2)!.length;
        spans.add(_HighlightSpan(
          start: lineStart + indentLen,
          end: lineStart + indentLen + markerLen,
          color: colors.listMarker,
          fontWeight: FontWeight.bold,
        ));
        _highlightInline(
          line.substring(indentLen + markerLen + 1),
          lineStart + indentLen + markerLen + 1,
          spans,
        );
        offset = lineEnd + 1;
        continue;
      }

      // 表格行
      if (line.trim().startsWith('|') && line.trim().endsWith('|')) {
        _highlightTableLine(line, lineStart, spans);
        offset = lineEnd + 1;
        continue;
      }

      // 普通文本行 — 内联高亮
      _highlightInline(line, lineStart, spans);
      offset = lineEnd + 1;
    }

    spans.sort((a, b) => a.start.compareTo(b.start));
    return _mergeOverlappingSpans(spans);
  }

  void _highlightFrontmatterLine(String line, int lineStart, List<_HighlightSpan> spans) {
    final colonIdx = line.indexOf(':');
    if (colonIdx > 0) {
      spans.add(_HighlightSpan(
        start: lineStart,
        end: lineStart + colonIdx,
        color: colors.frontmatter,
        fontWeight: FontWeight.w600,
      ));
      spans.add(_HighlightSpan(
        start: lineStart + colonIdx,
        end: lineStart + line.length,
        color: colors.plainText,
      ));
    } else {
      spans.add(_HighlightSpan(
        start: lineStart,
        end: lineStart + line.length,
        color: colors.frontmatter,
      ));
    }
  }

  void _highlightCodeBlockDelimiter(String line, int lineStart, List<_HighlightSpan> spans) {
    spans.add(_HighlightSpan(
      start: lineStart,
      end: lineStart + line.length,
      color: colors.codeBlock.withOpacity(0.6),
      fontWeight: FontWeight.bold,
    ));
  }

  void _highlightTableLine(String line, int lineStart, List<_HighlightSpan> spans) {
    if (RegExp(r'^\|[\s:-]+\|').hasMatch(line.trim())) {
      spans.add(_HighlightSpan(
        start: lineStart,
        end: lineStart + line.length,
        color: colors.table.withOpacity(0.5),
      ));
    } else {
      spans.add(_HighlightSpan(
        start: lineStart,
        end: lineStart + line.length,
        color: colors.table,
      ));
    }
  }

  void _highlightInline(String text, int baseOffset, List<_HighlightSpan> spans) {
    final patterns = <_PatternDef>[
      _PatternDef(RegExp(r'</?[a-zA-Z][a-zA-Z0-9]*(?:\s+[^>]*)?/?>'), colors.htmlTag),
      _PatternDef(RegExp(r'<!--.*?-->'), colors.comment),
      _PatternDef(RegExp(r'!\[([^\]]*)\]\(([^)]*)\)'), colors.image),
      _PatternDef(RegExp(r'\[([^\]]*)\]\(([^)]*)\)'), colors.link),
      _PatternDef(RegExp(r'`([^`]+)`'), colors.code),
      _PatternDef(RegExp(r'\*\*\*([^*]+)\*\*\*'), colors.boldItalic, bold: true, italic: true),
      _PatternDef(RegExp(r'\*\*([^*]+)\*\*'), colors.bold, bold: true),
      _PatternDef(RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)'), colors.italic, italic: true),
      _PatternDef(RegExp(r'~~([^~]+)~~'), colors.strikethrough, strikethrough: true),
      _PatternDef(RegExp(r'==([^=]+)=='), colors.highlight),
      _PatternDef(RegExp(r'\[([^\]]*)\]\[([^\]]*)\]'), colors.link),
      _PatternDef(RegExp(r'<(https?://[^>]+)>'), colors.linkUrl),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.regex.allMatches(text)) {
        final start = baseOffset + match.start;
        final end = baseOffset + match.end;
        if (!_hasOverlap(spans, start, end)) {
          spans.add(_HighlightSpan(
            start: start,
            end: end,
            color: pattern.color,
            fontWeight: pattern.bold ? FontWeight.bold : null,
            fontStyle: pattern.italic ? FontStyle.italic : null,
            decoration: pattern.strikethrough ? TextDecoration.lineThrough : null,
          ));
        }
      }
    }
  }

  bool _hasOverlap(List<_HighlightSpan> spans, int start, int end) {
    for (final s in spans) {
      if (start < s.end && end > s.start) return true;
    }
    return false;
  }

  List<_HighlightSpan> _mergeOverlappingSpans(List<_HighlightSpan> spans) {
    if (spans.length <= 1) return spans;
    final merged = <_HighlightSpan>[];
    merged.add(spans.first);
    for (var i = 1; i < spans.length; i++) {
      final last = merged.last;
      final cur = spans[i];
      if (cur.start < last.end) {
        if (cur.end - cur.start > last.end - last.start) {
          merged.last = cur;
        }
      } else {
        merged.add(cur);
      }
    }
    return merged;
  }

  @override
  void dispose() {
    _delegate.removeListener(_onDelegateChanged);
    removeListener(_onSelfChanged);
    super.dispose();
  }
}

/// 语法高亮范围
class _HighlightSpan {
  final int start;
  final int end;
  final Color color;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final TextDecoration? decoration;

  const _HighlightSpan({
    required this.start,
    required this.end,
    required this.color,
    this.fontWeight,
    this.fontStyle,
    this.decoration,
  });
}

/// Markdown 语法高亮 TextEditingController
/// 通过重写 buildTextSpan 实现语法着色
class MarkdownSyntaxController extends TextEditingController {
  final MarkdownSyntaxColors colors;
  final double fontSize;
  final String fontFamily;

  MarkdownSyntaxController({
    super.text,
    this.colors = MarkdownSyntaxColors.dark,
    this.fontSize = 14.5,
    this.fontFamily = 'monospace',
  });

  /// 更新配色方案
  void updateColors(MarkdownSyntaxColors newColors) {
    if (colors != newColors) {
      // 强制重建
      notifyListeners();
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) {
      return TextSpan(
        text: '',
        style: style?.copyWith(
          fontSize: fontSize,
          fontFamily: fontFamily,
        ),
      );
    }

    final spans = _parseHighlighting(text);
    final defaultStyle = (style ?? const TextStyle()).copyWith(
      fontSize: fontSize,
      fontFamily: fontFamily,
      color: colors.plainText,
    );

    if (spans.isEmpty) {
      return TextSpan(text: text, style: defaultStyle);
    }

    final children = <TextSpan>[];
    var cursor = 0;

    for (final span in spans) {
      if (span.start > cursor) {
        // 添加未高亮的文本
        children.add(TextSpan(
          text: text.substring(cursor, span.start),
          style: defaultStyle,
        ));
      }
      if (span.end > span.start) {
        children.add(TextSpan(
          text: text.substring(span.start, span.end),
          style: defaultStyle.copyWith(
            color: span.color,
            fontWeight: span.fontWeight ?? defaultStyle.fontWeight,
            fontStyle: span.fontStyle ?? defaultStyle.fontStyle,
            decoration: span.decoration ?? defaultStyle.decoration,
          ),
        ));
      }
      cursor = span.end;
    }

    // 剩余文本
    if (cursor < text.length) {
      children.add(TextSpan(
        text: text.substring(cursor),
        style: defaultStyle,
      ));
    }

    return TextSpan(style: defaultStyle, children: children);
  }

  /// 解析 Markdown 文本并返回高亮区间
  List<_HighlightSpan> _parseHighlighting(String text) {
    final spans = <_HighlightSpan>[];
    final lines = text.split('\n');
    var offset = 0;
    var inCodeBlock = false;
    var inFrontmatter = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineStart = offset;
      final lineEnd = offset + line.length;

      // Frontmatter 检测
      if (i == 0 && line.trim() == '---') {
        inFrontmatter = true;
        spans.add(_HighlightSpan(
          start: lineStart,
          end: lineEnd,
          color: colors.frontmatter,
          fontWeight: FontWeight.bold,
        ));
        offset = lineEnd + 1;
        continue;
      }
      if (inFrontmatter) {
        if (line.trim() == '---') {
          inFrontmatter = false;
          spans.add(_HighlightSpan(
            start: lineStart,
            end: lineEnd,
            color: colors.frontmatter,
            fontWeight: FontWeight.bold,
          ));
          offset = lineEnd + 1;
          continue;
        }
        _highlightFrontmatterLine(line, lineStart, spans);
        offset = lineEnd + 1;
        continue;
      }

      // 代码块检测
      if (line.trimLeft().startsWith('```')) {
        if (!inCodeBlock) {
          inCodeBlock = true;
          _highlightCodeBlockDelimiter(line, lineStart, spans);
        } else {
          inCodeBlock = false;
          _highlightCodeBlockDelimiter(line, lineStart, spans);
        }
        offset = lineEnd + 1;
        continue;
      }

      if (inCodeBlock) {
        spans.add(_HighlightSpan(
          start: lineStart,
          end: lineEnd,
          color: colors.codeBlock,
        ));
        offset = lineEnd + 1;
        continue;
      }

      // 空行跳过
      if (line.trim().isEmpty) {
        offset = lineEnd + 1;
        continue;
      }

      // 标题
      final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (headingMatch != null) {
        final hashEnd = lineStart + headingMatch.group(1)!.length;
        final spaceEnd = hashEnd + 1;
        spans.add(_HighlightSpan(
          start: lineStart,
          end: hashEnd,
          color: colors.heading.withOpacity(0.5),
          fontWeight: FontWeight.bold,
        ));
        spans.add(_HighlightSpan(
          start: spaceEnd,
          end: lineEnd,
          color: colors.heading,
          fontWeight: FontWeight.bold,
        ));
        offset = lineEnd + 1;
        continue;
      }

      // 引用块
      if (line.trimLeft().startsWith('>')) {
        final indent = line.length - line.trimLeft().length;
        final gtEnd = lineStart + indent + 1;
        spans.add(_HighlightSpan(
          start: lineStart + indent,
          end: gtEnd,
          color: colors.blockquote.withOpacity(0.5),
          fontWeight: FontWeight.bold,
        ));
        spans.add(_HighlightSpan(
          start: gtEnd,
          end: lineEnd,
          color: colors.blockquote,
        ));
        offset = lineEnd + 1;
        continue;
      }

      // 水平线
      if (RegExp(r'^(\s*[-*_]\s*){3,}$').hasMatch(line)) {
        spans.add(_HighlightSpan(
          start: lineStart,
          end: lineEnd,
          color: colors.horizontalRule,
        ));
        offset = lineEnd + 1;
        continue;
      }

      // 无序列表
      final ulMatch = RegExp(r'^(\s*)([-*+])\s+(.*)$').firstMatch(line);
      if (ulMatch != null) {
        final indentLen = ulMatch.group(1)!.length;
        final markerEnd = lineStart + indentLen + 1;
        spans.add(_HighlightSpan(
          start: lineStart + indentLen,
          end: markerEnd,
          color: colors.listMarker,
          fontWeight: FontWeight.bold,
        ));
        _highlightInline(
          line.substring(indentLen + 2),
          markerEnd + 1,
          spans,
        );
        offset = lineEnd + 1;
        continue;
      }

      // 有序列表
      final olMatch = RegExp(r'^(\s*)(\d+\.)\s+(.*)$').firstMatch(line);
      if (olMatch != null) {
        final indentLen = olMatch.group(1)!.length;
        final markerEnd = lineStart + indentLen + olMatch.group(2)!.length;
        spans.add(_HighlightSpan(
          start: lineStart + indentLen,
          end: markerEnd,
          color: colors.listMarker,
          fontWeight: FontWeight.bold,
        ));
        _highlightInline(
          line.substring(indentLen + olMatch.group(2)!.length + 1),
          markerEnd + 1,
          spans,
        );
        offset = lineEnd + 1;
        continue;
      }

      // 表格行
      if (line.trim().startsWith('|') && line.trim().endsWith('|')) {
        _highlightTableLine(line, lineStart, spans);
        offset = lineEnd + 1;
        continue;
      }

      // 普通文本行 — 内联高亮
      _highlightInline(line, lineStart, spans);
      offset = lineEnd + 1;
    }

    // 排序并合并重叠区间
    spans.sort((a, b) => a.start.compareTo(b.start));
    return _mergeOverlappingSpans(spans);
  }

  /// Frontmatter 行高亮
  void _highlightFrontmatterLine(String line, int lineStart, List<_HighlightSpan> spans) {
    final colonIdx = line.indexOf(':');
    if (colonIdx > 0) {
      spans.add(_HighlightSpan(
        start: lineStart,
        end: lineStart + colonIdx,
        color: colors.frontmatter,
        fontWeight: FontWeight.w600,
      ));
      spans.add(_HighlightSpan(
        start: lineStart + colonIdx,
        end: lineStart + line.length,
        color: colors.plainText,
      ));
    } else {
      spans.add(_HighlightSpan(
        start: lineStart,
        end: lineStart + line.length,
        color: colors.frontmatter,
      ));
    }
  }

  /// 代码块分隔符高亮
  void _highlightCodeBlockDelimiter(String line, int lineStart, List<_HighlightSpan> spans) {
    spans.add(_HighlightSpan(
      start: lineStart,
      end: lineStart + line.length,
      color: colors.codeBlock.withOpacity(0.6),
      fontWeight: FontWeight.bold,
    ));
  }

  /// 表格行高亮
  void _highlightTableLine(String line, int lineStart, List<_HighlightSpan> spans) {
    if (RegExp(r'^\|[\s:-]+\|').hasMatch(line.trim())) {
      // 分隔行
      spans.add(_HighlightSpan(
        start: lineStart,
        end: lineStart + line.length,
        color: colors.table.withOpacity(0.5),
      ));
    } else {
      spans.add(_HighlightSpan(
        start: lineStart,
        end: lineStart + line.length,
        color: colors.table,
      ));
    }
  }

  /// 内联语法高亮
  void _highlightInline(String text, int baseOffset, List<_HighlightSpan> spans) {
    final patterns = <_PatternDef>[
      // HTML 标签
      _PatternDef(RegExp(r'</?[a-zA-Z][a-zA-Z0-9]*(?:\s+[^>]*)?/?>'), colors.htmlTag),
      // HTML 注释
      _PatternDef(RegExp(r'<!--.*?-->'), colors.comment),
      // 图片: ![alt](url)
      _PatternDef(RegExp(r'!\[([^\]]*)\]\(([^)]*)\)'), colors.image),
      // 链接: [text](url)
      _PatternDef(RegExp(r'\[([^\]]*)\]\(([^)]*)\)'), colors.link),
      // 行内代码: `code`
      _PatternDef(RegExp(r'`([^`]+)`'), colors.code),
      // 粗斜体: ***text***
      _PatternDef(RegExp(r'\*\*\*([^*]+)\*\*\*'), colors.boldItalic, bold: true, italic: true),
      // 粗体: **text**
      _PatternDef(RegExp(r'\*\*([^*]+)\*\*'), colors.bold, bold: true),
      // 斜体: *text*
      _PatternDef(RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)'), colors.italic, italic: true),
      // 删除线: ~~text~~
      _PatternDef(RegExp(r'~~([^~]+)~~'), colors.strikethrough, strikethrough: true),
      // 高亮: ==text==
      _PatternDef(RegExp(r'==([^=]+)=='), colors.highlight),
      // 链接引用: [text][ref]
      _PatternDef(RegExp(r'\[([^\]]*)\]\[([^\]]*)\]'), colors.link),
      // 自动链接: <url>
      _PatternDef(RegExp(r'<(https?://[^>]+)>'), colors.linkUrl),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.regex.allMatches(text)) {
        final start = baseOffset + match.start;
        final end = baseOffset + match.end;
        // 检查是否与已有区间重叠
        if (!_hasOverlap(spans, start, end)) {
          spans.add(_HighlightSpan(
            start: start,
            end: end,
            color: pattern.color,
            fontWeight: pattern.bold ? FontWeight.bold : null,
            fontStyle: pattern.italic ? FontStyle.italic : null,
            decoration: pattern.strikethrough ? TextDecoration.lineThrough : null,
          ));
        }
      }
    }
  }

  bool _hasOverlap(List<_HighlightSpan> spans, int start, int end) {
    for (final s in spans) {
      if (start < s.end && end > s.start) return true;
    }
    return false;
  }

  /// 合并重叠区间
  List<_HighlightSpan> _mergeOverlappingSpans(List<_HighlightSpan> spans) {
    if (spans.length <= 1) return spans;
    final merged = <_HighlightSpan>[];
    merged.add(spans.first);
    for (var i = 1; i < spans.length; i++) {
      final last = merged.last;
      final cur = spans[i];
      if (cur.start < last.end) {
        // 重叠，保留更长的区间
        if (cur.end - cur.start > last.end - last.start) {
          merged.last = cur;
        }
      } else {
        merged.add(cur);
      }
    }
    return merged;
  }
}

/// 用于匹配的高亮模式定义
class _PatternDef {
  final RegExp regex;
  final Color color;
  final bool bold;
  final bool italic;
  final bool strikethrough;

  const _PatternDef(
    this.regex,
    this.color, {
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
  });
}