/// 工具格式适配器：将统一 ToolEntity 转换为不同模型厂商的工具格式
///
/// 不同模型对 tools 参数格式存在差异（OpenAI/Anthropic/Gemini 等），
/// 模型切换时工具定义保持同一份抽象，由适配层按模型族转换。
library;

import 'tool_entity.dart';

/// 工具格式适配器
class ToolFormatAdapter {
  /// 根据模型名猜测厂商（用于格式适配）
  static String vendorOf(String modelId) {
    final id = modelId.toLowerCase();
    if (id.contains('claude')) return 'anthropic';
    if (id.contains('gemini')) return 'gemini';
    if (id.contains('deepseek')) return 'deepseek';
    if (id.contains('qwen')) return 'qwen';
    if (id.contains('glm')) return 'glm';
    return 'openai';
  }

  /// 将 ToolEntity 列表转换为指定模型厂商的 tools 格式
  static List<Map<String, dynamic>> toTools(
    List<ToolEntity> tools, {
    String modelId = '',
  }) {
    final vendor = vendorOf(modelId);
    switch (vendor) {
      case 'gemini':
        return tools.map(_toGemini).toList();
      default:
        // OpenAI / DeepSeek / Qwen / GLM 等兼容 OpenAI 格式
        return tools.map((t) => t.toOpenAiFunction()).toList();
    }
  }

  /// Gemini 格式（functionDeclarations）
  static Map<String, dynamic> _toGemini(ToolEntity tool) {
    final props = <String, dynamic>{};
    for (final p in tool.parameters) {
      props[p.name] = {
        'type': p.type == 'number' ? 'NUMBER' : 'STRING',
        'description': p.description,
      };
    }
    return {
      'functionDeclarations': [
        {
          'name': tool.id,
          'description': tool.description,
          'parameters': {
            'type': 'OBJECT',
            'properties': props,
          },
        },
      ],
    };
  }
}
