import 'dart:async';

import 'package:flutter/material.dart';

import 'markdown_preview_smooth.dart';

/// 实验性分屏实时预览（Markor / SoloMD 模式，参照安卓开源 MD 编辑器的主流方案）：
/// 上半屏 = 原源码编辑（沿用既有 TextField / 自动保存 / 打字机链路，零新风险），
/// 下半屏 = MarkdownPreviewSmooth 实时渲染（表格 / 公式 / mermaid 全支持），
/// 中缝可拖拽调比例。
///
/// 为什么不用「直接在渲染文档上编辑」的真 inline 所见即所得：
/// super_editor 移动端 IME 风险未验证（桌面已在用），flutter_smooth_markdown 的
/// formatted 编辑器实测空渲染不可用；安卓开源生态（Markor/Mua/SoloMD）绝大多数
/// 也是源码+实时预览，这是被验证过最稳的形态。真 inline 编辑由
/// WysiwygWebViewEditor（TipTap WebView）承担。
///
/// 连续回调守则：中缝拖拽只写 [splitRatio] ValueNotifier，由
/// ValueListenableBuilder 局部重建，绝不整页 setState。
///
/// 性能：预览侧「停手 [previewIdleDebounce] 才渲染」的空闲防抖——打字期间
/// 预览静止（不再每次击键全文重解析重建），停手后一次性渲染，消除打字卡顿；
/// 下半屏包 RepaintBoundary，重绘不串扰上半屏。
class SplitPreviewPane extends StatefulWidget {
  const SplitPreviewPane({
    super.key,
    required this.titleCtrl,
    required this.contentCtrl,
    required this.splitRatio,
    required this.textColor,
    required this.onContentChanged,
    this.editorScrollCtrl,
    this.previewIdleDebounce = const Duration(milliseconds: 600),
  });

  final TextEditingController titleCtrl;
  final TextEditingController contentCtrl;

  /// 编辑区高度占比（0.25 ~ 0.75），中缝拖拽只写这里
  final ValueNotifier<double> splitRatio;

  /// 跟随壁纸/主题的全局文字色（标题与正文输入用）
  final Color textColor;

  /// 正文变更回调（宿主接 _onContentChanged：未保存标记 + 自动保存防抖）
  final VoidCallback onContentChanged;

  /// 复用源码模式的滚动控制器（打字机滚动定位）
  final ScrollController? editorScrollCtrl;

  /// 预览空闲防抖窗口
  final Duration previewIdleDebounce;

  @override
  State<SplitPreviewPane> createState() => _SplitPreviewPaneState();
}

class _SplitPreviewPaneState extends State<SplitPreviewPane> {
  Timer? _idleTimer;
  late String _previewMarkdown;

  @override
  void initState() {
    super.initState();
    widget.titleCtrl.addListener(_schedulePreview);
    widget.contentCtrl.addListener(_schedulePreview);
    _previewMarkdown = _composeMarkdown();
  }

  @override
  void didUpdateWidget(covariant SplitPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.titleCtrl != widget.titleCtrl) {
      oldWidget.titleCtrl.removeListener(_schedulePreview);
      widget.titleCtrl.addListener(_schedulePreview);
      _previewMarkdown = _composeMarkdown();
    }
    if (oldWidget.contentCtrl != widget.contentCtrl) {
      oldWidget.contentCtrl.removeListener(_schedulePreview);
      widget.contentCtrl.addListener(_schedulePreview);
      _previewMarkdown = _composeMarkdown();
    }
  }

  @override
  void dispose() {
    widget.titleCtrl.removeListener(_schedulePreview);
    widget.contentCtrl.removeListener(_schedulePreview);
    _idleTimer?.cancel();
    super.dispose();
  }

  /// 打字期间只重置计时器，停手 [previewIdleDebounce] 后才真正渲染
  void _schedulePreview() {
    _idleTimer?.cancel();
    _idleTimer = Timer(widget.previewIdleDebounce, () {
      if (mounted) setState(() => _previewMarkdown = _composeMarkdown());
    });
  }

  String _composeMarkdown() {
    final t = widget.titleCtrl.text.trim();
    final body = widget.contentCtrl.text;
    if (t.isEmpty) return body.isEmpty ? '*暂无内容*' : body;
    return '# $t\n\n$body';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ValueListenableBuilder<double>(
          valueListenable: widget.splitRatio,
          builder: (context, ratio, _) {
            final editorFlex = (ratio * 100).round();
            final previewFlex = 100 - editorFlex;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: TextField(
                    controller: widget.titleCtrl,
                    decoration: InputDecoration(
                      hintText: '输入标题',
                      hintStyle: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: widget.textColor.withValues(alpha: 0.35),
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    cursorColor: widget.textColor,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: widget.textColor,
                    ),
                  ),
                ),
                Expanded(
                  flex: editorFlex,
                  child: SingleChildScrollView(
                    controller: widget.editorScrollCtrl,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    child: TextField(
                      controller: widget.contentCtrl,
                      minLines: 6,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: '开始写作，支持 Markdown 语法...',
                        hintStyle: TextStyle(
                          fontSize: 15,
                          color: widget.textColor.withValues(alpha: 0.35),
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      cursorColor: widget.textColor,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.7,
                        color: widget.textColor,
                      ),
                      onChanged: (_) => widget.onContentChanged(),
                    ),
                  ),
                ),
                // ── 可拖拽中缝：横线加宽触摸区，拖拽只写 notifier ──
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) {
                    final h = constraints.maxHeight;
                    if (h <= 0) return;
                    widget.splitRatio.value =
                        (widget.splitRatio.value - d.primaryDelta! / h)
                            .clamp(0.25, 0.75);
                  },
                  child: SizedBox(
                    height: 14,
                    child: Center(
                      child: Container(
                        width: 56,
                        height: 3,
                        decoration: BoxDecoration(
                          color: widget.textColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: previewFlex,
                  child: RepaintBoundary(
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.06),
                      child: MarkdownPreviewSmooth(
                        markdown: _previewMarkdown,
                        baseFontSize: 15,
                        lineHeight: 1.7,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
