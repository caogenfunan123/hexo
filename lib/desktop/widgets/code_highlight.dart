/// Markdown 代码块语法高亮
/// 为预览区代码块提供语言着色
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';

const String _codeFont = 'monospace';

/// 创建 Markdown 预览区的自定义构建器映射
/// 提供代码块语法高亮、特殊块处理
Map<String, MarkdownElementBuilder> buildHighlightedBuilders(bool isDark) {
  return {
    'pre': _HighlightedCodeBuilder(isDark: isDark),
  };
}

class _HighlightedCodeBuilder extends MarkdownElementBuilder {
  final bool isDark;
  _HighlightedCodeBuilder({required this.isDark});

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final code = element.textContent;
    // 从 code 子元素中提取语言
    String? language;
    final codeChild = element.children?.firstOrNull;
    if (codeChild != null && codeChild.attributes['class'] != null) {
      final classes = codeChild.attributes['class']!.toString();
      if (classes.startsWith('language-')) {
        language = classes.substring(9);
      }
    }

    if (language != null && language.isNotEmpty) {
      final lang = language.toLowerCase().trim();
      // 特殊处理图表
      if (lang == 'mermaid' || lang == 'plantuml') {
        return _plainCodeBlock(code, isDark, label: lang.toUpperCase());
      }
      try {
        final theme = isDark ? atomOneDarkTheme : githubTheme;
        return HighlightView(
          code,
          language: lang,
          theme: theme,
          padding: const EdgeInsets.all(14),
          textStyle: const TextStyle(
            fontFamily: _codeFont,
            fontSize: 13.5,
            height: 1.5,
          ),
        );
      } catch (_) {
        return _plainCodeBlock(code, isDark, label: lang);
      }
    }

    return _plainCodeBlock(code, isDark);
  }
}

/// 普通代码块（无语法高亮）
Widget _plainCodeBlock(String code, bool isDark, {String? label}) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF6F8FA),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE5E7EB),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE5E7EB),
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white.withOpacity(0.3) : const Color(0xFF9CA3AF),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              code,
              style: TextStyle(
                fontFamily: _codeFont,
                fontSize: 13.5,
                height: 1.5,
                color: isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF374151),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}