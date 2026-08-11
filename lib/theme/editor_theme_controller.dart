import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/editor_theme.dart';

/// 编辑器主题纯计算逻辑
///
/// 负责写作界面的背景色、全局文字色、系统栏样式的推导，不含任何
/// State/Platform 副作用，便于单元测试与在多个界面复用。
class EditorThemeController {
  EditorThemeController._();

  /// 编辑器背景颜色：纯白 / 纯黑，壁纸模式下返回透明底色
  static Color editorBgColor(EditorTheme theme) {
    return switch (theme.bgMode) {
      1 => const Color(0xFF000000),
      _ => Colors.white,
    };
  }

  /// 壁纸模式下自动适配的文字颜色（固定按亮度估算：壁纸视为中等亮度，默认黑字）
  static Color wallpaperTextColor() => Colors.black;

  /// 全局文字颜色：强制黑白 > 自动适配背景亮度
  static Color globalTextColor(EditorTheme theme) {
    final mode = theme.forceTextMode;
    if (mode == 1) return Colors.black;
    if (mode == 2) return Colors.white;
    if (theme.bgMode == 2 && theme.wallpaperPath.isNotEmpty) {
      return wallpaperTextColor();
    }
    return editorBgColor(theme).computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
  }

  /// 是否使用深色系统栏图标（浅背景黑字时用深色图标）
  static bool useDarkSystemIcons(EditorTheme theme) =>
      globalTextColor(theme).computeLuminance() > 0.5;

  /// 生成系统栏样式：编辑页跟随主题，其余页面恢复浅色默认
  static SystemUiOverlayStyle systemBarStyle({
    required bool editorPage,
    required EditorTheme theme,
  }) {
    if (!editorPage) {
      return const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.dark,
      );
    }
    final darkIcons = useDarkSystemIcons(theme);
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: darkIcons ? Brightness.dark : Brightness.light,
      statusBarBrightness: darkIcons ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: darkIcons
          ? Brightness.dark
          : Brightness.light,
    );
  }
}
