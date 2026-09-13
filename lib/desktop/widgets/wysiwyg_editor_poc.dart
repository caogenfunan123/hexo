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
        // 表格组件默认不在 defaultComponentBuilders 里，缺了表格只解析不渲染
        const MarkdownTableComponentBuilder(),
        ...defaultComponentBuilders,
      ],
      stylesheet: defaultStylesheet.copyWith(
        documentPadding: const EdgeInsets.symmetric(
          vertical: 24,
          horizontal: 8,
        ),
        addRulesAfter: [
          StyleRule(
            BlockSelector.all,
            (doc, docNode) => {
              'backgroundColor': Colors.transparent,
              'color': isDark
                  ? const Color(0xFFE7E5E4)
                  : const Color(0xFF292524),
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

/// 所见即所得主编辑器（阶段2.5：替换主编辑区）
///
/// 与外部 TextEditingController 双向绑定：
/// - 用户在富文本里编辑 → 防抖 250ms 序列化 markdown 写回 controller
///   （触发 shell 既有链路：自动保存/字数统计/状态栏）；
/// - 外部程序化改动（AI 改写/查找替换/片段插入/切文章）→ 检测文本差异后
///   整体重建文档（光标复位，属预期行为）；
/// - frontmatter（--- 块）不参与富文本编辑：解析时拆出保管，写回时原样前置，
///   属性编辑仍走工作区属性面板/源码模式。
class WysiwygMainEditor extends StatefulWidget {
  final TextEditingController controller;
  final double? maxWidth;

  /// 正文文字色；为空时跟随明暗主题默认（壁纸/纯黑背景下由调用方传
  /// `_deskTextColor` 自动适配色，保证可读）
  final Color? textColor;

  const WysiwygMainEditor({
    super.key,
    required this.controller,
    this.maxWidth,
    this.textColor,
  });

  @override
  State<WysiwygMainEditor> createState() => _WysiwygMainEditorState();
}

class _WysiwygMainEditorState extends State<WysiwygMainEditor> {
  static final _frontmatterRegex = RegExp(
    '^' + r'-{3}[\s\S]*?-{3}' + r'\r?\n?',
  );

  MutableDocument? _doc;
  MutableDocumentComposer? _composer;
  Editor? _editor;
  int _generation = 0; // 文档代数：外部重建后迫使 SuperEditor 重挂载
  String _frontmatter = '';
  String _lastBody = '';
  Timer? _debounce;
  bool _writingBack = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _rebuildDocument(widget.controller.text);
  }

  @override
  void didUpdateWidget(covariant WysiwygMainEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _rebuildDocument(widget.controller.text);
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // 切模式/关标签销毁本组件前，把防抖中未写回的编辑强制同步回 controller，
    // 否则最后一次防抖窗口（≤250ms）内的输入会静默丢失
    // 先摘掉自己的监听再落盘：controller.text= 会同步通知监听者，
    // 若通知打到已 defunct 的本元素会触发框架断言
    widget.controller.removeListener(_onControllerChanged);
    final doc = _doc;
    if (doc != null) {
      try {
        final body = serializeDocumentToMarkdown(doc);
        final full = _frontmatter + body;
        if (widget.controller.text != full) {
          widget.controller.text = full;
        }
      } catch (_) {
        // 序列化异常时放弃本次同步，避免阻塞销毁流程
      }
    }
    _disposeDocument();
    super.dispose();
  }

  void _disposeDocument() {
    final doc = _doc;
    if (doc != null) doc.removeListener(_onDocChanged);
    _doc?.dispose();
    _composer?.dispose();
    _doc = null;
    _composer = null;
    _editor = null;
  }

  void _rebuildDocument(String fullText) {
    _disposeDocument();
    final m = _frontmatterRegex.firstMatch(fullText);
    _frontmatter = m?.group(0) ?? '';
    final body = fullText.substring(_frontmatter.length);
    _lastBody = body;
    final doc = deserializeMarkdownToDocument(body);
    doc.addListener(_onDocChanged);
    final composer = MutableDocumentComposer();
    _doc = doc;
    _composer = composer;
    _editor = createDefaultDocumentEditor(document: doc, composer: composer);
    _generation++;
  }

  /// 外部文本变化（AI/查找替换/片段插入/程序化写入）：整体重建文档
  void _onControllerChanged() {
    if (_writingBack) return;
    final full = widget.controller.text;
    if (full == _frontmatter + _lastBody) return; // 自己写回的回环
    _rebuildDocument(full);
    if (mounted) setState(() {});
  }

  void _onDocChanged(_) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _writeBack);
  }

  void _writeBack() {
    if (!mounted || _doc == null) return;
    _writingBack = true;
    try {
      final body = serializeDocumentToMarkdown(_doc!);
      _lastBody = body;
      final full = _frontmatter + body;
      if (widget.controller.text != full) {
        widget.controller.text = full;
      }
    } finally {
      _writingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    if (editor == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = SuperEditor(
      key: ValueKey('wysiwyg-$_generation'),
      editor: editor,
      componentBuilders: [
        TaskComponentBuilder(editor),
        // 表格组件默认不在 defaultComponentBuilders 里，缺了表格只解析不渲染
        const MarkdownTableComponentBuilder(),
        ...defaultComponentBuilders,
      ],
      stylesheet: defaultStylesheet.copyWith(
        // 左对齐书写（对标源码模式的 20px 左缘内边距），不做纸面居中
        documentPadding: const EdgeInsets.symmetric(
          vertical: 24,
          horizontal: 20,
        ),
        addRulesAfter: [
          StyleRule(
            BlockSelector.all,
            (doc, docNode) => {
              'backgroundColor': Colors.transparent,
              'color': widget.textColor ??
                  (isDark
                      ? const Color(0xFFE7E5E4)
                      : const Color(0xFF292524)),
            },
          ),
        ],
      ),
    );
    if (widget.maxWidth != null) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth!),
          child: content,
        ),
      );
    }
    return content;
  }
}
