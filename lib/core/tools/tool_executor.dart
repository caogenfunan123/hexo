import 'dart:convert';
import 'dart:io';

import 'builtin_tools.dart';
import 'tool_entity.dart';
import 'tool_registry.dart';

/// 工具执行器：接收 AI 的工具调用请求，执行对应工具并返回结果
class ToolExecutor {
  static final ToolExecutor _instance = ToolExecutor._();
  factory ToolExecutor() => _instance;
  ToolExecutor._();

  final ToolRegistry _registry = ToolRegistry();

  /// 执行单个工具调用
  Future<ToolCallResult> execute(ToolCallRequest request) async {
    final tool = _registry.get(request.toolId);
    if (tool == null) {
      return ToolCallResult(
        toolId: request.toolId,
        content: '',
        success: false,
        error: '未找到工具: ${request.toolId}',
      );
    }

    if (!tool.enabled) {
      return ToolCallResult(
        toolId: request.toolId,
        content: '',
        success: false,
        error: '工具已禁用: ${tool.name}',
      );
    }

    switch (tool.type) {
      case ToolType.builtin:
        return BuiltinTools.execute(request);
      case ToolType.skill:
        return _executeSkill(tool, request);
      case ToolType.mcp:
        return _executeMcp(tool, request);
    }
  }

  /// 批量执行多个工具调用
  Future<List<ToolCallResult>> executeAll(List<ToolCallRequest> requests) async {
    final results = <ToolCallResult>[];
    for (final req in requests) {
      results.add(await execute(req));
    }
    return results;
  }

  /// 执行自定义技能
  Future<ToolCallResult> _executeSkill(ToolEntity skill, ToolCallRequest request) async {
    if (skill.skillContent == null || skill.skillContent!.isEmpty) {
      return ToolCallResult(
        toolId: skill.id,
        content: '',
        success: false,
        error: '技能内容为空',
      );
    }
    return ToolCallResult(
      toolId: skill.id,
      content: '技能已激活: ${skill.name}\n\n${skill.skillContent}',
      success: true,
    );
  }

  /// 执行 MCP 工具
  Future<ToolCallResult> _executeMcp(ToolEntity mcpTool, ToolCallRequest request) async {
    if (mcpTool.endpoint == null || mcpTool.endpoint!.isEmpty) {
      return ToolCallResult(
        toolId: mcpTool.id,
        content: '',
        success: false,
        error: 'MCP 端点未配置',
      );
    }

    final client = HttpClient();
    try {
      final uri = Uri.parse(mcpTool.endpoint!);
      final httpReq = await client.postUrl(uri);
      httpReq.headers.set('Content-Type', 'application/json');
      httpReq.headers.set('Accept', 'application/json');

      final body = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'tools/call',
        'params': {
          'name': mcpTool.id,
          'arguments': request.arguments,
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      });
      httpReq.write(body);

      final response = await httpReq.close();
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(text) as Map<String, dynamic>;
        final result = data['result']?['content']?.toString() ??
            data['result']?.toString() ?? text;
        return ToolCallResult(
          toolId: mcpTool.id,
          content: result,
          success: true,
        );
      } else {
        return ToolCallResult(
          toolId: mcpTool.id,
          content: '',
          success: false,
          error: 'MCP HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      return ToolCallResult(
        toolId: mcpTool.id,
        content: '',
        success: false,
        error: 'MCP 调用失败: $e',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 将工具调用结果格式化为发给 AI 的消息
  static List<Map<String, dynamic>> formatToolResultsForAi(
    List<ToolCallRequest> requests,
    List<ToolCallResult> results,
  ) {
    final messages = <Map<String, dynamic>>[];
    for (var i = 0; i < results.length && i < requests.length; i++) {
      final result = results[i];
      final request = requests[i];
      messages.add({
        'role': 'tool',
        'tool_call_id': request.callId.isNotEmpty
            ? request.callId
            : 'call_${result.toolId}_${DateTime.now().millisecondsSinceEpoch}',
        'content': result.success
            ? result.content
            : '工具执行失败: ${result.error}',
      });
    }
    return messages;
  }
}