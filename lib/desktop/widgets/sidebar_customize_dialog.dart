/// 自定义侧边栏对话框
///
/// 分组分区列出全部入口，每项提供显隐开关与置顶按钮，实时生效。
/// "恢复默认"重置 customized/visible/pinnedOrder。
library;

import 'package:flutter/material.dart';

import '../../theme/app_color.dart';
import '../../models/ui_settings.dart';
import '../../models/nav_custom_config.dart';
import '../../desktop/nav_entries_meta.dart';

Future<void> showSidebarCustomizeDialog({
  required BuildContext context,
  required AppMode mode,
  required List<String> simpleModeExtras,
  required NavCustomConfig navCustom,
  required ValueChanged<NavCustomConfig> onNavCustomChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SidebarCustomizeDialog(
      mode: mode,
      simpleModeExtras: simpleModeExtras,
      navCustom: navCustom,
      onNavCustomChanged: onNavCustomChanged,
    ),
  );
}

class _SidebarCustomizeDialog extends StatefulWidget {
  final AppMode mode;
  final List<String> simpleModeExtras;
  final NavCustomConfig navCustom;
  final ValueChanged<NavCustomConfig> onNavCustomChanged;

  const _SidebarCustomizeDialog({
    required this.mode,
    required this.simpleModeExtras,
    required this.navCustom,
    required this.onNavCustomChanged,
  });

  @override
  State<_SidebarCustomizeDialog> createState() =>
      _SidebarCustomizeDialogState();
}

class _SidebarCustomizeDialogState extends State<_SidebarCustomizeDialog> {
  late NavCustomConfig _cfg = widget.navCustom;

  void _update(NavCustomConfig cfg) {
    setState(() => _cfg = cfg);
    widget.onNavCustomChanged(cfg);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('自定义侧边栏'),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '勾选要显示在侧边栏的入口，未勾选项仍可在"全部功能"中访问。',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('恢复默认'),
                onPressed: () => _update(NavCustomConfig(
                  customized: false,
                )),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final group in kNavGroups)
                    ..._buildGroup(cs, group),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }

  List<Widget> _buildGroup(ColorScheme cs, String group) {
    final defs = kNavEntries.where((d) => d.group == group).toList();
    if (defs.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text(
          group,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
      ),
      for (final def in defs) _buildRow(cs, def),
    ];
  }

  Widget _buildRow(ColorScheme cs, NavEntryDef def) {
    // 未自定义时按模式默认判断当前显示
    bool current() {
      if (_cfg.hasOverride(def.id)) return _cfg.visible[def.id] ?? false;
      return _modeDefault(def.id);
    }

    final shown = current();
    final pinned = _cfg.isPinned(def.id);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(def.icon, size: 18, color: AppColor.icon(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(def.label, style: const TextStyle(fontSize: 13.5)),
          ),
          // 置顶
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: pinned ? '取消置顶' : '置顶到顶部',
            icon: Icon(
              pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 16,
              color: pinned ? cs.primary : AppColor.iconMuted(context),
            ),
            onPressed: () {
              var order = List<String>.from(_cfg.pinnedOrder);
              order.remove(def.id);
              if (!pinned) order.add(def.id);
              _update(_cfg.copyWith(pinnedOrder: order));
            },
          ),
          // 显隐开关
          Switch(
            value: shown,
            onChanged: (v) {
              final visible = Map<String, bool>.from(_cfg.visible)
                ..[def.id] = v;
              _update(_cfg.copyWith(customized: true, visible: visible));
            },
          ),
        ],
      ),
    );
  }

  /// 模式默认可见性
  bool _modeDefault(String id) {
    final vis = NavEntries.visibleEntryOrDefault(id, widget.mode);
    return vis;
  }
}