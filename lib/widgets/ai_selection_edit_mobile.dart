/// 移动端 AI 选区编辑工具栏
///
/// 移动端适配的 AI 选区编辑：
/// - 选中文本后弹出浮动工具栏
/// - 支持：润色、续写、摘要、改写、翻译
/// - 使用 BottomSheet 展示结果
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../services/conflict_diff_service.dart';
import '../models/app_settings.dart';

/// 移动端 AI 编辑操作类型
enum MobileAiEditAction {
  polish('润色', '优化文字表达', Icons.auto_fix_high),
  expand('续写', '丰富内容细节', Icons.open_in_full),
  summarize('摘要', '提取核心观点', Icons.summarize),
  rewrite('改写', '改变写作风格', Icons.swap_horiz),
  translate('翻译', '翻译为英文', Icons.translate);

  final String label;
  final String description;
  final IconData icon;
  const MobileAiEditAction(this.label, this.description, this.icon);

  String get promptTemplate {
    switch (this) {
      case MobileAiEditAction.polish:
        return '请对以下文字进行润色优化，使语言更流畅、表达更专业。保持原意不变，只优化表达方式。直接输出结果，不要添加解释。\n\n原文：\n';
      case MobileAiEditAction.expand:
        return '请对以下文字进行扩写，丰富内容细节和论述深度。保持原文风格和核心观点。直接输出结果，不要添加解释。\n\n原文：\n';
      case MobileAiEditAction.summarize:
        return '请提取以下文字的核心观点，生成简洁的摘要。直接输出结果，不要添加解释。\n\n原文：\n';
      case MobileAiEditAction.rewrite:
        return '请用不同的写作风格改写以下文字，保持原意不变。直接输出结果，不要添加解释。\n\n原文：\n';
      case MobileAiEditAction.translate:
        return '请将以下中文翻译为英文，保持专业、流畅的表达风格。直接输出结果，不要添加解释。\n\n原文：\n';
    }
  }
}

/// 移动端 AI 选区编辑工具栏
///
/// 选中文本后弹出浮动工具栏，提供 AI 编辑操作。
class AiSelectionEditMobile extends StatefulWidget {
  final String selectedText;
  final AiService aiService;
  final AppSettings settings;
  final void Function(String acceptedText)? onAccept;

  const AiSelectionEditMobile({
    super.key,
    required this.selectedText,
    required this.aiService,
    required this.settings,
    this.onAccept,
  });

  @override
  State<AiSelectionEditMobile> createState() => _AiSelectionEditMobileState();
}

class _AiSelectionEditMobileState extends State<AiSelectionEditMobile>
    with SingleTickerProviderStateMixin {
  MobileAiEditAction? _selectedAction;
  bool _isProcessing = false;
  String? _aiResult;
  String? _errorMessage;

  List<DiffLine> _diffLines = [];
  bool _showResult = false;
  bool _showDiff = false;

  late AnimationController _animController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ============================================================
  // AI 处理
  // ============================================================

  Future<void> _executeAction(MobileAiEditAction action) async {
    setState(() {
      _selectedAction = action;
      _isProcessing = true;
      _errorMessage = null;
      _showResult = false;
      _showDiff = false;
    });

    try {
      final prompt = '${action.promptTemplate}${widget.selectedText}';

      final result = await widget.aiService.complete(
        settings: widget.settings,
        systemPrompt: '你是一个专业的文字编辑助手。请严格按照用户的要求处理文本，直接输出处理后的结果，不要添加任何解释、说明或前缀。',
        userPrompt: prompt,
      );

      if (!mounted) return;

      final cleaned = _cleanAiOutput(result);
      setState(() {
        _aiResult = cleaned;
        _isProcessing = false;
        _showResult = true;
        _showDiff = false;
        _diffLines = ConflictDiffService.computeDiff(
          widget.selectedText,
          cleaned,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString();
      });
    }
  }

  String _cleanAiOutput(String raw) {
    var text = raw.trim();
    final codeBlockPattern = RegExp(r'^```[\w]*\n([\s\S]*?)\n```$', multiLine: true);
    final match = codeBlockPattern.firstMatch(text);
    if (match != null) {
      text = match.group(1)!.trim();
    }
    final patterns = [
      RegExp(r'^以下是[^：:]*[：:]\s*', multiLine: true),
      RegExp(r'^修改后的[^：:]*[：:]\s*', multiLine: true),
      RegExp(r'^优化后的[^：:]*[：:]\s*', multiLine: true),
    ];
    for (final pattern in patterns) {
      final m = pattern.firstMatch(text);
      if (m != null) {
        text = text.substring(m.end).trim();
        break;
      }
    }
    return text;
  }

  void _acceptResult() {
    if (_aiResult != null) {
      widget.onAccept?.call(_aiResult!);
      Navigator.pop(context, _aiResult);
    }
  }

  void _toggleDiffView() {
    setState(() => _showDiff = !_showDiff);
  }

  // ============================================================
  // 构建 UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(_slideAnimation),
      child: FadeTransition(
        opacity: _slideAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 拖动指示器
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 标题栏
                _buildHeader(isDark),
                // 内容区
                if (_showResult && _showDiff)
                  _buildDiffView(isDark)
                else if (_showResult)
                  _buildResultView(isDark)
                else
                  _buildActionSelection(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 20, color: Color(0xFF7C4DFF)),
          const SizedBox(width: 8),
          const Text(
            'AI 选区编辑',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (_showResult)
            IconButton(
              icon: Icon(_showDiff ? Icons.list : Icons.compare),
              tooltip: _showDiff ? '结果预览' : '对比差异',
              onPressed: _toggleDiffView,
              iconSize: 20,
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionSelection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 原文预览
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D2D3A) : const Color(0xFFEEEEEE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF3E3E42) : const Color(0xFFE0E0E0),
              ),
            ),
            constraints: const BoxConstraints(maxHeight: 100),
            child: SingleChildScrollView(
              child: Text(
                widget.selectedText,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                  height: 1.5,
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已选中 ${widget.selectedText.length} 个字符',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('AI 正在处理...', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.error_outline, size: 36, color: Colors.red.shade300),
                    const SizedBox(height: 8),
                    Text('处理失败', style: TextStyle(color: Colors.red.shade400, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(_errorMessage!, style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() {
                        _errorMessage = null;
                        _selectedAction = null;
                      }),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          else
            // 操作按钮列表
            ...MobileAiEditAction.values.map((action) => _buildActionTile(action, isDark)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildActionTile(MobileAiEditAction action, bool isDark) {
    final isSelected = _selectedAction == action;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: isSelected
          ? const Color(0xFF7C4DFF).withOpacity(0.1)
          : null,
      child: ListTile(
        leading: Icon(
          action.icon,
          color: isSelected ? const Color(0xFF7C4DFF) : null,
          size: 22,
        ),
        title: Text(
          action.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isSelected ? const Color(0xFF7C4DFF) : null,
          ),
        ),
        subtitle: Text(
          action.description,
          style: const TextStyle(fontSize: 11),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, size: 18, color: Color(0xFF7C4DFF))
            : const Icon(Icons.chevron_right, size: 18),
        onTap: () => _executeAction(action),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
    );
  }

  Widget _buildResultView(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 操作标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _selectedAction?.icon ?? Icons.auto_awesome,
                  size: 14,
                  color: const Color(0xFF7C4DFF),
                ),
                const SizedBox(width: 4),
                Text(
                  _selectedAction?.label ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7C4DFF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 结果
          SizedBox(
            height: 200,
            child: SingleChildScrollView(
              child: Text(
                _aiResult ?? '',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.6,
                ),
                ),
              ),
            ),
            // 操作按钮
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _acceptResult,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('接受'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
  }

  Widget _buildDiffView(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图例
            Row(
              children: [
                _legendItem(Colors.green, '新增'),
                const SizedBox(width: 12),
                _legendItem(Colors.red, '删除'),
                const SizedBox(width: 12),
                _legendItem(Colors.grey, '不变'),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // Diff 内容
            Expanded(
              child: ListView.builder(
                itemCount: _diffLines.length,
                itemBuilder: (_, i) {
                  final line = _diffLines[i];
                  Color bgColor;
                  String prefix;

                  switch (line.operation) {
                    case DiffOperation.insert:
                      bgColor = isDark ? const Color(0xFF1A3A2A) : const Color(0xFFE8F5E9);
                      prefix = '+ ';
                      break;
                    case DiffOperation.delete:
                      bgColor = isDark ? const Color(0xFF3A1A1A) : const Color(0xFFFFEBEE);
                      prefix = '- ';
                      break;
                    default:
                      bgColor = Colors.transparent;
                      prefix = '  ';
                  }

                  return Container(
                    color: bgColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text(
                            prefix,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: line.operation == DiffOperation.insert
                                  ? Colors.green
                                  : line.operation == DiffOperation.delete
                                      ? Colors.red
                                      : Colors.grey,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            line.content.isEmpty ? ' ' : line.content,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: isDark ? Colors.white : Colors.black87,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // 操作按钮
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _acceptResult,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('接受'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

}