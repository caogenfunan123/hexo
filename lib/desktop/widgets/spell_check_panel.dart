/// 拼写检查结果面板
/// 显示拼写检查结果，支持点击跳转和替换
library;

import 'package:flutter/material.dart';
import '../../services/spell_check_service.dart';

/// 拼写检查结果面板
class SpellCheckPanel extends StatelessWidget {
  final List<SpellCheckResult> results;
  final ValueChanged<int>? onJumpToOffset;
  final ValueChanged<SpellCheckResult>? onReplace;
  final bool isDark;

  const SpellCheckPanel({
    super.key,
    required this.results,
    this.onJumpToOffset,
    this.onReplace,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = this.isDark;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: isDark ? const Color(0xFF4ADE80).withOpacity(0.5) : const Color(0xFF22C55E).withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              '未发现拼写问题',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white.withOpacity(0.5) : const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '文档拼写检查通过',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white.withOpacity(0.25) : const Color(0xFFD1D5DB),
              ),
            ),
          ],
        ),
      );
    }

    final errors = results.where((r) => r.severity == SpellCheckSeverity.error).length;
    final warnings = results.where((r) => r.severity == SpellCheckSeverity.warning).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 统计摘要
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE5E5EA)),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.spellcheck, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                '${results.length} 个问题',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white.withOpacity(0.7) : const Color(0xFF374151),
                ),
              ),
              if (errors > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$errors 错误',
                    style: TextStyle(fontSize: 10, color: Colors.red.shade400, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              if (warnings > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$warnings 警告',
                    style: TextStyle(fontSize: 10, color: Colors.amber.shade700, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),

        // 结果列表
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: results.length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (_, i) {
              final result = results[i];
              return _SpellCheckItem(
                result: result,
                onTap: () => onJumpToOffset?.call(result.offset),
                onReplace: (suggestion) {
                  onReplace?.call(result);
                },
                isDark: isDark,
                cs: cs,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SpellCheckItem extends StatelessWidget {
  final SpellCheckResult result;
  final VoidCallback onTap;
  final ValueChanged<String> onReplace;
  final bool isDark;
  final ColorScheme cs;

  const _SpellCheckItem({
    required this.result,
    required this.onTap,
    required this.onReplace,
    required this.isDark,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final isError = result.severity == SpellCheckSeverity.error;
    final severityColor = isError ? Colors.red : Colors.amber;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isError ? Icons.error_outline : Icons.warning_amber_rounded,
                    size: 14,
                    color: severityColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    result.word,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: severityColor,
                      decoration: TextDecoration.underline,
                      decorationColor: isError ? Colors.red.withOpacity(0.4) : Colors.amber.withOpacity(0.4),
                      decorationStyle: TextDecorationStyle.wavy,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '行 ${result.line}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white.withOpacity(0.3) : const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
              if (result.suggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: result.suggestions.map((s) {
                    return GestureDetector(
                      onTap: () => onReplace(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(isDark ? 0.15 : 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: cs.primary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}