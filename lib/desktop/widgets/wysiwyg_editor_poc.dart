/// 阶段2 Spike：super_editor 所见即所得编辑器（实验）
///
/// 数据流：markdown 进 → deserializeMarkdownToDocument → SuperEditor 富文本编辑
/// → 文档变更防抖 250ms → serializeDocumentToMarkdown → markdown 出。
/// 与发布链路解耦：主编辑器内容经「应用」一次性写回，不满意可取消。
///
/// 已知边界（spike 范围外，见 docs/fixes/ui-phase2-wysiwyg-spike.md）：
/// frontmatter 由调用方原样保留、图片仅支持网络图、表格/任务列表依赖包内语法支持。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 所见即所得编辑器（markdown 双向绑定）
class WysiwygEditorPoc extends StatefulWidget {
  final String initialMarkdown;
  final ValueChanged<String>? onMarkdownChanged;

  const WysiwygEditorPoc({
    super.key,
    required this.initialMarkdown,
    this.onMarkdownChanged,
  });

  @override
  State<WysiwygEditorPoc> createState() => _WysiwygEditorPocState();
}

class _WysiwygEditorPocState extends State<WysiwygEditorPoc> {
  late MutableDocument _doc;
  late MutableDocumentComposer _composer;
  late Editor _editor;
  Timer? _debounce;
  bool _serializing = false;

  @override
  void initState() {
    super.initState();
    _doc = deserializeMarkdownToDocument(widget.initialMarkdown);
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(document: _doc, composer: _composer);
    _doc.addListener(_onDocChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _doc.removeListener(_onDocChanged);
    _doc.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _onDocChanged(_) {
    if (_serializing) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      // 序列化不改文档，此开关防的是「外层又把新 markdown 回灌本组件」的回环
      _serializing = true;
      try {
        final md = serializeDocumentToMarkdown(_doc);
        widget.onMarkdownChanged?.call(md);
      } finally {
        _serializing = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SuperEditor(
      editor: _editor,
      componentBuilders: [
        TaskComponentBuilder(_editor),
        ...defaultComponentBuilders,
      ],
      stylesheet: defaultStylesheet.copyWith(
        documentPadding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
        addRulesAfter: [
          StyleRule(
            BlockSelector.all,
            (doc, docNode) => {
              'backgroundColor': Colors.transparent,
              'color': isDark ? const Color(0xFFE7E5E4) : const Color(0xFF292524),
            },
          ),
        ],
      ),
    );
  }
}

/// 全屏实验对话框：所见即所得编辑 → 「应用」把 markdown 写回主编辑器
class WysiwygPocDialog extends StatefulWidget {
  final String initialMarkdown;

  const WysiwygPocDialog({super.key, required this.initialMarkdown});

  @override
  State<WysiwygPocDialog> createState() => _WysiwygPocDialogState();
}

class _WysiwygPocDialogState extends State<WysiwygPocDialog> {
  late String _markdown;

  @override
  void initState() {
    super.initState();
    _markdown = widget.initialMarkdown;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 8),
                  Text(
                    '所见即所得编辑（实验）',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_markdown),
                    child: const Text('应用回编辑器'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: WysiwygEditorPoc(
                  initialMarkdown: widget.initialMarkdown,
                  onMarkdownChanged: (md) => _markdown = md,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
