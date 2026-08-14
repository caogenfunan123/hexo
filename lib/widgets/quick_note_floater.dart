import 'package:flutter/material.dart';

import '../services/timestamp_util.dart';

/// 悬浮速记窗（复刻 QuickDaily 悬浮速记体验）
///
/// 半透明遮罩 + 局中可拖拽悬浮卡（约屏宽 88%、高 35%）。
/// 自动聚焦输入框弹出键盘，输入自动保存，提供明确保存按钮。
class QuickNoteFloater extends StatefulWidget {
  const QuickNoteFloater({
    super.key,
    required this.initialText,
    required this.anchor,
    required this.insertTimestamp,
    required this.timestampFormatKey,
    required this.onSave,
    required this.onClose,
  });

  final String initialText;
  final String anchor;
  final bool insertTimestamp;
  final String timestampFormatKey;

  /// 保存回调（返回 true 表示保存成功，可关闭）
  final Future<bool> Function(String text) onSave;

  /// 关闭回调（未保存内容直接丢弃）
  final VoidCallback onClose;

  /// 展示悬浮速记窗
  static void show(
    BuildContext context, {
    required String initialText,
    required String anchor,
    required bool insertTimestamp,
    required String timestampFormatKey,
    required Future<bool> Function(String text) onSave,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => QuickNoteFloater(
        initialText: initialText,
        anchor: anchor,
        insertTimestamp: insertTimestamp,
        timestampFormatKey: timestampFormatKey,
        onSave: onSave,
        onClose: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<QuickNoteFloater> createState() => _QuickNoteFloaterState();
}

class _QuickNoteFloaterState extends State<QuickNoteFloater> {
  late final TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  final _scrollCtrl = ScrollController();

  // 拖拽状态
  Offset _dragOffset = Offset.zero;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      widget.onClose();
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.onSave(text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      widget.onClose();
    }
  }

  void _insertTimestamp() {
    final ts = TimestampUtil.formatKey(widget.timestampFormatKey);
    final idx = _ctrl.selection.isValid ? _ctrl.selection.start : _ctrl.text.length;
    final before = _ctrl.text.substring(0, idx);
    final after = _ctrl.text.substring(idx);
    final sep = (before.isEmpty || before.endsWith('\n')) ? '' : '\n';
    final newText = '$before$sep$ts\n$after';
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: idx + sep.length + ts.length + 1),
    );
  }

  void _insertWrap(String prefix, String suffix) {
    final sel = _ctrl.selection;
    final start = sel.isValid ? sel.start : _ctrl.text.length;
    final end = sel.isValid ? sel.end : _ctrl.text.length;
    final selected = _ctrl.text.substring(start, end);
    final before = _ctrl.text.substring(0, start);
    final after = _ctrl.text.substring(end);
    final newText = '$before$prefix$selected$suffix$after';
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + prefix.length + selected.length + suffix.length),
    );
  }

  void _insertPrefix(String prefix) {
    final idx = _ctrl.selection.isValid ? _ctrl.selection.start : _ctrl.text.length;
    final before = _ctrl.text.substring(0, idx);
    final after = _ctrl.text.substring(idx);
    final sep = (before.isEmpty || before.endsWith('\n')) ? '' : '\n';
    _ctrl.value = TextEditingValue(
      text: '$before$sep$prefix$after',
      selection: TextSelection.collapsed(offset: idx + sep.length + prefix.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width * 0.88;
    final h = size.height * 0.35;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // 半透明遮罩
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(color: Colors.black.withOpacity(0.4)),
          ),
        ),
        // 悬浮卡片（局中 + 可拖拽偏移）
        Positioned.fill(
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.center,
                child: Transform.translate(
                  offset: _dragOffset,
                  child: Container(
                    width: w,
                    height: h,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        // 标题栏（可拖拽）
                        GestureDetector(
                          onPanUpdate: (d) =>
                              setState(() => _dragOffset += d.delta),
                          onPanEnd: (_) {
                            // 弹回居中
                            setState(() => _dragOffset = Offset.zero);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.06),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.edit_note, size: 18, color: cs.primary),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    '速记',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: '关闭',
                                  onPressed: () {
                                    _save();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 输入区
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                            child: TextField(
                              controller: _ctrl,
                              focusNode: _focusNode,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              style: const TextStyle(fontSize: 15, height: 1.5),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: '记录灵感…',
                                hintStyle: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                        ),
                        // 底部工具栏
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              _toolBtn(Icons.schedule, '插入时间戳', _insertTimestamp),
                              _toolBtn(Icons.format_bold, '加粗', () {
                                _insertWrap('**', '**');
                              }),
                              _toolBtn(Icons.format_list_bulleted, '列表', () {
                                _insertPrefix('- ');
                              }),
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.check, size: 16),
                                label: const Text('保存'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(72, 36),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}
