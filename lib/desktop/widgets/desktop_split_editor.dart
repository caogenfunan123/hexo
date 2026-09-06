/// 桌面端 Markdown 双栏编辑器
/// 对标 MarkText + PureWriter：左栏源码编辑 + 右栏实时预览
/// 支持宽高比可调、一键切换单栏/双栏
/// PureWriter 借鉴：720px 宽度约束、隐藏滚动条、思源黑体
library;

import 'package:flutter/material.dart';
import '../../../theme/app_color.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../widgets/debounced_markdown_preview.dart';

/// 双栏编辑器模式
enum SplitEditorMode {
  /// 仅源码
  sourceOnly,
  /// 仅预览
  previewOnly,
  /// 左右分栏
  split,
}

/// 双栏 Markdown 编辑器
class DesktopSplitEditor extends StatefulWidget {
  final TextEditingController contentController;
  final FocusNode focusNode;
  final VoidCallback? onChanged;
  final MarkdownStyleSheet? styleSheet;
  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final bool isDark;
  final ColorScheme colorScheme;
  final Widget Function(BuildContext, String)? customPreview;
  final SplitEditorMode initialMode;
  final ValueChanged<SplitEditorMode>? onModeChanged;
  final Color? editorTextColor;

  const DesktopSplitEditor({
    super.key,
    required this.contentController,
    required this.focusNode,
    this.onChanged,
    this.styleSheet,
    this.fontSize = 14.5,
    this.lineHeight = 1.6,
    this.fontFamily = 'monospace',
    this.isDark = false,
    required this.colorScheme,
    this.customPreview,
    this.initialMode = SplitEditorMode.sourceOnly,
    this.onModeChanged,
    this.editorTextColor,
  });

  @override
  State<DesktopSplitEditor> createState() => _DesktopSplitEditorState();
}

class _DesktopSplitEditorState extends State<DesktopSplitEditor> {
  late SplitEditorMode _mode;
  double _splitRatio = 0.5; // 源码区占比

  // 源码区滚动控制器
  final ScrollController _sourceScrollCtrl = ScrollController();
  // 预览区滚动控制器
  final ScrollController _previewScrollCtrl = ScrollController();
  bool _syncingScroll = false;

  // Debounced markdown preview state
  late final DebouncedMarkdownPreviewState _previewState;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _sourceScrollCtrl.addListener(_onSourceScroll);
    _previewState = DebouncedMarkdownPreviewState(
      debounce: const Duration(milliseconds: 200),
    );
    _previewState.updateText(widget.contentController.text);
    widget.contentController.addListener(_onContentChanged);
  }

  @override
  void didUpdateWidget(covariant DesktopSplitEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentController != widget.contentController) {
      oldWidget.contentController.removeListener(_onContentChanged);
      widget.contentController.addListener(_onContentChanged);
      _previewState.updateText(widget.contentController.text);
    }
  }

  @override
  void dispose() {
    _sourceScrollCtrl.removeListener(_onSourceScroll);
    _sourceScrollCtrl.dispose();
    _previewScrollCtrl.dispose();
    widget.contentController.removeListener(_onContentChanged);
    _previewState.dispose();
    super.dispose();
  }

  void _onContentChanged() {
    _previewState.updateText(widget.contentController.text);
    widget.onChanged?.call();
  }

  void _onSourceScroll() {
    if (_syncingScroll || _mode != SplitEditorMode.split) return;
    _syncingScroll = true;
    if (_sourceScrollCtrl.hasClients && _previewScrollCtrl.hasClients) {
      final maxSource = _sourceScrollCtrl.position.maxScrollExtent;
      final maxPreview = _previewScrollCtrl.position.maxScrollExtent;
      if (maxSource > 0 && maxPreview > 0) {
        final ratio = _sourceScrollCtrl.offset / maxSource;
        _previewScrollCtrl.jumpTo(ratio * maxPreview);
      }
    }
    _syncingScroll = false;
  }

  void _switchMode(SplitEditorMode mode) {
    setState(() => _mode = mode);
    widget.onModeChanged?.call(mode);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cs = widget.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Column(
        children: [
          // 模式切换工具栏
          _buildModeBar(isDark, cs),
          // 编辑器主体
          Expanded(
            child: _buildEditorBody(isDark, cs),
          ),
        ],
      ),
    );
  }

  Widget _buildModeBar(bool isDark, ColorScheme cs) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColor.surfaceBase(context),
        border: Border(
          bottom: BorderSide(
            color: AppColor.border(context),
          ),
        ),
      ),
      child: Row(
        children: [
          _modeButton(
            icon: Icons.code,
            label: '源码',
            mode: SplitEditorMode.sourceOnly,
            isDark: isDark,
            cs: cs,
          ),
          _modeButton(
            icon: Icons.vertical_split,
            label: '分栏',
            mode: SplitEditorMode.split,
            isDark: isDark,
            cs: cs,
          ),
          _modeButton(
            icon: Icons.visibility,
            label: '预览',
            mode: SplitEditorMode.previewOnly,
            isDark: isDark,
            cs: cs,
          ),
          const Spacer(),
          // 分栏比例调整（仅在分栏模式）
          if (_mode == SplitEditorMode.split)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _splitRatio = (_splitRatio - 0.1).clamp(0.3, 0.7)),
                  child: Icon(Icons.chevron_left, size: 14, color: cs.primary.withOpacity(0.6)),
                ),
                const SizedBox(width: 4),
                Text(
                  '${(_splitRatio * 100).round()}%',
                  style: TextStyle(fontSize: 10, color: cs.primary.withOpacity(0.6)),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() => _splitRatio = (_splitRatio + 0.1).clamp(0.3, 0.7)),
                  child: Icon(Icons.chevron_right, size: 14, color: cs.primary.withOpacity(0.6)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _modeButton({
    required IconData icon,
    required String label,
    required SplitEditorMode mode,
    required bool isDark,
    required ColorScheme cs,
  }) {
    final active = _mode == mode;
    return GestureDetector(
      onTap: () => _switchMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withOpacity(isDark ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active
                  ? cs.primary
                  : (AppColor.textMuted(context)),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active
                    ? cs.primary
                    : (AppColor.textMuted(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorBody(bool isDark, ColorScheme cs) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _buildEditorBodyContent(isDark, cs),
    );
  }

  Widget _buildEditorBodyContent(bool isDark, ColorScheme cs) {
    switch (_mode) {
      case SplitEditorMode.sourceOnly:
        return _buildSourceEditor(isDark, cs);
      case SplitEditorMode.previewOnly:
        return _buildPreviewOnly(isDark, cs);
      case SplitEditorMode.split:
        return _buildSplitView(isDark, cs);
    }
  }

  /// 纯源码编辑器 — 占满可用宽度、隐藏滚动条
  Widget _buildSourceEditor(bool isDark, ColorScheme cs) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final minLines = constraints.maxHeight.isFinite
            ? ((constraints.maxHeight - 80) / (widget.fontSize * widget.lineHeight)).floor().clamp(1, 50)
            : 15;
        return ScrollbarTheme(
          data: ScrollbarThemeData(
            thickness: WidgetStateProperty.all(0), // 隐藏滚动条
          ),
          child: TextField(
            controller: widget.contentController,
            focusNode: widget.focusNode,
            minLines: minLines,
            maxLines: null,
            expands: constraints.maxHeight.isFinite,
            keyboardType: TextInputType.multiline,
            cursorColor: cs.primary,
            style: TextStyle(
              fontFamily: widget.fontFamily,
                  height: widget.lineHeight,
                  fontSize: widget.fontSize,
                  color: widget.editorTextColor ?? AppColor.textPrimary(context),
                ),
                decoration: InputDecoration(
                  hintText: '支持 Markdown 语法写作...',
                  hintStyle: TextStyle(
                    color: (widget.editorTextColor ?? AppColor.textPrimary(context)).withOpacity(0.35),
                    fontSize: widget.fontSize,
                  ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
        );
      },
    );
  }

  /// 纯预览 — PureWriter 风格：720px 宽度约束
  Widget _buildPreviewOnly(bool isDark, ColorScheme cs) {
    return Center(
      child: ConstrainedBox(
        // PureWriter 借鉴：720px 最大宽度
        constraints: const BoxConstraints(maxWidth: 720),
        child: ScrollbarTheme(
          data: ScrollbarThemeData(
            thickness: WidgetStateProperty.all(0), // 隐藏滚动条
          ),
          child: Scrollbar(
            controller: _previewScrollCtrl,
            child: SingleChildScrollView(
              controller: _previewScrollCtrl,
              padding: const EdgeInsets.all(20),
              child: DebouncedMarkdownPreview(
                state: _previewState,
                isDark: isDark,
                styleSheet: widget.styleSheet,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 左右分栏 — PureWriter 风格：隐藏滚动条
  Widget _buildSplitView(bool isDark, ColorScheme cs) {
    final sepColor = AppColor.border(context);

    return Row(
      children: [
        // 左栏：源码编辑
        Expanded(
          flex: (_splitRatio * 100).round(),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final minLines = constraints.maxHeight.isFinite
                  ? ((constraints.maxHeight - 80) / (widget.fontSize * widget.lineHeight)).floor().clamp(1, 50)
                  : 15;
              return ScrollbarTheme(
                data: ScrollbarThemeData(
                  thickness: WidgetStateProperty.all(0), // 隐藏滚动条
                ),
                child: Scrollbar(
                  controller: _sourceScrollCtrl,
                  child: SingleChildScrollView(
                    controller: _sourceScrollCtrl,
                    child: TextField(
                      controller: widget.contentController,
                      focusNode: widget.focusNode,
                      minLines: minLines,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      cursorColor: cs.primary,
                      style: TextStyle(
                        fontFamily: widget.fontFamily,
                        height: widget.lineHeight,
                        fontSize: widget.fontSize,
                        color: widget.editorTextColor ?? AppColor.textPrimary(context),
                      ),
                      decoration: InputDecoration(
                        hintText: '支持 Markdown 语法写作...',
                        hintStyle: TextStyle(
                          color: (widget.editorTextColor ?? AppColor.textPrimary(context)).withOpacity(0.35),
                          fontSize: widget.fontSize,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // 分隔线（可拖拽）
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            final totalWidth = MediaQuery.of(context).size.width;
            setState(() {
              _splitRatio += details.delta.dx / totalWidth;
              _splitRatio = _splitRatio.clamp(0.3, 0.7);
            });
          },
          child: Container(
            width: 1,
            color: sepColor,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 3,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 右栏：实时预览
        Expanded(
          flex: ((1 - _splitRatio) * 100).round(),
          child: ScrollbarTheme(
            data: ScrollbarThemeData(
              thickness: WidgetStateProperty.all(0), // 隐藏滚动条
            ),
            child: Scrollbar(
              controller: _previewScrollCtrl,
              child: SingleChildScrollView(
                controller: _previewScrollCtrl,
                padding: const EdgeInsets.all(16),
                child: DebouncedMarkdownPreview(
                  state: _previewState,
                  isDark: isDark,
                  styleSheet: widget.styleSheet,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}