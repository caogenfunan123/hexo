import 'package:flutter/material.dart';
import '../core/ai/ai_model_entity.dart';

/// 全局 AI 模型选择下拉组件
/// 用于所有 AI 页面统一展示模型切换入口
class AiModelPicker extends StatelessWidget {
  final List<AiModelEntity> models;
  final AiModelEntity? selectedModel;
  final ValueChanged<AiModelEntity?> onChanged;
  final String? label;
  final bool showGroupLabel;

  const AiModelPicker({
    super.key,
    required this.models,
    this.selectedModel,
    required this.onChanged,
    this.label,
    this.showGroupLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = models.where((m) => m.enable).toList();
    final colorScheme = Theme.of(context).colorScheme;

    if (enabled.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber, size: 16, color: colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '未配置 AI 模型，请先在设置中配置',
                style: TextStyle(fontSize: 12, color: colorScheme.error),
              ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<String>(
      value: selectedModel != null
          ? '${selectedModel!.apiBase}|${selectedModel!.modelId}'
          : null,
      decoration: InputDecoration(
        labelText: label ?? 'AI 模型',
        prefixIcon: const Icon(Icons.psychology_outlined, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      isExpanded: true,
      items: [
        ...enabled.map((m) => DropdownMenuItem<String>(
              value: '${m.apiBase}|${m.modelId}',
              child: Row(
                children: [
                  Icon(
                    m.group == 'code' ? Icons.code : Icons.chat_outlined,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m.displayLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (showGroupLabel) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        m.group == 'code' ? '代码' : m.group == 'longtext' ? '长文本' : '通用',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )),
      ],
      onChanged: (v) {
        if (v == null) {
          onChanged(null);
          return;
        }
        final parts = v.split('|');
        if (parts.length >= 2) {
          final apiBase = parts.sublist(0, parts.length - 1).join('|');
          final modelId = parts.last;
          final found = enabled.firstWhere(
            (m) => m.apiBase == apiBase && m.modelId == modelId,
            orElse: () => enabled.first,
          );
          onChanged(found);
        }
      },
    );
  }
}

/// 快捷模型选择底部栏（用于对话页面）
class AiModelBottomBar extends StatelessWidget {
  final List<AiModelEntity> models;
  final AiModelEntity? selectedModel;
  final ValueChanged<AiModelEntity?> onChanged;
  final VoidCallback onManageModels;
  final bool showAutoSwitch;

  const AiModelBottomBar({
    super.key,
    required this.models,
    this.selectedModel,
    required this.onChanged,
    required this.onManageModels,
    this.showAutoSwitch = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = models.where((m) => m.enable).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Icon(Icons.psychology_outlined, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedModel != null
                    ? '${selectedModel!.apiBase}|${selectedModel!.modelId}'
                    : (enabled.isNotEmpty
                        ? '${enabled.first.apiBase}|${enabled.first.modelId}'
                        : null),
                isExpanded: true,
                isDense: true,
                style: TextStyle(fontSize: 13, color: cs.onSurface),
                items: enabled.map((m) => DropdownMenuItem<String>(
                      value: '${m.apiBase}|${m.modelId}',
                      child: Text(
                        m.displayLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final parts = v.split('|');
                  if (parts.length >= 2) {
                    final apiBase = parts.sublist(0, parts.length - 1).join('|');
                    final modelId = parts.last;
                    final found = enabled.firstWhere(
                      (m) => m.apiBase == apiBase && m.modelId == modelId,
                      orElse: () => enabled.first,
                    );
                    onChanged(found);
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 18),
            onPressed: onManageModels,
            tooltip: '管理模型',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}