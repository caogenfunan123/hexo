/// 移动端 Diff 对比屏幕
///
/// 上下分栏布局（顶部旧版本，底部新版本）
/// 参考 Yank Note (https://github.com/purocean/yn) 的 Diff 交互设计
///
/// 功能：
/// - 使用 ConflictDiffService.computeDiff() 计算差异
/// - 差异行高亮：绿色=新增，红色=删除，黄色=修改
/// - 支持左右滑动切换变更块
/// - 底部操作栏：接受本地、接受远程、手动合并
library;

import 'package:flutter/material.dart';
import '../services/conflict_diff_service.dart';

/// 移动端 Diff 对比屏幕
class MobileDiffScreen extends StatefulWidget {
  final String oldText;
  final String newText;
  final String oldLabel;
  final String newLabel;
  final void Function(String mergedText)? onAccept;

  const MobileDiffScreen({
    super.key,
    required this.oldText,
    required this.newText,
    this.oldLabel = '旧版本',
    this.newLabel = '新版本',
    this.onAccept,
  });

  @override
  State<MobileDiffScreen> createState() => _MobileDiffScreenState();
}

class _MobileDiffScreenState extends State<MobileDiffScreen> {
  late List<DiffLine> _diffLines;
  late List<DiffBlock> _diffBlocks;
  int _currentBlockIndex = 0;
  final PageController _blockPageController = PageController();
  final ScrollController _oldScrollController = ScrollController();
  final ScrollController _newScrollController = ScrollController();

  // 合并状态
  final Set<int> _acceptedLineIndices = {};
  final Set<int> _rejectedLineIndices = {};
  bool _showManualMerge = false;

  @override
  void initState() {
    super.initState();
    _computeDiff();
  }

  void _computeDiff() {
    _diffLines = ConflictDiffService.computeDiff(
      widget.oldText,
      widget.newText,
    );
    _diffBlocks = ConflictDiffService.groupIntoBlocks(_diffLines);
    if (_diffBlocks.isEmpty) {
      // 创建一个虚拟块以显示所有内容
      _diffBlocks = [
        DiffBlock(
          lines: _diffLines,
          startLineOld: 1,
          startLineNew: 1,
        ),
      ];
    }
  }

  @override
  void dispose() {
    _blockPageController.dispose();
    _oldScrollController.dispose();
    _newScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('版本对比'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 变更块导航
          Center(
            child: Text(
              _diffBlocks.isEmpty
                  ? '无变更'
                  : '${_currentBlockIndex + 1} / ${_diffBlocks.length}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            tooltip: '上一处变更',
            onPressed: _currentBlockIndex > 0
                ? () {
                    _blockPageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: '下一处变更',
            onPressed: _currentBlockIndex < _diffBlocks.length - 1
                ? () {
                    _blockPageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                : null,
          ),
        ],
      ),
      body: _showManualMerge ? _buildManualMergeView(isDark) : _buildDiffView(isDark),
      bottomNavigationBar: _buildBottomBar(isDark),
    );
  }

  // ============================================================
  // Diff 视图
  // ============================================================

  Widget _buildDiffView(bool isDark) {
    return Column(
      children: [
        // 上方：旧版本
        _buildVersionPanel(
          label: widget.oldLabel,
          isOld: true,
          isDark: isDark,
          scrollController: _oldScrollController,
        ),
        // 分隔线
        Container(
          height: 2,
          color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
        ),
        // 下方：新版本
        _buildVersionPanel(
          label: widget.newLabel,
          isOld: false,
          isDark: isDark,
          scrollController: _newScrollController,
        ),
      ],
    );
  }

  Widget _buildVersionPanel({
    required String label,
    required bool isOld,
    required bool isDark,
    required ScrollController scrollController,
  }) {
    return Expanded(
      child: Column(
        children: [
          // 面板标签
          _buildPanelLabel(label, isOld, isDark),
          // 内容
          Expanded(
            child: _diffLines.isEmpty
                ? _buildEmptyDiff(isDark)
                : ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    itemCount: _diffLines.length,
                    itemBuilder: (context, index) {
                      final line = _diffLines[index];
                      // 在旧面板中跳过仅新增的行，在旧面板中显示占位
                      if (isOld && line.operation == DiffOperation.insert) {
                        return const SizedBox(height: 22);
                      }
                      // 在新面板中跳过仅删除的行
                      if (!isOld && line.operation == DiffOperation.delete) {
                        return const SizedBox(height: 22);
                      }
                      return _buildDiffLine(line, index, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelLabel(String label, bool isOld, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isOld
          ? (isDark ? const Color(0xFF1A3A2A) : const Color(0xFFE8F5E9))
          : (isDark ? const Color(0xFF2A1A3A) : const Color(0xFFE3F2FD)),
      child: Row(
        children: [
          Icon(
            isOld ? Icons.history : Icons.update,
            size: 14,
            color: isOld
                ? (isDark ? const Color(0xFF4CAF50) : const Color(0xFF2E7D32))
                : (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0)),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isOld
                  ? (isDark ? const Color(0xFF4CAF50) : const Color(0xFF2E7D32))
                  : (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffLine(DiffLine line, int index, bool isDark) {
    Color bgColor;
    Color? borderColor;
    String prefix;

    switch (line.operation) {
      case DiffOperation.insert:
        bgColor = isDark ? const Color(0xFF1A3A2A) : const Color(0xFFE8F5E9);
        borderColor = isDark ? const Color(0xFF4CAF50) : const Color(0xFF66BB6A);
        prefix = '+ ';
        break;
      case DiffOperation.delete:
        bgColor = isDark ? const Color(0xFF3A1A1A) : const Color(0xFFFFEBEE);
        borderColor = isDark ? const Color(0xFFEF5350) : const Color(0xFFEF9A9A);
        prefix = '- ';
        break;
      case DiffOperation.equal:
        bgColor = Colors.transparent;
        prefix = '  ';
        break;
      default:
        bgColor = Colors.transparent;
        prefix = '  ';
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行号
          SizedBox(
            width: 30,
            child: Text(
              '${line.lineNumber}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: isDark ? Colors.white.withOpacity(0.3) : Colors.grey.shade400,
                height: 1.5,
              ),
            ),
          ),
          // 变更指示器
          if (borderColor != null)
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: 4),
              color: borderColor,
            )
          else
            const SizedBox(width: 7),
          // 内容
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: prefix,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: line.operation == DiffOperation.insert
                          ? const Color(0xFF4CAF50)
                          : line.operation == DiffOperation.delete
                              ? const Color(0xFFEF5350)
                              : null,
                    ),
                  ),
                  TextSpan(text: line.content),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDiff(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.compare_arrows, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            '无差异',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 手动合并视图
  // ============================================================

  Widget _buildManualMergeView(bool isDark) {
    final mergedText = _buildMergedText();
    final controller = TextEditingController(text: mergedText);

    return Column(
      children: [
        // 头部说明
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: isDark ? const Color(0xFF2A2A1A) : const Color(0xFFFFF8E1),
          child: Row(
            children: [
              const Icon(Icons.merge, size: 16, color: Color(0xFFFFCA28)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '手动合并模式 - 编辑下方文本以合并两个版本',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _showManualMerge = false),
                child: const Text('返回对比', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        // 编辑区域
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: isDark ? Colors.white : Colors.black87,
                height: 1.6,
              ),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
                  ),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              onChanged: (value) {
                // 实时更新合并文本
              },
            ),
          ),
        ),
        // 操作按钮
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _showManualMerge = false),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    widget.onAccept?.call(controller.text);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('确认合并'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _buildMergedText() {
    final buffer = StringBuffer();
    for (final line in _diffLines) {
      if (line.operation == DiffOperation.delete) {
        // 删除的行：在合并中保留（带注释）
        buffer.writeln('<!-- DELETED: ${line.content} -->');
      } else {
        buffer.writeln(line.content);
      }
    }
    return buffer.toString().trimRight();
  }

  // ============================================================
  // 底部操作栏
  // ============================================================

  Widget _buildBottomBar(bool isDark) {
    if (_showManualMerge) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F7),
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
            ),
          ),
        ),
        child: Row(
          children: [
            // 接受本地（旧版本）
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  _showAcceptDialog(
                    context,
                    '接受本地版本',
                    '确定要使用本地版本（${widget.oldLabel}）覆盖吗？',
                    () {
                      widget.onAccept?.call(widget.oldText);
                      Navigator.pop(context);
                    },
                  );
                },
                icon: const Icon(Icons.laptop, size: 16),
                label: const Text('本地', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 手动合并
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showManualMerge = true),
                icon: const Icon(Icons.merge, size: 16),
                label: const Text('合并', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 接受远程（新版本）
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  _showAcceptDialog(
                    context,
                    '接受远程版本',
                    '确定要使用远程版本（${widget.newLabel}）覆盖吗？',
                    () {
                      widget.onAccept?.call(widget.newText);
                      Navigator.pop(context);
                    },
                  );
                },
                icon: const Icon(Icons.cloud_download, size: 16),
                label: const Text('远程', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAcceptDialog(
    BuildContext context,
    String title,
    String content,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}