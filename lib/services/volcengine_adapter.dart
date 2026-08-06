import 'dart:convert';

/// 火山方舟 ↔ OpenAI Function-Call 格式双向转换器
///
/// 不再粗暴删除 tools 字段，而是做入参转换、出参转换、消息体适配三层处理，
/// 让火山方舟也能跑完整 MCP 工具链。
class VolcengineAdapter {
  /// 检测是否为火山方舟 ARK 服务
  static bool isVolcengineArk(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return false;
    return uri.host.contains('volces.com');
  }

  /// 将 OpenAI 标准请求体转换为火山方舟兼容请求
  static Map<String, dynamic> transformRequest({
    required Map<String, dynamic> originBody,
    int toolRound = 0,
  }) {
    final output = Map<String, dynamic>.from(originBody);

    // 1. 删除火山完全不识别的顶层参数
    output.remove('parallel_tool_calls');
    output.remove('response_format');
    output.remove('logprobs');
    output.remove('top_logprobs');

    // 2. 处理 messages 数组：把 role:tool 的消息做格式改写
    final List<dynamic> msgs = (output['messages'] as List<dynamic>?) ?? [];
    final List<dynamic> newMessages = [];
    for (final msg in msgs) {
      if (msg is! Map) {
        newMessages.add(msg);
        continue;
      }
      final role = msg['role'];
      if (role == 'tool') {
        final toolName = msg['name']?.toString() ?? msg['tool_call_id']?.toString() ?? '未知工具';
        final content = msg['content']?.toString() ?? '';
        newMessages.add({
          'role': 'user',
          'content': '[TOOL_RESULT] 工具 "$toolName" 执行完成\n$content',
        });
      } else {
        newMessages.add(Map<String, dynamic>.from(msg));
      }
    }
    output['messages'] = newMessages;

    // 3. tool_choice 字段做兼容，火山只支持 none / auto
    //    首轮用 auto 让 AI 决定是否调用工具，后续轮次强制 none 避免循环
    if (output.containsKey('tool_choice')) {
      final tc = output['tool_choice'];
      if (tc is Map) {
        output['tool_choice'] = toolRound > 0 ? 'none' : 'auto';
      }
    }
    if (toolRound > 0) {
      output['tool_choice'] = 'none';
    }

    return output;
  }

  /// 把火山 SSE 的 chunk 翻译成内部统一 OpenAI delta 格式
  static Map<String, dynamic>? transformResponseChunk(Map<String, dynamic> arkChunk) {
    if (!arkChunk.containsKey('choices')) return null;
    final choices = arkChunk['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final choice = choices[0];
    if (choice is! Map) return null;
    final delta = choice['delta'];
    if (delta is! Map) return null;

    if (delta['tool_calls'] != null) {
      final List<dynamic> arkToolCalls = (delta['tool_calls'] as List<dynamic>?) ?? [];
      final List<Map<String, dynamic>> openAiToolCalls = [];

      for (final arkTc in arkToolCalls) {
        if (arkTc is! Map) continue;
        final func = (arkTc['function'] as Map?) ?? {};
        openAiToolCalls.add({
          'index': arkTc['index'] ?? 0,
          'id': arkTc['id'],
          'type': 'function',
          'function': {
            'name': func['name'],
            'arguments': func['arguments'],
          },
        });
      }

      if (openAiToolCalls.isNotEmpty) {
        return {
          'choices': [
            {
              'delta': {
                'content': delta['content'],
                'tool_calls': openAiToolCalls,
              },
              'finish_reason': choice['finish_reason'],
            },
          ],
        };
      }
    }

    return null;
  }
}