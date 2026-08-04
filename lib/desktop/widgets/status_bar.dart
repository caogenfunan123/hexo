/// 桌面端底部状态栏
/// 专业桌面端设计：简洁的信息展示 + 自动保存指示器
library;

import 'package:flutter/material.dart';
import 'work_mode.dart';

class DesktopStatusBar extends StatelessWidget {
  final WorkMode workMode;
  final ValueChanged<WorkMode> onModeChange;
  final String? editorStatus;
  final (int, int)? cursorPosition;
  final int wordCount;
  final int charCount;
  final String siteName;
  final bool isSyncing;
  final bool isSaved; // 自动保存指示器
  final int lineCount; // 总行数
  final String readTime; // 阅读时间

  const DesktopStatusBar({
    super.key,
    required this.workMode,
    required this.onModeChange,
    this.editorStatus,
    this.cursorPosition,
    this.wordCount = 0,
    this.charCount = 0,
    this.siteName = '',
    this.isSyncing = false,
    this.isSaved = true,
    this.lineCount = 0,
    this.readTime = '',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF252536)
            : const Color(0xFFFAFAFC),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : const Color(0xFFE5E5EA),
          ),
        ),
      ),
      child: Row(
        children: [
          // 保存状态指示器
          _buildSaveIndicator(isDark, cs),

          const SizedBox(width: 8),

          // 工作模式切换
          _modeButton(
            label: '工作台',
            icon: Icons.space_dashboard,
            active: workMode == WorkMode.workspace,
            onTap: () => onModeChange(WorkMode.workspace),
            cs: cs,
            isDark: isDark,
          ),
          _modeButton(
            label: '专注',
            icon: Icons.visibility,
            active: workMode == WorkMode.focus,
            onTap: () => onModeChange(WorkMode.focus),
            cs: cs,
            isDark: isDark,
          ),
          _modeButton(
            label: '源码',
            icon: Icons.code,
            active: workMode == WorkMode.source,
            onTap: () => onModeChange(WorkMode.source),
            cs: cs,
            isDark: isDark,
          ),

          const Spacer(),

          // 编辑器状态信息
          if (editorStatus != null)
            _statusLabel(
              editorStatus!,
              isDark: isDark,
            ),

          // 光标位置
          if (cursorPosition != null) ...[
            const SizedBox(width: 12),
            _statusLabel(
              '行 ${cursorPosition!.$1} 列 ${cursorPosition!.$2}',
              isDark: isDark,
            ),
          ],

          // 行数
          const SizedBox(width: 12),
          _statusLabel(
            '$lineCount 行',
            isDark: isDark,
          ),

          // 字数统计
          const SizedBox(width: 12),
          _statusLabel(
            '$wordCount 词',
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _statusLabel(
            '$charCount 字',
            isDark: isDark,
          ),

          // 阅读时间
          if (readTime.isNotEmpty) ...[
            const SizedBox(width: 12),
            _statusLabel(
              readTime,
              icon: Icons.timer_outlined,
              isDark: isDark,
            ),
          ],

          // 同步状态
          const SizedBox(width: 12),
          if (isSyncing)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          else
            _statusLabel(
              siteName.isNotEmpty ? siteName : '未连接',
              icon: Icons.cloud_outlined,
              isDark: isDark,
            ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  /// 自动保存指示器圆点
  Widget _buildSaveIndicator(bool isDark, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSaved
                  ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF22C55E))
                  : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B)),
              boxShadow: isSaved ? null : [
                BoxShadow(
                  color: (isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B)).withOpacity(0.4),
                  blurRadius: 4,
                  spreadRadius: 0.5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isSaved ? '已保存' : '未保存',
            style: TextStyle(
              fontSize: 10,
              color: isSaved
                  ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF22C55E))
                  : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B)),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    required ColorScheme cs,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        height: 28,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: active
                  ? cs.primary
                  : (isDark ? Colors.white.withOpacity(0.35) : const Color(0xFF9CA3AF)),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active
                    ? cs.primary
                    : (isDark ? Colors.white.withOpacity(0.35) : const Color(0xFF9CA3AF)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusLabel(
    String text, {
    IconData? icon,
    bool isDark = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 10,
            color: isDark
                ? Colors.white.withOpacity(0.25)
                : const Color(0xFFD1D5DB),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: isDark
                ? Colors.white.withOpacity(0.25)
                : const Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }
}