/// 编辑器主题定义
/// 提供多种预设编辑器配色方案
library;

import 'package:flutter/material.dart';

/// 编辑器主题
class EditorTheme {
  /// 主题名称
  final String name;

  /// 编辑器背景色
  final Color backgroundColor;

  /// 编辑器文本颜色
  final Color textColor;

  /// 标题文字颜色
  final Color headingColor;

  /// 二级标题颜色
  final Color heading2Color;

  /// 三级标题颜色
  final Color heading3Color;

  /// 代码块背景色
  final Color codeBlockBackground;

  /// 代码块文字颜色
  final Color codeBlockTextColor;

  /// 链接颜色
  final Color linkColor;

  /// 分隔线颜色
  final Color dividerColor;

  /// 引用块左边框颜色
  final Color blockquoteBorderColor;

  /// 引用块背景色
  final Color blockquoteBackground;

  /// 是否为暗色主题
  final bool isDark;

  const EditorTheme({
    required this.name,
    required this.backgroundColor,
    required this.textColor,
    required this.headingColor,
    required this.heading2Color,
    required this.heading3Color,
    required this.codeBlockBackground,
    required this.codeBlockTextColor,
    required this.linkColor,
    required this.dividerColor,
    required this.blockquoteBorderColor,
    required this.blockquoteBackground,
    required this.isDark,
  });
}

/// 预设编辑器主题集合
const Map<String, EditorTheme> editorThemes = {
  'default': EditorTheme(
    name: '默认',
    backgroundColor: Color(0xFFFFFFFF),
    textColor: Color(0xFF1E293B),
    headingColor: Color(0xFF0F172A),
    heading2Color: Color(0xFF1E293B),
    heading3Color: Color(0xFF334155),
    codeBlockBackground: Color(0xFFF1F5F9),
    codeBlockTextColor: Color(0xFF1E293B),
    linkColor: Color(0xFF0EA5E9),
    dividerColor: Color(0xFFE2E8F0),
    blockquoteBorderColor: Color(0xFF0EA5E9),
    blockquoteBackground: Color(0xFFF8FAFC),
    isDark: false,
  ),
  'monokai': EditorTheme(
    name: 'Monokai',
    backgroundColor: Color(0xFF272822),
    textColor: Color(0xFFF8F8F2),
    headingColor: Color(0xFFA6E22E),
    heading2Color: Color(0xFF66D9EF),
    heading3Color: Color(0xFFF92672),
    codeBlockBackground: Color(0xFF1E1F1C),
    codeBlockTextColor: Color(0xFFF8F8F2),
    linkColor: Color(0xFF66D9EF),
    dividerColor: Color(0xFF49483E),
    blockquoteBorderColor: Color(0xFFE6DB74),
    blockquoteBackground: Color(0xFF3E3D32),
    isDark: true,
  ),
  'github': EditorTheme(
    name: 'GitHub',
    backgroundColor: Color(0xFFF6F8FA),
    textColor: Color(0xFF24292E),
    headingColor: Color(0xFF1B1F23),
    heading2Color: Color(0xFF24292E),
    heading3Color: Color(0xFF444D56),
    codeBlockBackground: Color(0xFFF0F0F0),
    codeBlockTextColor: Color(0xFF24292E),
    linkColor: Color(0xFF0366D6),
    dividerColor: Color(0xFFE1E4E8),
    blockquoteBorderColor: Color(0xFF0366D6),
    blockquoteBackground: Color(0xFFF0F4F8),
    isDark: false,
  ),
  'dracula': EditorTheme(
    name: 'Dracula',
    backgroundColor: Color(0xFF282A36),
    textColor: Color(0xFFF8F8F2),
    headingColor: Color(0xFFBD93F9),
    heading2Color: Color(0xFF50FA7B),
    heading3Color: Color(0xFFFFB86C),
    codeBlockBackground: Color(0xFF21222C),
    codeBlockTextColor: Color(0xFFF8F8F2),
    linkColor: Color(0xFF8BE9FD),
    dividerColor: Color(0xFF44475A),
    blockquoteBorderColor: Color(0xFFBD93F9),
    blockquoteBackground: Color(0xFF343746),
    isDark: true,
  ),
  'nord': EditorTheme(
    name: 'Nord',
    backgroundColor: Color(0xFF2E3440),
    textColor: Color(0xFFD8DEE9),
    headingColor: Color(0xFF88C0D0),
    heading2Color: Color(0xFF81A1C1),
    heading3Color: Color(0xFFB48EAD),
    codeBlockBackground: Color(0xFF3B4252),
    codeBlockTextColor: Color(0xFFE5E9F0),
    linkColor: Color(0xFF5E81AC),
    dividerColor: Color(0xFF4C566A),
    blockquoteBorderColor: Color(0xFF88C0D0),
    blockquoteBackground: Color(0xFF3B4252),
    isDark: true,
  ),
  'solarized-light': EditorTheme(
    name: 'Solarized Light',
    backgroundColor: Color(0xFFFDF6E3),
    textColor: Color(0xFF657B83),
    headingColor: Color(0xFF073642),
    heading2Color: Color(0xFF586E75),
    heading3Color: Color(0xFF657B83),
    codeBlockBackground: Color(0xFFEEE8D5),
    codeBlockTextColor: Color(0xFF586E75),
    linkColor: Color(0xFF268BD2),
    dividerColor: Color(0xFFD3CBB7),
    blockquoteBorderColor: Color(0xFF268BD2),
    blockquoteBackground: Color(0xFFF5EFDC),
    isDark: false,
  ),
  'solarized-dark': EditorTheme(
    name: 'Solarized Dark',
    backgroundColor: Color(0xFF002B36),
    textColor: Color(0xFF839496),
    headingColor: Color(0xFFB58900),
    heading2Color: Color(0xFF2AA198),
    heading3Color: Color(0xFFD33682),
    codeBlockBackground: Color(0xFF073642),
    codeBlockTextColor: Color(0xFF93A1A1),
    linkColor: Color(0xFF268BD2),
    dividerColor: Color(0xFF586E75),
    blockquoteBorderColor: Color(0xFF2AA198),
    blockquoteBackground: Color(0xFF073642),
    isDark: true,
  ),
};

/// 根据主题名称获取主题，不存在则返回默认主题
EditorTheme getEditorTheme(String themeName) {
  return editorThemes[themeName] ?? editorThemes['default']!;
}