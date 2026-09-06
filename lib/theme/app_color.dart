/// 语义颜色令牌
/// 将散落的 `isDark ? Color(...) : Color(...)` 手写双分支收敛为语义化令牌，
/// 使亮/暗主题颜色有单一来源，避免改一处只变一处的碎片化。
library;

import 'package:flutter/material.dart';

class AppColor {
  AppColor._();

  // ── 文字层级 ──

  /// 主文字（标题/正文）
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.92)
          : const Color(0xFF0F172A);

  /// 次级文字（正文/列表项）
  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.7)
          : const Color(0xFF4B5563);

  /// 弱化文字（副标题/辅助信息）
  static Color textMuted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.45)
          : const Color(0xFF9CA3AF);

  /// 极弱文字（占位/时间戳）
  static Color textFaint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.3)
          : const Color(0xFF9CA3AF);

  // ── 表面层级 ──
  // 深色值与主题（darkBgColor=0xFF042F2E, darkCardColor=0xFF0F3D3A）统一，
  // 避免桌面壳沿用旧深紫蓝系（0xFF1E1E2E 等）造成色温冲突。
  // 浅色值与 DesignConfig 同源（lightBgColor=0xFFF0FDFA, lightCardColor=0xFFFFFFFF），
  // 保证窗口原生底色 / scaffoldBackgroundColor / 面板三层同色，无灰底拼贴。

  /// 页面底色（对应 DesignConfig.lightBgColor）
  static Color surfaceBase(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF042F2E)
          : const Color(0xFFF0FDFA);

  /// 面板底色（顶栏/侧栏/卡片，对应 DesignConfig.lightCardColor）
  static Color surfaceRaised(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F3D3A)
          : const Color(0xFFFFFFFF);

  /// 悬停/选中底色（teal 调浅色，与背景同色系）
  static Color surfaceHover(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.06)
          : const Color(0xFFE6F6F2);

  /// 深色弹层底色（菜单/弹窗）
  static Color surfaceOverlay(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF134E4A)
          : Colors.white;

  // ── 边框 ──

  /// 常规分隔线（teal 调，与安卓端 divider 色系一致）
  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.06)
          : const Color(0xFFD9EEE8);

  /// 强调分隔线
  static Color borderStrong(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.12)
          : const Color(0xFFD1D5DB);

  // ── 图标 ──

  /// 常规图标
  static Color icon(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.55)
          : const Color(0xFF6B7280);

  /// 弱化图标
  static Color iconMuted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.35)
          : const Color(0xFF9CA3AF);
}
