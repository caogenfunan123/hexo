/// 模型 Provider 常量与接口类型定义
/// 对标 MonkeyCode backend/consts/model.go 的 Provider / InterfaceType 设计
library;

/// 模型服务商
enum ModelProvider {
  openAI('OpenAI'),
  siliconFlow('SiliconFlow'),
  deepSeek('DeepSeek'),
  moonshot('Moonshot'),
  ollama('Ollama'),
  azureOpenAI('AzureOpenAI'),
  hunyuan('Hunyuan'),
  baiLian('BaiLian'),
  volcengine('Volcengine'),
  google('Gemini'),
  baiZhiCloud('BaiZhiCloud'),
  custom('Custom');

  final String label;
  const ModelProvider(this.label);

  static ModelProvider fromCode(String? code) {
    for (final p in ModelProvider.values) {
      if (p.name == code) return p;
    }
    return ModelProvider.custom;
  }

  String get code => name;
}

/// API 接口类型（三种主流协议）
enum InterfaceType {
  openaiChat('openai_chat'),
  openaiResponses('openai_responses'),
  anthropic('anthropic');

  final String code;
  const InterfaceType(this.code);

  static InterfaceType fromCode(String? code) {
    switch (code) {
      case 'openai_responses':
        return InterfaceType.openaiResponses;
      case 'anthropic':
        return InterfaceType.anthropic;
      default:
        return InterfaceType.openaiChat;
    }
  }
}

/// Provider 默认配置
class ProviderPreset {
  final String name;
  final String baseUrl;
  final InterfaceType interfaceType;
  final bool isOverseas;

  const ProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.interfaceType,
    this.isOverseas = false,
  });
}

/// 预置 Provider 列表（添加模型时可快速选择）
const providerPresets = <ProviderPreset>[
  ProviderPreset(name: 'OpenAI', baseUrl: 'https://api.openai.com/v1', interfaceType: InterfaceType.openaiChat, isOverseas: true),
  ProviderPreset(name: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', interfaceType: InterfaceType.openaiChat),
  ProviderPreset(name: 'SiliconFlow', baseUrl: 'https://api.siliconflow.cn/v1', interfaceType: InterfaceType.openaiChat),
  ProviderPreset(name: 'Moonshot', baseUrl: 'https://api.moonshot.cn/v1', interfaceType: InterfaceType.openaiChat),
  ProviderPreset(name: 'Ollama', baseUrl: 'http://localhost:11434/v1', interfaceType: InterfaceType.openaiChat),
  ProviderPreset(name: 'AzureOpenAI', baseUrl: '', interfaceType: InterfaceType.openaiChat, isOverseas: true),
  ProviderPreset(name: 'Hunyuan', baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1', interfaceType: InterfaceType.openaiChat),
  ProviderPreset(name: 'BaiLian', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', interfaceType: InterfaceType.openaiChat),
  ProviderPreset(name: 'Volcengine', baseUrl: 'https://ark.cn-beijing.volces.com/api/v3', interfaceType: InterfaceType.openaiChat),
  ProviderPreset(name: 'Gemini', baseUrl: 'https://generativelanguage.googleapis.com/v1beta', interfaceType: InterfaceType.openaiChat, isOverseas: true),
  ProviderPreset(name: 'BaiZhiCloud', baseUrl: '', interfaceType: InterfaceType.openaiChat),
];

/// 根据模型名推断接口类型（未指定时）
InterfaceType inferInterfaceType(String model) {
  if (model.contains('codex')) return InterfaceType.openaiResponses;
  if (model.contains('claude')) return InterfaceType.anthropic;
  return InterfaceType.openaiChat;
}

/// 工具定义转换（供 function calling 使用）
List<Map<String, dynamic>> toOpenAiTools(List<Map<String, dynamic>> tools) => tools;

/// OpenAI 工具转 Anthropic tool 格式
List<Map<String, dynamic>> toAnthropicTools(List<Map<String, dynamic>> tools) {
  return tools.map((t) {
    final fn = t['function'] as Map<String, dynamic>? ?? {};
    return {
      'name': fn['name'] ?? '',
      'description': fn['description'] ?? '',
      'input_schema': fn['parameters'] ?? {'type': 'object', 'properties': {}},
    };
  }).toList();
}
