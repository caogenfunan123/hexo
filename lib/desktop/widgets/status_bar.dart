/// 桌面版底部状态栏
/// 显示：工作模式切换、行号/列号、字数统计、编辑器状态、同步状态
library;

import 'package:flutter/material.dart';
import 'work_mode.dart';

class DesktopStatusBar extends StatelessWidget {
  final WorkMode workMode;
  final ValueChanged<WorkMode> onModeChange;

  /// 编辑器状态文本
  final String? editorStatus;

  /// 光标位置 (行, 列)
  final (int, int)? cursorPosition;

  /// 字数统计
  final int? wordCount;

  /// 字符数统计
  final int? charCount;

  /// 当前站点名称
  final String? siteName;

  /// 同步状态
  final String? syncStatus;

  /// 是否正在同步
  final bool isSyncing;

  const DesktopStatusBar({
    super.key,
    required this.workMode,
    required this.onModeChange,
    this.editorStatus,
    this.cursorPosition,
    this.wordCount,
    this.charCount,
    this.siteName,
    this.syncStatus,
    this.isSyncing = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withOpacity(0.2)),
        ),
      ),
      child: Row(
        children: [
          // ── 左侧：工作模式 ──
          _modeButton(context, WorkMode.workspace, Icons.dashboard, '工作台'),
          _modeButton(context, WorkMode.focus, Icons.auto_awesome, '专注'),
          _modeButton(context, WorkMode.source, Icons.code, '源码'),

          const SizedBox(width: 12),
          // 编辑器状态
          if (editorStatus != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                editorStatus!,
                style: TextStyle(fontSize: 10, color: cs.primary),
              ),
            ),
          ],

          const Spacer(),

          // ── 右侧：统计信息 ──
          if (cursorPosition case (final row, final col))
            _statusChip(context, '$row:$col', Icons.pin),
          if (wordCount != null)
            _statusChip(context, '$wordCount 词', Icons.text_fields),
          if (charCount != null)
            _statusChip(context, '$charCount 字', Icons.abc),

          if (isSyncing) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.primary),
            ),
          ] else if (syncStatus != null) ...[
            _statusChip(context, syncStatus!, Icons.cloud_done_outlined),
          ],

          if (siteName != null) ...[
            const SizedBox(width: 8),
            _statusChip(context, siteName!, Icons.language),
          ],
        ],
      ),
    );
  }

  Widget _modeButton(BuildContext context, WorkMode mode, IconData icon, String label) {
    final isActive = workMode == mode;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onModeChange(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isActive ? cs.primary : cs.onSurface.withOpacity(0.4)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? cs.primary : cs.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, String text, IconData? icon) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: cs.onSurface.withOpacity(0.35)),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.4), fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}