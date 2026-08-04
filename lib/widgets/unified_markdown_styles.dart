/// 统一的 Markdown 样式定义
///
/// 参考 MarkText 排版规范 + Zettlr FrontMatter 解析：
/// - 定义统一的 MarkdownStyleSheet，在桌面端和移动端共用
/// - 支持亮色/暗色主题
/// - 支持自定义字体大小
/// - 导出 createUnifiedMarkdownStyle() 工厂方法
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// 统一的 Markdown 样式配置
class UnifiedMarkdownStyleConfig {
  final double baseFontSize;
  final double lineHeight;
  final String fontFamily;
  final String codeFontFamily;
  final double headingScaleFactor;
  final double blockQuoteIndent;
  final double codeBlockFontSize;
  final double tableFontSize;
  final double horizontalPadding;

  const UnifiedMarkdownStyleConfig({
    this.baseFontSize = 16.0,
    this.lineHeight = 1.6,
    this.fontFamily = 'system',
    this.codeFontFamily = 'monospace',
    this.headingScaleFactor = 1.0,
    this.blockQuoteIndent = 16.0,
    this.codeBlockFontSize = 14.0,
    this.tableFontSize = 14.0,
    this.horizontalPadding = 16.0,
  });

  UnifiedMarkdownStyleConfig copyWith({
    double? baseFontSize,
    double? lineHeight,
    String? fontFamily,
    String? codeFontFamily,
    double? headingScaleFactor,
    double? blockQuoteIndent,
    double? codeBlockFontSize,
    double? tableFontSize,
    double? horizontalPadding,
  }) {
    return UnifiedMarkdownStyleConfig(
      baseFontSize: baseFontSize ?? this.baseFontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      codeFontFamily: codeFontFamily ?? this.codeFontFamily,
      headingScaleFactor: headingScaleFactor ?? this.headingScaleFactor,
      blockQuoteIndent: blockQuoteIndent ?? this.blockQuoteIndent,
      codeBlockFontSize: codeBlockFontSize ?? this.codeBlockFontSize,
      tableFontSize: tableFontSize ?? this.tableFontSize,
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
    );
  }
}

/// 创建统一的 Markdown 样式
///
/// 根据当前主题和配置生成统一的 [MarkdownStyleSheet]。
/// 确保桌面端和移动端渲染一致的 Markdown 视觉效果。
MarkdownStyleSheet createUnifiedMarkdownStyle({
  required BuildContext context,
  double baseFontSize = 16.0,
  double lineHeight = 1.6,
  UnifiedMarkdownStyleConfig? config,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cfg = config ?? UnifiedMarkdownStyleConfig(
    baseFontSize: baseFontSize,
    lineHeight: lineHeight,
  );

  // 基础文本颜色
  final baseTextColor = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF212121);
  final secondaryTextColor = isDark ? const Color(0xFF9E9E9E) : const Color(0xFF757575);
  final linkColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0);
  final codeBgColor = isDark ? const Color(0xFF2D2D3A) : const Color(0xFFF5F5F5);
  final blockQuoteColor = isDark ? const Color(0xFF4C4C5A) : const Color(0xFFE0E0E0);
  final tableBorderColor = isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0);
  final tableHeaderBgColor = isDark ? const Color(0xFF2D2D3A) : const Color(0xFFF5F5F5);
  final hrColor = isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0);

  // 字号
  final h1Size = cfg.baseFontSize * 2.0 * cfg.headingScaleFactor;
  final h2Size = cfg.baseFontSize * 1.75 * cfg.headingScaleFactor;
  final h3Size = cfg.baseFontSize * 1.5 * cfg.headingScaleFactor;
  final h4Size = cfg.baseFontSize * 1.25 * cfg.headingScaleFactor;
  final h5Size = cfg.baseFontSize * 1.1 * cfg.headingScaleFactor;
  final h6Size = cfg.baseFontSize * 1.0 * cfg.headingScaleFactor;

  // 构建默认样式
  final baseStyle = TextStyle(
    fontSize: cfg.baseFontSize,
    height: cfg.lineHeight,
    color: baseTextColor,
    fontFamily: cfg.fontFamily == 'system' ? null : cfg.fontFamily,
  );

  return MarkdownStyleSheet(
    // 段落
    p: baseStyle,
    // 强调
    em: baseStyle.copyWith(fontStyle: FontStyle.italic),
    strong: baseStyle.copyWith(fontWeight: FontWeight.w700),
    // 删除线
    del: baseStyle.copyWith(
      decoration: TextDecoration.lineThrough,
      color: secondaryTextColor,
    ),
    // 标题
    h1: baseStyle.copyWith(
      fontSize: h1Size,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.5,
    ),
    h2: baseStyle.copyWith(
      fontSize: h2Size,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.3,
    ),
    h3: baseStyle.copyWith(
      fontSize: h3Size,
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    h4: baseStyle.copyWith(
      fontSize: h4Size,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    h5: baseStyle.copyWith(
      fontSize: h5Size,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    h6: baseStyle.copyWith(
      fontSize: h6Size,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: secondaryTextColor,
    ),
    // 内联代码
    code: TextStyle(
      fontSize: cfg.baseFontSize * 0.9,
      fontFamily: cfg.codeFontFamily,
      color: isDark ? const Color(0xFFF48FB1) : const Color(0xFFD81B60),
      backgroundColor: codeBgColor,
      height: cfg.lineHeight,
    ),
    // 代码块
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: codeBgColor,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
        width: 0.5,
      ),
    ),
    // 引用块
    blockquote: baseStyle.copyWith(
      color: secondaryTextColor,
      fontStyle: FontStyle.italic,
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: blockQuoteColor,
          width: 3,
        ),
      ),
      color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFFAFAFA),
    ),
    blockquotePadding: const EdgeInsets.only(
      left: cfg.blockQuoteIndent,
      top: 4,
      bottom: 4,
      right: 8,
    ),
    // 链接
    a: TextStyle(
      color: linkColor,
      fontSize: cfg.baseFontSize,
      height: cfg.lineHeight,
      decoration: TextDecoration.underline,
      decorationColor: linkColor.withOpacity(0.5),
    ),
    // 列表
    listBullet: baseStyle,
    listIndent: 24.0,
    listBulletPadding: const EdgeInsets.only(right: 8),
    // 图片
    img: baseStyle,
    // 水平线
    h1Padding: const EdgeInsets.only(top: 24, bottom: 8),
    h2Padding: const EdgeInsets.only(top: 20, bottom: 6),
    h3Padding: const EdgeInsets.only(top: 16, bottom: 4),
    h4Padding: const EdgeInsets.only(top: 12, bottom: 2),
    h5Padding: const EdgeInsets.only(top: 8, bottom: 2),
    h6Padding: const EdgeInsets.only(top: 8, bottom: 2),
    pPadding: const EdgeInsets.symmetric(vertical: 4),
    // 表格样式
    tableHead: TextStyle(
      fontSize: cfg.tableFontSize,
      fontWeight: FontWeight.w600,
      color: baseTextColor,
      height: cfg.lineHeight,
    ),
    tableBody: TextStyle(
      fontSize: cfg.tableFontSize,
      color: baseTextColor,
      height: cfg.lineHeight,
    ),
    tableBorder: TableBorder(
      top: BorderSide(color: tableBorderColor, width: 0.5),
      bottom: BorderSide(color: tableBorderColor, width: 0.5),
      left: BorderSide(color: tableBorderColor, width: 0.5),
      right: BorderSide(color: tableBorderColor, width: 0.5),
      horizontalInside: BorderSide(color: tableBorderColor, width: 0.5),
      verticalInside: BorderSide(color: tableBorderColor, width: 0.5),
    ),
    tableColumnWidth: const FlexColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    tableHeadAlign: TextAlign.left,
    // 分割线
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: hrColor, width: 1),
      ),
    ),
    // 勾选框
    checkbox: TextStyle(
      fontSize: cfg.baseFontSize,
      color: baseTextColor,
      height: cfg.lineHeight,
    ),
  );
}

/// 创建 FrontMatter 样式
///
/// 用于渲染 YAML FrontMatter 区域，参考 Zettlr 的 FrontMatter 解析风格。
TextStyle createFrontMatterStyle({
  required BuildContext context,
  double fontSize = 13.0,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return TextStyle(
    fontSize: fontSize,
    fontFamily: 'monospace',
    height: 1.5,
    color: isDark ? const Color(0xFF82AAFF) : const Color(0xFF3F51B5),
    backgroundColor: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF0F4FF),
  );
}

/// 创建 FrontMatter 容器装饰
BoxDecoration createFrontMatterDecoration({
  required BuildContext context,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return BoxDecoration(
    color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF0F4FF),
    borderRadius: BorderRadius.circular(6),
    border: Border.all(
      color: isDark ? const Color(0xFF30304A) : const Color(0xFFC5CAE9),
      width: 0.5,
    ),
  );
}

/// 创建移动端适配的 Markdown 样式
///
/// 移动端字号稍小，间距稍紧凑，以适配小屏幕。
MarkdownStyleSheet createMobileMarkdownStyle({
  required BuildContext context,
  double baseFontSize = 15.0,
  double lineHeight = 1.5,
}) {
  return createUnifiedMarkdownStyle(
    context: context,
    baseFontSize: baseFontSize,
    lineHeight: lineHeight,
    config: UnifiedMarkdownStyleConfig(
      baseFontSize: baseFontSize,
      lineHeight: lineHeight,
      headingScaleFactor: 0.9,
      blockQuoteIndent: 12.0,
      horizontalPadding: 12.0,
    ),
  );
}

/// 创建桌面端适配的 Markdown 样式
///
/// 桌面端字号稍大，间距更宽松，适合大屏幕阅读。
MarkdownStyleSheet createDesktopMarkdownStyle({
  required BuildContext context,
  double baseFontSize = 17.0,
  double lineHeight = 1.7,
}) {
  return createUnifiedMarkdownStyle(
    context: context,
    baseFontSize: baseFontSize,
    lineHeight: lineHeight,
    config: UnifiedMarkdownStyleConfig(
      baseFontSize: baseFontSize,
      lineHeight: lineHeight,
      headingScaleFactor: 1.05,
      blockQuoteIndent: 20.0,
      horizontalPadding: 24.0,
    ),
  );
}

/// 获取统一的代码高亮主题颜色
class UnifiedCodeTheme {
  final Color background;
  final Color comment;
  final Color keyword;
  final Color string;
  final Color number;
  final Color function;
  final Color type;
  final Color variable;
  final Color operator;

  const UnifiedCodeTheme({
    required this.background,
    required this.comment,
    required this.keyword,
    required this.string,
    required this.number,
    required this.function,
    required this.type,
    required this.variable,
    required this.operator,
  });

  /// 亮色代码主题
  static const UnifiedCodeTheme light = UnifiedCodeTheme(
    background: Color(0xFFF5F5F5),
    comment: Color(0xFF6A737D),
    keyword: Color(0xFFD73A49),
    string: Color(0xFF032F62),
    number: Color(0xFF005CC5),
    function: Color(0xFF6F42C1),
    type: Color(0xFF22863A),
    variable: Color(0xFFE36209),
    operator: Color(0xFF005CC5),
  );

  /// 暗色代码主题
  static const UnifiedCodeTheme dark = UnifiedCodeTheme(
    background: Color(0xFF2D2D3A),
    comment: Color(0xFF8B949E),
    keyword: Color(0xFFFF7B72),
    string: Color(0xFFA5D6FF),
    number: Color(0xFF79C0FF),
    function: Color(0xFFD2A8FF),
    type: Color(0xFF7EE787),
    variable: Color(0xFFFFA657),
    operator: Color(0xFF79C0FF),
  );

  static UnifiedCodeTheme of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? dark : light;
  }
}