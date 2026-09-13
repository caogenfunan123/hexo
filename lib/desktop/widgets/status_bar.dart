/// 桌面端底部状态栏
/// 专业桌面端设计：简洁的信息展示 + 自动保存指示器
library;

import 'package:flutter/material.dart';
import '../../theme/app_color.dart';
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
      height: 30,
      decoration: BoxDecoration(
        color: AppColor.surfaceRaised(context),
        border: Border(
          top: BorderSide(color: AppColor.border(context)),
        ),
      ),
      child: Row(
        children: [
          // 保存状态指示器
          _buildSaveIndicator(context, cs),

          const SizedBox(width: 8),

          // 工作模式切换
          _modeButton(context,
            label: '工作台',
            icon: Icons.space_dashboard,
            active: workMode == WorkMode.workspace,
            onTap: () => onModeChange(WorkMode.workspace),
            cs: cs,
          ),
          _modeButton(context,
            label: '专注',
            icon: Icons.visibility,
            active: workMode == WorkMode.focus,
            onTap: () => onModeChange(WorkMode.focus),
            cs: cs,
          ),
          _modeButton(context,
            label: '画布',
            icon: Icons.auto_stories,
            active: workMode == WorkMode.source,
            onTap: () => onModeChange(WorkMode.source),
            cs: cs,
          ),

          // 状态信息：窄窗时横向滚动，避免 Row 溢出
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 编辑器状态信息
                  if (editorStatus != null)
                    _statusLabel(context,
                      editorStatus!,
                      isDark: isDark,
                    ),

                  // 光标位置
                  if (cursorPosition != null) ...[
                    const SizedBox(width: 12),
                    _statusLabel(context,
                      '行 ${cursorPosition!.$1} 列 ${cursorPosition!.$2}',
                      isDark: isDark,
                    ),
                  ],

                  // 行数
                  const SizedBox(width: 12),
                  _statusLabel(context,
                    '$lineCount 行',
                    isDark: isDark,
                  ),

                  // 字数统计
                  const SizedBox(width: 12),
                  _statusLabel(context,
                    '$wordCount 词',
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _statusLabel(context,
                    '$charCount 字',
                    isDark: isDark,
                  ),

                  // 阅读时间
                  if (readTime.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    _statusLabel(context,
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
                    _statusLabel(context,
                      siteName.isNotEmpty ? siteName : '未连接',
                      icon: Icons.cloud_outlined,
                      isDark: isDark,
                    ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 自动保存指示器圆点
  Widget _buildSaveIndicator(BuildContext context, ColorScheme cs) {
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
                  ? AppColor.success(context)
                  : AppColor.warning(context),
              boxShadow: isSaved ? null : [
                BoxShadow(
                  color: AppColor.warning(context).withOpacity(0.4),
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
              fontSize: 12,
              color: isSaved
                  ? AppColor.success(context)
                  : AppColor.warning(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        height: 30,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? cs.primary : AppColor.iconMuted(context),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? cs.primary : AppColor.iconMuted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusLabel(
    BuildContext context,
    String text, {
    IconData? icon,
    bool isDark = false,
  }) {
    final useDark = isDark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 13,
            color: AppColor.iconMuted(context),
          ),
          const SizedBox(width: 5),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: useDark
                ? Colors.white.withOpacity(0.25)
                : AppColor.textMuted(context),
          ),
        ),
      ],
    );
  }
}