import 'package:flutter/material.dart';

import '../models/design_config.dart';

class AppTheme {
  static const Color seed = Color(0xFF0EA5E9);
  static const bg = Color(0xFFF0F4F8);
  static const card = Colors.white;
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const divider = Color(0xFFE2E8F0);
  static const accent = Color(0xFF0EA5E9);
  static const accentPurple = Color(0xFF8B5CF6);
  static const accentGreen = Color(0xFF10B981);
  static const accentOrange = Color(0xFFF59E0B);
  static const accentRed = Color(0xFFEF4444);

  // ── 根据 DesignConfig 动态生成主题 ──

  /// 浅色主题（基于 DesignConfig）
  static ThemeData lightFromConfig(DesignConfig dc) {
    final seedColor = Color(dc.seedColor);
    final bgColor = Color(dc.lightBgColor);
    final cardColor = Color(dc.lightCardColor);
    final textColor = Color(dc.lightTextColor);
    final dividerColor = Color(dc.lightTextColor).withOpacity(0.08);

    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
      surface: bgColor,
    );

    final baseRadius = 12.0 * dc.borderRadiusScale;
    final basePadding = 14.0 * dc.paddingScale;
    final baseFontScale = dc.fontScale;

    return _buildTheme(
      scheme: scheme,
      brightness: Brightness.light,
      bgColor: bgColor,
      cardColor: cardColor,
      textColor: textColor,
      dividerColor: dividerColor,
      baseRadius: baseRadius,
      basePadding: basePadding,
      fontScale: baseFontScale,
      density: dc.density,
      enableBlur: dc.enableBlur,
    );
  }

  /// 深色主题（基于 DesignConfig）
  static ThemeData darkFromConfig(DesignConfig dc) {
    final seedColor = Color(dc.seedColor);
    final bgColor = Color(dc.darkBgColor);
    final cardColor = Color(dc.darkCardColor);
    final textColor = Colors.white;
    final dividerColor = Colors.white.withOpacity(0.06);

    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    final baseRadius = 12.0 * dc.borderRadiusScale;
    final basePadding = 14.0 * dc.paddingScale;
    final baseFontScale = dc.fontScale;

    return _buildTheme(
      scheme: scheme,
      brightness: Brightness.dark,
      bgColor: bgColor,
      cardColor: cardColor,
      textColor: textColor,
      dividerColor: dividerColor,
      baseRadius: baseRadius,
      basePadding: basePadding,
      fontScale: baseFontScale,
      density: dc.density,
      enableBlur: dc.enableBlur,
    );
  }

  /// 统一主题构建（内部方法）
  static ThemeData _buildTheme({
    required ColorScheme scheme,
    required Brightness brightness,
    required Color bgColor,
    required Color cardColor,
    required Color textColor,
    required Color dividerColor,
    required double baseRadius,
    required double basePadding,
    required double fontScale,
    required int density,
    required bool enableBlur,
  }) {
    final isLight = brightness == Brightness.light;
    final titleFontSize = 18.0 * fontScale;
    final bodyFontSize = 14.0 * fontScale;
    final labelFontSize = 14.0 * fontScale;

    // 视觉密度映射
    final visualDensity = switch (density) {
      0 => VisualDensity.compact,
      2 => VisualDensity.comfortable,
      _ => VisualDensity.standard,
    };

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgColor,
      visualDensity: visualDensity,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: cardColor,
        foregroundColor: textColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.04),
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: titleFontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(baseRadius * 1.5)),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(baseRadius * 1.2),
          side: BorderSide(
            color: isLight
                ? Colors.black.withOpacity(0.05)
                : Colors.white.withOpacity(0.05),
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFF8FAFC) : cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(baseRadius),
          borderSide: BorderSide(color: dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(baseRadius),
          borderSide: BorderSide(color: dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(baseRadius),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(baseRadius),
          borderSide: const BorderSide(color: accentRed),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: basePadding),
        labelStyle: TextStyle(color: muted, fontSize: labelFontSize),
        hintStyle: TextStyle(
          color: isLight ? Colors.grey.shade400 : Colors.white.withOpacity(0.3),
          fontSize: labelFontSize,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(baseRadius * 1.2)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(baseRadius * 1.5),
        ),
        backgroundColor: scheme.primary.withOpacity(0.06),
        selectedColor: scheme.primary.withOpacity(0.12),
        labelStyle: TextStyle(fontSize: 12 * fontScale, fontWeight: FontWeight.w500),
        side: BorderSide.none,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(baseRadius * 2)),
        backgroundColor: cardColor,
        elevation: 8,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: titleFontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(baseRadius)),
        backgroundColor: textColor,
        contentTextStyle: TextStyle(color: bgColor, fontSize: bodyFontSize),
      ),
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: basePadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(baseRadius),
          ),
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15 * fontScale,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withOpacity(0.3)),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: basePadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(baseRadius),
          ),
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15 * fontScale,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14 * fontScale),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(baseRadius * 1.5),
            bottomRight: Radius.circular(baseRadius * 1.5),
          ),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(fontSize: 16 * fontScale, color: textColor),
        bodyMedium: TextStyle(fontSize: bodyFontSize, color: textColor),
        bodySmall: TextStyle(fontSize: 12 * fontScale, color: textColor.withOpacity(0.7)),
        titleLarge: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w700, color: textColor),
        titleMedium: TextStyle(fontSize: 16 * fontScale, fontWeight: FontWeight.w600, color: textColor),
        titleSmall: TextStyle(fontSize: 14 * fontScale, fontWeight: FontWeight.w600, color: textColor),
        labelLarge: TextStyle(fontSize: 14 * fontScale, fontWeight: FontWeight.w500, color: textColor),
        labelSmall: TextStyle(fontSize: 11 * fontScale, color: muted),
      ),
    );
  }

  // ── 原有静态方法保留（向后兼容） ──

  static ThemeData light({int? seedColor}) {
    final localSeed = Color(seedColor ?? 0xFF0EA5E9);
    final scheme = ColorScheme.fromSeed(
      seedColor: localSeed,
      brightness: Brightness.light,
      surface: bg,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.04),
        titleTextStyle: const TextStyle(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.black.withOpacity(0.05)),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentRed),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: TextStyle(color: muted, fontSize: 14),
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: scheme.primary.withOpacity(0.06),
        selectedColor: scheme.primary.withOpacity(0.12),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        elevation: 8,
        titleTextStyle: const TextStyle(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: text,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withOpacity(0.3)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
      ),
    );
  }

  static ThemeData dark({int? seedColor}) {
    final localSeed = Color(seedColor ?? 0xFF0EA5E9);
    final scheme = ColorScheme.fromSeed(
      seedColor: localSeed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E293B),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 8,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF334155),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade800,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withOpacity(0.3)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: const Color(0xFF1E293B),
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}