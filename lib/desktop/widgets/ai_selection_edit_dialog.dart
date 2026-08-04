/// AI 选区编辑对话框
///
/// 对选中的文本进行 AI 编辑（润色、扩写、缩写、翻译、总结、改写）
/// 提供 Diff 对比视图，支持选择性接受修改
///
/// 对标：Cursor AI inline edit + VS Code diff view
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/app_settings.dart';
import '../../services/ai_service.dart';
import '../../services/conflict_diff_service.dart';
import '../../core/cancel_token.dart';

/// AI 编辑操作类型
enum AiEditAction {
  polish('润色优化', '优化文字表达，使语言更流畅自然', Icons.auto_fix_high),
  expand('扩写内容', '丰富内容细节，增加论述深度', Icons.open_in_full),
  shorten('精简缩写', '精简文字，保留核心要点', Icons.close_fullscreen),
  translate('翻译英文', '翻译为英文，保持专业表达', Icons.translate),
  summarize('生成摘要', '提取核心观点，生成简短摘要', Icons.summarize),
  rewrite('风格改写', '改变写作风格，保持原意', Icons.swap_horiz),
  fixGrammar('语法修正', '修正语法错误和拼写问题', Icons.spellcheck),
  improveClarity('提升清晰度', '使表达更清晰易懂', Icons.visibility);

  final String label;
  final String description;
  final IconData icon;
  const AiEditAction(this.label, this.description, this.icon);

  String get promptTemplate {
    switch (this) {
      case AiEditAction.polish:
        return '请对以下文字进行润色优化，使语言更流畅、表达更专业。保持原意不变，只优化表达方式。\n\n原文：\n';
      case AiEditAction.expand:
        return '请对以下文字进行扩写，丰富内容细节和论述深度，增加具体例子或数据支撑。保持原文风格和核心观点。\n\n原文：\n';
      case AiEditAction.shorten:
        return '请对以下文字进行精简缩写，保留核心要点和关键信息，删除冗余表达。\n\n原文：\n';
      case AiEditAction.translate:
        return '请将以下中文翻译为英文，保持专业、流畅的表达风格。\n\n原文：\n';
      case AiEditAction.summarize:
        return '请提取以下文字的核心观点，生成简洁的摘要（不超过原文的1/3）。\n\n原文：\n';
      case AiEditAction.rewrite:
        return '请用不同的写作风格改写以下文字，保持原意不变。可以尝试更正式/更口语化/更有文采的表达。\n\n原文：\n';
      case AiEditAction.fixGrammar:
        return '请修正以下文字中的语法错误和拼写问题，不改变原意和表达风格。\n\n原文：\n';
      case AiEditAction.improveClarity:
        return '请优化以下文字，使表达更清晰、逻辑更连贯。保持原意不变。\n\n原文：\n';
    }
  }
}

/// AI 选区编辑对话框
class AiSelectionEditDialog extends StatefulWidget {
  final String selectedText;
  final AiService aiService;
  final AppSettings settings;
  final void Function(String acceptedText)? onAccept;

  const AiSelectionEditDialog({
    super.key,
    required this.selectedText,
    required this.aiService,
    required this.settings,
    this.onAccept,
  });

  @override
  State<AiSelectionEditDialog> createState() => _AiSelectionEditDialogState();
}

class _AiSelectionEditDialogState extends State<AiSelectionEditDialog>
    with SingleTickerProviderStateMixin {
  // ── 状态 ──
  AiEditAction? _selectedAction;
  bool _isProcessing = false;
  String? _aiResult;
  String? _errorMessage;

  // ── Diff 状态 ──
  List<DiffLine> _diffLines = [];
  final Set<int> _acceptedLines = {};
  final Set<int> _rejectedLines = {};
  bool _showDiff = false;

  CancelToken? _cancelToken;

  // ── 动画 ──
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // AI 处理
  // ============================================================

  Future<void> _executeAction(AiEditAction action) async {
    setState(() {
      _selectedAction = action;
      _isProcessing = true;
      _errorMessage = null;
      _showDiff = false;
    });

    _cancelToken = CancelToken();

    try {
      final prompt = '${action.promptTemplate}${widget.selectedText}\n\n请直接输出修改后的文本，不要添加任何解释或说明。';

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
        _showDiff = true;
        _diffLines = ConflictDiffService.computeDiff(
          widget.selectedText,
          cleaned,
        );
        _acceptedLines.clear();
        _rejectedLines.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// 清理 AI 输出，去除可能的 markdown 包装和多余内容
  String _cleanAiOutput(String raw) {
    var text = raw.trim();

    // 去除常见的 markdown 代码块包装
    final codeBlockPattern = RegExp(r'^```[\w]*\n([\s\S]*?)\n```$', multiLine: true);
    final match = codeBlockPattern.firstMatch(text);
    if (match != null) {
      text = match.group(1)!.trim();
    }

    // 去除 "以下是修改后的文本：" 等引导语
    final introPatterns = [
      RegExp(r'^以下是[^：:]*[：:]\s*', multiLine: true),
      RegExp(r'^修改后的[^：:]*[：:]\s*', multiLine: true),
      RegExp(r'^优化后的[^：:]*[：:]\s*', multiLine: true),
      RegExp(r'^Here[\'’]s? the[^:]*:\s*', multiLine: true, caseSensitive: false),
    ];
    for (final pattern in introPatterns) {
      final m = pattern.firstMatch(text);
      if (m != null) {
        text = text.substring(m.end).trim();
        break;
      }
    }

    return text;
  }

  // ============================================================
  // Diff 操作
  // ============================================================

  void _toggleLineAcceptance(int index) {
    setState(() {
      if (_acceptedLines.contains(index)) {
        _acceptedLines.remove(index);
      } else {
        _acceptedLines.add(index);
        _rejectedLines.remove(index);
      }
    });
  }

  void _toggleLineRejection(int index) {
    setState(() {
      if (_rejectedLines.contains(index)) {
        _rejectedLines.remove(index);
      } else {
        _rejectedLines.add(index);
        _acceptedLines.remove(index);
      }
    });
  }

  void _acceptAll() {
    setState(() {
      for (int i = 0; i < _diffLines.length; i++) {
        if (_diffLines[i].operation != DiffOperation.equal) {
          _acceptedLines.add(i);
          _rejectedLines.remove(i);
        }
      }
    });
  }

  void _rejectAll() {
    setState(() {
      _acceptedLines.clear();
      for (int i = 0; i < _diffLines.length; i++) {
        if (_diffLines[i].operation != DiffOperation.equal) {
          _rejectedLines.add(i);
        }
      }
    });
  }

  void _applyAcceptedChanges() {
    if (_aiResult == null) return;

    // 构建最终文本：接受的行用 AI 结果，拒绝的行用原文
    final buffer = StringBuffer();
    for (int i = 0; i < _diffLines.length; i++) {
      final line = _diffLines[i];
      if (_rejectedLines.contains(i)) {
        // 如果被拒绝，且是插入行则跳过，是删除行则恢复原文
        if (line.operation == DiffOperation.insert) {
          continue; // 跳过被拒绝的插入
        }
        if (line.operation == DiffOperation.delete) {
          buffer.writeln(line.content); // 恢复被删除的原文
        }
      } else {
        // 接受此行
        if (line.operation != DiffOperation.delete) {
          buffer.writeln(line.content);
        }
      }
    }

    final result = buffer.toString().trimRight();
    widget.onAccept?.call(result);
    Navigator.pop(context, result);
  }

  // ============================================================
  // 构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 22, color: Color(0xFF7C4DFF)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('AI 选区编辑', style: TextStyle(fontSize: 17)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: SizedBox(
          width: 850,
          height: 600,
          child: _showDiff ? _buildDiffView() : _buildActionSelection(),
        ),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildActionSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 原文预览
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor,
            ),
          ),
          constraints: const BoxConstraints(maxHeight: 120),
          child: SingleChildScrollView(
            child: Text(
              widget.selectedText,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              maxLines: 8,
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
        Text(
          '选择编辑操作',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        // 操作按钮网格
        Expanded(
          child: _isProcessing
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('AI 正在处理...'),
                    ],
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                          const SizedBox(height: 12),
                          Text('处理失败', style: TextStyle(color: Colors.red.shade400)),
                          const SizedBox(height: 4),
                          Text(_errorMessage!, style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => setState(() {
                              _errorMessage = null;
                              _selectedAction = null;
                            }),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 3.5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: AiEditAction.values.length,
                      itemBuilder: (_, i) {
                        final action = AiEditAction.values[i];
                        final isSelected = _selectedAction == action;
                        return Material(
                          color: isSelected
                              ? const Color(0xFF7C4DFF).withOpacity(0.1)
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _executeAction(action),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  Icon(
                                    action.icon,
                                    size: 20,
                                    color: isSelected
                                        ? const Color(0xFF7C4DFF)
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          action.label,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: isSelected
                                                ? const Color(0xFF7C4DFF)
                                                : Theme.of(context).colorScheme.onSurface,
                                          ),
                                        ),
                                        Text(
                                          action.description,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildDiffView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 操作标签
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_selectedAction?.icon ?? Icons.auto_awesome,
                      size: 14, color: const Color(0xFF7C4DFF)),
                  const SizedBox(width: 4),
                  Text(
                    _selectedAction?.label ?? '',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7C4DFF),
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              '${_diffLines.where((l) => l.operation != DiffOperation.equal).length} 处变更',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 图例
        _buildDiffLegend(),
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
              Color textColor;
              String prefix;

              if (_rejectedLines.contains(i)) {
                // 被拒绝的变更 → 灰色
                bgColor = Colors.grey.withOpacity(0.1);
                textColor = Colors.grey.shade600;
                prefix = '  ';
              } else if (_acceptedLines.contains(i)) {
                // 被接受的变更 → 蓝色
                bgColor = const Color(0xFF7C4DFF).withOpacity(0.08);
                textColor = const Color(0xFF7C4DFF);
                prefix = '✓ ';
              } else {
                switch (line.operation) {
                  case DiffOperation.insert:
                    bgColor = Colors.green.withOpacity(0.1);
                    textColor = Colors.green.shade700;
                    prefix = '+ ';
                    break;
                  case DiffOperation.delete:
                    bgColor = Colors.red.withOpacity(0.1);
                    textColor = Colors.red.shade700;
                    prefix = '- ';
                    break;
                  default:
                    bgColor = Colors.transparent;
                    textColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
                    prefix = '  ';
                }
              }

              return GestureDetector(
                onTap: () {
                  if (line.operation != DiffOperation.equal &&
                      !_acceptedLines.contains(i) &&
                      !_rejectedLines.contains(i)) {
                    _toggleLineAcceptance(i);
                  } else if (_acceptedLines.contains(i) || _rejectedLines.contains(i)) {
                    _toggleLineRejection(i);
                  }
                },
                child: Container(
                  color: bgColor,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          prefix,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${line.lineNumber}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          line.content.isEmpty ? ' ' : line.content,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: textColor,
                            height: 1.5,
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
      ],
    );
  }

  Widget _buildDiffLegend() {
    return Row(
      children: [
        _legendItem(Colors.green, '新增'),
        const SizedBox(width: 12),
        _legendItem(Colors.red, '删除'),
        const SizedBox(width: 12),
        _legendItem(Colors.grey, '不变'),
        const SizedBox(width: 12),
        _legendItem(const Color(0xFF7C4DFF), '已接受'),
      ],
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

  List<Widget> _buildActions() {
    if (_showDiff) {
      return [
        TextButton.icon(
          icon: const Icon(Icons.close, size: 16),
          label: const Text('全部拒绝'),
          onPressed: () {
            _rejectAll();
            Navigator.pop(context);
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.done_all, size: 16),
          label: const Text('全部接受'),
          onPressed: () {
            _acceptAll();
            _applyAcceptedChanges();
          },
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('应用选择'),
          onPressed: _applyAcceptedChanges,
        ),
      ];
    }

    return [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ];
  }
}