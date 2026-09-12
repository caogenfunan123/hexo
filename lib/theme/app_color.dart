/// 语义颜色令牌
/// 将散落的 `isDark ? Color(...) : Color(...)` 手写双分支收敛为语义化令牌，
/// 使亮/暗主题颜色有单一来源，避免改一处只变一处的碎片化。
///
/// 阶段0（界面改版）：色板重调为「纸感写作」主题——亮色 = 暖纸白 stone 系
/// + 单一陶土橙强调；暗色 = 暖炭黑。边框降到近乎不可见，分层靠背景色阶。
library;

import 'package:flutter/material.dart';

class AppColor {
  AppColor._();

  // ── 文字层级 ──

  /// 主文字（标题/正文）
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.92)
          : const Color(0xFF292524);

  /// 次级文字（正文/列表项）
  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.7)
          : const Color(0xFF57534E);

  /// 弱化文字（副标题/辅助信息）
  static Color textMuted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.45)
          : const Color(0xFFA8A29E);

  /// 辅助信息小字（状态栏/角标）
  static Color textSubtle(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.45)
          : const Color(0xFF78716C);

  /// 极弱文字（占位/时间戳）
  static Color textFaint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.3)
          : const Color(0xFFA8A29E);

  // ── 表面层级 ──
  // 深色值与主题（darkBgColor=0xFF1C1917, darkCardColor=0xFF292524）统一，
  // 避免桌面壳沿用旧深紫蓝系（0xFF1E1E2E 等）造成色温冲突。
  // 浅色值与 DesignConfig 同源（lightBgColor=0xFFFAF9F7, lightCardColor=0xFFFFFFFF），
  // 保证窗口原生底色 / scaffoldBackgroundColor / 面板三层同色，无灰底拼贴。

  /// 页面底色（对应 DesignConfig.lightBgColor）
  static Color surfaceBase(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1C1917)
          : const Color(0xFFFAF9F7);

  /// 面板底色（顶栏/侧栏/卡片，对应 DesignConfig.lightCardColor）
  static Color surfaceRaised(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF292524)
          : const Color(0xFFFFFFFF);

  /// 悬停/选中底色（teal 调浅色，与背景同色系）
  static Color surfaceHover(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.06)
          : const Color(0xFFF3F1EC);

  /// 深色弹层底色（菜单/弹窗）
  static Color surfaceOverlay(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF33302C)
          : Colors.white;

  // ── 边框 ──

  /// 常规分隔线（teal 调，与安卓端 divider 色系一致）
  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.06)
          : const Color(0xFFECEAE6);

  /// 强调分隔线
  static Color borderStrong(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.12)
          : const Color(0xFFDEDAD3);

  // ── 图标 ──

  /// 常规图标
  static Color icon(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.55)
          : const Color(0xFF78716C);

  /// 弱化图标
  static Color iconMuted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withOpacity(0.35)
          : const Color(0xFFA8A29E);

  // ── 状态色 ──

  /// 成功/已保存
  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF4ADE80)
          : const Color(0xFF22C55E);

  /// 警告/未保存
  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFBBF24)
          : const Color(0xFFF59E0B);

  /// 错误/失败
  static Color error(BuildContext context) => Colors.red;

  /// AI 功能强调色（AI 选区编辑/接受态）
  static Color aiAccent(BuildContext context) => const Color(0xFF7C4DFF);

  // ── Diff / 差异对比 ──

  /// 新增行背景
  static Color diffAddedBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1A3A2A)
          : const Color(0xFFE8F5E9);

  /// 新增行强调（边框/色条）
  static Color diffAddedAccent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF4CAF50)
          : const Color(0xFF66BB6A);

  /// 删除行背景
  static Color diffRemovedBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF3A1A1A)
          : const Color(0xFFFFEBEE);

  /// 删除行强调（边框/色条）
  static Color diffRemovedAccent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFEF5350)
          : const Color(0xFFEF9A9A);

  /// 修改行背景
  static Color diffModifiedBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2A2A1A)
          : const Color(0xFFFFF8E1);

  /// 修改行强调（边框/色条）
  static Color diffModifiedAccent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFFCA28)
          : const Color(0xFFFFE082);

  /// 信息/蓝色系背景（选中项、远程面板头）
  static Color infoBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2A3A5A)
          : const Color(0xFFE3F2FD);
}
