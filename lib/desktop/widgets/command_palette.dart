/// 快捷键命令面板（Command Palette）
/// 对标 VS Code Ctrl+Shift+P / Ctrl+K 命令面板
/// 搜索所有可用操作，键盘导航，Enter 执行
library;

import 'package:flutter/material.dart';
import '../../../theme/app_color.dart';
import 'package:flutter/services.dart';

/// 命令面板中的单个命令项
class CommandItem {
  final String label;
  final String category;
  final String shortcut;
  final IconData icon;
  final VoidCallback onExecute;

  const CommandItem({
    required this.label,
    required this.category,
    required this.shortcut,
    required this.icon,
    required this.onExecute,
  });

  String get searchText => '$label $category $shortcut'.toLowerCase();
}

/// 命令面板
class CommandPalette extends StatefulWidget {
  final List<CommandItem> commands;
  final VoidCallback onClose;

  const CommandPalette({
    super.key,
    required this.commands,
    required this.onClose,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollCtrl = ScrollController();
  int _selectedIndex = 0;
  List<CommandItem> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.commands);
    _focusNode.requestFocus();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearch);
    _searchCtrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filtered = List.from(widget.commands);
      } else {
        _filtered = widget.commands
            .where((c) => c.searchText.contains(query))
            .toList();
      }
      _selectedIndex = _filtered.isNotEmpty ? 0 : -1;
    });
  }

  void _execute(int index) {
    if (index < 0 || index >= _filtered.length) return;
    widget.onClose();
    _filtered[index].onExecute();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_filtered.isEmpty) return;
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, _filtered.length - 1);
      });
      _scrollToSelected();
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_filtered.isEmpty) return;
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, _filtered.length - 1);
      });
      _scrollToSelected();
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _execute(_selectedIndex);
      return;
    }
  }

  void _scrollToSelected() {
    if (!_scrollCtrl.hasClients) return;
    final itemHeight = 44.0;
    final viewportHeight = _scrollCtrl.position.viewportDimension;
    final targetY = _selectedIndex * itemHeight;
    if (targetY < _scrollCtrl.offset) {
      _scrollCtrl.jumpTo(targetY);
    } else if (targetY + itemHeight > _scrollCtrl.offset + viewportHeight) {
      _scrollCtrl.jumpTo(targetY - viewportHeight + itemHeight);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black.withOpacity(0.4),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 560,
              constraints: const BoxConstraints(maxHeight: 480),
              decoration: BoxDecoration(
                color: AppColor.surfaceBase(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColor.border(context),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: KeyboardListener(
                focusNode: _focusNode,
                onKeyEvent: _handleKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 搜索框
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: AppColor.border(context),
                          ),
                        ),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _focusNode,
                        autofocus: true,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColor.textPrimary(context),
                        ),
                        decoration: InputDecoration(
                          hintText: '输入命令名称搜索...',
                          hintStyle: TextStyle(
                            color: AppColor.textMuted(context),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          prefixIcon: Icon(
                            Icons.search,
                            size: 18,
                            color: AppColor.textMuted(context),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),

                    // 命令列表
                    Flexible(
                      child: _filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                '无匹配命令',
                                style: TextStyle(
                                  color: AppColor.textMuted(context),
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollCtrl,
                              shrinkWrap: true,
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final cmd = _filtered[i];
                                final selected = i == _selectedIndex;
                                return GestureDetector(
                                  onTap: () => _execute(i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 100),
                                    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? cs.primary.withOpacity(isDark ? 0.2 : 0.1)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          cmd.icon,
                                          size: 16,
                                          color: selected
                                              ? cs.primary
                                              : (AppColor.icon(context)),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                cmd.label,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                                  color: AppColor.textPrimary(context),
                                                ),
                                              ),
                                              Text(
                                                cmd.category,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppColor.textMuted(context),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColor.surfaceHover(context),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            cmd.shortcut,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontFamily: 'monospace',
                                              color: AppColor.icon(context),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),

                    // 底部提示
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: AppColor.border(context),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          _hintKey('↑↓', '导航', isDark),
                          const SizedBox(width: 12),
                          _hintKey('Enter', '执行', isDark),
                          const SizedBox(width: 12),
                          _hintKey('Esc', '关闭', isDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hintKey(String key, String label, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: AppColor.border(context),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: AppColor.icon(context),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColor.textMuted(context),
          ),
        ),
      ],
    );
  }
}