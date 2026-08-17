/// "全部功能"枢纽页
///
/// 收纳侧边栏全部入口（含 optIn 隐藏项），按分组网格展示。
/// 每格支持显隐开关与置顶，隐藏项始终可访问；顶部提供搜索过滤。
library;

import 'package:flutter/material.dart';

import '../models/ui_settings.dart';
import '../models/nav_custom_config.dart';
import '../desktop/shell_action_bus.dart';
import '../desktop/feature_entries.dart';
import '../desktop/nav_entries_meta.dart';
import '../theme/app_color.dart';

class AllFeaturesScreen extends StatefulWidget {
  final AppMode mode;
  final List<String> simpleModeExtras;
  final NavCustomConfig navCustom;
  final ShellActionBus? bus;

  /// 非桌面端可传入自定义入口点击处理器（替代 bus 动作映射）
  final VoidCallback Function(String entryId)? onEntryTapOverride;

  /// 打开自定义侧边栏（为空则隐藏 appbar 按钮）
  final VoidCallback? onOpenCustomize;

  final void Function(NavCustomConfig) onNavCustomChanged;

  const AllFeaturesScreen({
    super.key,
    required this.mode,
    required this.simpleModeExtras,
    required this.navCustom,
    this.bus,
    this.onEntryTapOverride,
    this.onOpenCustomize,
    required this.onNavCustomChanged,
  });

  @override
  State<AllFeaturesScreen> createState() => _AllFeaturesScreenState();
}

class _AllFeaturesScreenState extends State<AllFeaturesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 当前入口是否显示于侧边栏
  bool _isVisible(NavEntryDef def) => NavEntries.navVisibleFor(
        def.id,
        widget.mode,
        widget.simpleModeExtras,
        widget.navCustom,
      );

  /// 切换显隐
  void _toggleVisibility(NavEntryDef def, bool show) {
    final visible = Map<String, bool>.from(widget.navCustom.visible)
      ..[def.id] = show;
    // 首次自定义：标记 customized，其余未配置项回落模式默认
    widget.onNavCustomChanged(
      widget.navCustom.copyWith(
        customized: true,
        visible: visible,
      ),
    );
  }

  /// 切换置顶
  void _togglePin(NavEntryDef def) {
    var order = List<String>.from(widget.navCustom.pinnedOrder);
    order.remove(def.id);
    if (!widget.navCustom.isPinned(def.id)) {
      order.add(def.id);
    }
    widget.onNavCustomChanged(widget.navCustom.copyWith(pinnedOrder: order));
  }

  /// 搜索过滤后的入口，按分组分区
  Map<String, List<NavEntryDef>> get _groupedEntries {
    final map = <String, List<NavEntryDef>>{};
    final q = _query.trim().toLowerCase();
    for (final def in kNavEntries) {
      if (q.isNotEmpty &&
          !def.label.toLowerCase().contains(q) &&
          !def.id.toLowerCase().contains(q)) {
        continue;
      }
      map.putIfAbsent(def.group, () => []).add(def);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grouped = _groupedEntries;
    final hasAny = grouped.values.any((l) => l.isNotEmpty);

    return Scaffold(
      backgroundColor: AppColor.surfaceBase(context),
      appBar: AppBar(
        title: const Text('全部功能'),
        backgroundColor: AppColor.surfaceBase(context),
        actions: [
          if (widget.onOpenCustomize != null)
            IconButton(
              tooltip: '自定义侧边栏',
              icon: const Icon(Icons.tune),
              onPressed: widget.onOpenCustomize!,
            ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索功能…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          Expanded(
            child: hasAny
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      for (final group in kNavGroups)
                        if (grouped[group] case final entries?
                            when entries.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                            child: Text(
                              group,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColor.textSecondary(context),
                              ),
                            ),
                          ),
                          GridView.count(
                            crossAxisCount:
                                MediaQuery.sizeOf(context).width < 700 ? 2 : 4,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1.4,
                            children: [
                              for (final def in entries)
                                _buildCard(cs, def),
                            ],
                          ),
                        ],
                    ],
                  )
                : const Center(
                    child: Text('无匹配功能'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(ColorScheme cs, NavEntryDef def) {
    final visible = _isVisible(def);
    final pinned = widget.navCustom.isPinned(def.id);
    final onTapOverride = widget.onEntryTapOverride;
    final action = onTapOverride != null
        ? () => onTapOverride(def.id)
        : (widget.bus != null ? navEntryAction(widget.bus!, def.id) : null);
    final enabled = action != null;

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? action : null,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    def.icon,
                    size: 22,
                    color: enabled
                        ? cs.primary
                        : AppColor.iconMuted(context),
                    // ignore: deprecated_member_use
                    semanticLabel: def.label,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    def.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColor.textSecondary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // ignore: deprecated_member_use
                  if (!visible)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: cs.error.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '侧边栏已隐藏',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: cs.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 右上角：置顶按钮 + 显隐开关
            Positioned(
              top: 2,
              right: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    tooltip: pinned ? '取消置顶' : '置顶',
                    icon: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 15,
                      color: pinned ? cs.primary : AppColor.iconMuted(context),
                    ),
                    onPressed: () => _togglePin(def),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    tooltip: visible ? '从侧边栏隐藏' : '显示到侧边栏',
                    icon: Icon(
                      visible ? Icons.remove_circle_outline : Icons.add_circle_outline,
                      size: 15,
                      color: visible
                          ? AppColor.iconMuted(context)
                          : cs.primary,
                    ),
                    onPressed: () => _toggleVisibility(def, !visible),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}