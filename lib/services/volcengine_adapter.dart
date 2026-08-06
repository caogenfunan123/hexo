/// 火山方舟 ↔ OpenAI Function-Call 格式入参转换器
///
/// 将 OpenAI 标准请求体转换为火山方舟兼容格式，让火山方舟也能跑完整 MCP 工具链。
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

  
}