/// 编辑器主题定义（扩展版 V2）
/// 对标 MarkText 33 主题体系，提供 12 种预设配色
/// 包含：Catppuccin、Tokyo Night、Gruvbox、Sepia 等经典主题
library;

import 'package:flutter/material.dart';

/// 编辑器主题
class EditorTheme {
  final String name;
  final Color backgroundColor;
  final Color textColor;
  final Color headingColor;
  final Color heading2Color;
  final Color heading3Color;
  final Color codeBlockBackground;
  final Color codeBlockTextColor;
  final Color linkColor;
  final Color dividerColor;
  final Color blockquoteBorderColor;
  final Color blockquoteBackground;
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

/// 预设编辑器主题集合（12 种）
const Map<String, EditorTheme> editorThemes = {
  // ── 浅色主题 ──
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
  'sepia': EditorTheme(
    name: 'Sepia',
    backgroundColor: Color(0xFFF2EBE0),
    textColor: Color(0xFF5E3D25),
    headingColor: Color(0xFF3E2312),
    heading2Color: Color(0xFF5E3D25),
    heading3Color: Color(0xFF7A5538),
    codeBlockBackground: Color(0xFFEADFD2),
    codeBlockTextColor: Color(0xFF5E3D25),
    linkColor: Color(0xFF00897B),
    dividerColor: Color(0xFFDACFC2),
    blockquoteBorderColor: Color(0xFF927966),
    blockquoteBackground: Color(0xFFE8DCCE),
    isDark: false,
  ),

  // ── 深色主题 ──
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
  'catppuccin': EditorTheme(
    name: 'Catppuccin',
    backgroundColor: Color(0xFF1E1E2E),
    textColor: Color(0xFFCDD6F4),
    headingColor: Color(0xFFCBA6F7),
    heading2Color: Color(0xFF89B4FA),
    heading3Color: Color(0xFF94E2D5),
    codeBlockBackground: Color(0xFF181825),
    codeBlockTextColor: Color(0xFFCDD6F4),
    linkColor: Color(0xFF89B4FA),
    dividerColor: Color(0xFF45475A),
    blockquoteBorderColor: Color(0xFFCBA6F7),
    blockquoteBackground: Color(0xFF313244),
    isDark: true,
  ),
  'tokyo-night': EditorTheme(
    name: 'Tokyo Night',
    backgroundColor: Color(0xFF1A1B26),
    textColor: Color(0xFFC0CAF5),
    headingColor: Color(0xFF7DCFFF),
    heading2Color: Color(0xFF9ECE6A),
    heading3Color: Color(0xFFBB9AF7),
    codeBlockBackground: Color(0xFF16161E),
    codeBlockTextColor: Color(0xFFA9B1D6),
    linkColor: Color(0xFF7AA2F7),
    dividerColor: Color(0xFF292E42),
    blockquoteBorderColor: Color(0xFF7DCFFF),
    blockquoteBackground: Color(0xFF24283B),
    isDark: true,
  ),
  'gruvbox': EditorTheme(
    name: 'Gruvbox',
    backgroundColor: Color(0xFF282828),
    textColor: Color(0xFFEBDBB2),
    headingColor: Color(0xFFFABD2F),
    heading2Color: Color(0xFFB8BB26),
    heading3Color: Color(0xFF83A598),
    codeBlockBackground: Color(0xFF1D2021),
    codeBlockTextColor: Color(0xFFEBDBB2),
    linkColor: Color(0xFF83A598),
    dividerColor: Color(0xFF504945),
    blockquoteBorderColor: Color(0xFFFABD2F),
    blockquoteBackground: Color(0xFF3C3836),
    isDark: true,
  ),
  'one-dark': EditorTheme(
    name: 'One Dark',
    backgroundColor: Color(0xFF282C34),
    textColor: Color(0xFFABB2BF),
    headingColor: Color(0xFFE06C75),
    heading2Color: Color(0xFF61AFEF),
    heading3Color: Color(0xFF98C379),
    codeBlockBackground: Color(0xFF21252B),
    codeBlockTextColor: Color(0xFFABB2BF),
    linkColor: Color(0xFF61AFEF),
    dividerColor: Color(0xFF3E4451),
    blockquoteBorderColor: Color(0xFFE5C07B),
    blockquoteBackground: Color(0xFF2C313A),
    isDark: true,
  ),
};

/// 根据主题名称获取主题
EditorTheme getEditorTheme(String themeName) {
  return editorThemes[themeName] ?? editorThemes['default']!;
}

/// 获取所有主题名称列表
List<String> get themeNames => editorThemes.keys.toList();

/// 获取浅色主题列表
List<String> get lightThemeNames =>
    editorThemes.entries.where((e) => !e.value.isDark).map((e) => e.key).toList();

/// 获取深色主题列表
List<String> get darkThemeNames =>
    editorThemes.entries.where((e) => e.value.isDark).map((e) => e.key).toList();