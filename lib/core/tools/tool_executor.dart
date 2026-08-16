import 'dart:convert';
import 'dart:io';

import 'builtin_tools.dart';
import 'tool_entity.dart';
import 'tool_registry.dart';

/// 工具执行器：接收 AI 的工具调用请求，执行对应工具并返回结果
class ToolExecutor {
  /// 所有工具结果累加的整体上限（字节），仿 Operit
  /// ConversationMarkupManager.MAX_FINAL_TOOL_RESULT_MESSAGE_CHARS。
  static const int _kToolResultTotalBudgetChars = 64 * 1024;

  static final ToolExecutor _instance = ToolExecutor._();
  factory ToolExecutor() => _instance;
  ToolExecutor._();

  final ToolRegistry _registry = ToolRegistry();

  /// 执行单个工具调用
  Future<ToolCallResult> execute(
    ToolCallRequest request, {
    Future<bool> Function(ToolCallRequest request)? confirmOverride,
  }) async {
    final stopwatch = Stopwatch()..start();
    final tool = _registry.get(request.toolId);
    if (tool == null) {
      return ToolCallResult(
        toolId: request.toolId,
        content: '',
        success: false,
        error: '未找到工具: ${request.toolId}',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    if (!tool.enabled) {
      return ToolCallResult(
        toolId: request.toolId,
        content: '',
        success: false,
        error: '工具已禁用: ${tool.name}',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 高风险工具执行前确认（用户拒绝则跳过）
    if (tool.riskLevel == 'high' && confirmOverride != null) {
      final allowed = await confirmOverride(request);
      if (!allowed) {
        return ToolCallResult(
          toolId: request.toolId,
          content: '',
          success: false,
          error: '用户拒绝了该操作',
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }
    }

    ToolCallResult result;
    try {
      switch (tool.type) {
        case ToolType.builtin:
          result = await BuiltinTools.execute(request);
          break;
        case ToolType.skill:
          result = await _executeSkill(tool, request);
          break;
        case ToolType.mcp:
          result = await _executeMcp(tool, request);
          break;
      }
    } catch (e) {
      // 工具执行抛异常时兜底为失败结果，确保每个 tool_call 都有 tool 回执，
      // 避免"tool_calls must be followed by tool messages"的 400 错误
      result = ToolCallResult(
        toolId: request.toolId,
        content: '',
        success: false,
        error: '工具执行异常: $e',
      );
    }
    stopwatch.stop();
    return result.copyWith(durationMs: stopwatch.elapsedMilliseconds);
  }

  /// 批量执行多个工具调用
  Future<List<ToolCallResult>> executeAll(
    List<ToolCallRequest> requests, {
    Future<bool> Function(ToolCallRequest request)? confirmOverride,
    bool Function()? isCancelled,
  }) async {
    final results = <ToolCallResult>[];
    for (final req in requests) {
      if (isCancelled != null && isCancelled()) break;
      results.add(await execute(req, confirmOverride: confirmOverride));
    }
    return results;
  }

  /// 执行自定义技能
  Future<ToolCallResult> _executeSkill(
      ToolEntity skill, ToolCallRequest request) async {
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
  Future<ToolCallResult> _executeMcp(
      ToolEntity mcpTool, ToolCallRequest request) async {
    if (mcpTool.endpoint == null || mcpTool.endpoint!.isEmpty) {
      return ToolCallResult(
        toolId: mcpTool.id,
        content: '',
        success: false,
        error: 'MCP 端点未配置',
      );
    }

    // rawDefinition 中若记录了远端工具名与认证头，使用远端名调用
    var remoteName = mcpTool.id;
    final headers = <String, String>{};
    if (mcpTool.rawDefinition != null && mcpTool.rawDefinition!.isNotEmpty) {
      try {
        final raw = jsonDecode(mcpTool.rawDefinition!) as Map<String, dynamic>;
        remoteName = raw['remote_name']?.toString() ?? remoteName;
        final h = raw['headers'];
        if (h is Map) {
          h.forEach((k, v) => headers[k.toString()] = v.toString());
        }
      } catch (_) {}
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse(mcpTool.endpoint!);
      final httpReq = await client.postUrl(uri);
      httpReq.headers.set('Content-Type', 'application/json');
      httpReq.headers.set('Accept', 'application/json');
      headers.forEach((k, v) => httpReq.headers.set(k, v));

      final body = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'tools/call',
        'params': {
          'name': remoteName,
          'arguments': request.arguments,
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      });
      httpReq.write(body);

      final response =
          await httpReq.close().timeout(const Duration(seconds: 30));
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(text) as Map<String, dynamic>;
        final jsonrpcError = data['error'];
        if (jsonrpcError != null) {
          return ToolCallResult(
            toolId: mcpTool.id,
            content: '',
            success: false,
            error: 'MCP 调用失败: $jsonrpcError',
          );
        }
        final result = data['result'];
        // 解析 MCP 标准结构化内容数组
        String resultText;
        if (result is Map && result['content'] is List) {
          final parts = (result['content'] as List)
              .whereType<Map>()
              .map((c) {
                final ct = c['type']?.toString() ?? 'text';
                if (ct == 'image') return '[图片]';
                if (ct == 'resource') return c['text']?.toString() ?? '[资源]';
                return c['text']?.toString() ?? '';
              })
              .where((s) => s.isNotEmpty)
              .join('\n');
          final isError = (result['isError'] == true);
          if (parts.isEmpty && result['structuredContent'] != null) {
            resultText = jsonEncode(result['structuredContent']);
          } else {
            resultText = parts;
          }
          if (resultText.isEmpty) resultText = jsonEncode(result);
          return ToolCallResult(
            toolId: mcpTool.id,
            content: resultText,
            success: !isError,
            error: isError ? 'MCP 工具返回错误' : null,
          );
        }
        resultText = result?.toString() ?? text;
        return ToolCallResult(
          toolId: mcpTool.id,
          content: resultText,
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

  /// 将工具调用结果格式化为发给 AI 的消息。
  ///
  /// 对超长结果做截断提炼，避免工具原始返回（如 list_dir 大目录、
  /// 网页全文）整体塞进上下文。保留头部并附截断提示，模型据此判断
  /// 是否需要分段读取。
  ///
  /// 整体预算（仿 Operit ConversationMarkupManager）：
  /// 单条结果先按 [maxResultChars] 截断，所有结果累加不超过
  /// [_kToolResultTotalBudgetChars]（64KB）。超预算的条目标记占位回执，
  /// 保持与 assistant tool_calls 的对偶完整（否则 _sanitizeHistory
  /// 会判定对偶残缺而把整轮工具调用连坐丢弃）。
  static List<Map<String, dynamic>> formatToolResultsForAi(
    List<ToolCallRequest> requests,
    List<ToolCallResult> results, {
    int maxResultChars = 6000,
  }) {
    const totalBudget = _kToolResultTotalBudgetChars;
    final messages = <Map<String, dynamic>>[];
    final ts = DateTime.now().millisecondsSinceEpoch;
    var used = 0;
    for (var i = 0; i < results.length && i < requests.length; i++) {
      final result = results[i];
      final request = requests[i];
      final detail = result.success
          ? _trimToolResult(result.content, maxResultChars)
          : '工具执行失败: ${result.error}${result.content.isNotEmpty ? '\n${_trimToolResult(result.content, maxResultChars)}' : ''}';
      final toolCallId = request.callId.isNotEmpty
          ? request.callId
          : 'call_${result.toolId}_${ts}_$i';

      final String content;
      if (used + detail.length > totalBudget) {
        content = '[工具 ${request.toolId} 已执行，但结果因整体上下文预算超限'
            '（累计已用 $used/$totalBudget 字符）未返回全文。'
            '如需细节请用读取类工具按需查询]';
      } else {
        content = detail;
        used += detail.length;
      }
      messages.add({
        'role': 'tool',
        'tool_call_id': toolCallId,
        'content': content,
      });
    }
    return messages;
  }

  /// 截断超长工具结果，保留开头并提示截断位置。
  static String _trimToolResult(String content, int maxChars) {
    if (content.length <= maxChars) return content;
    return '${content.substring(0, maxChars)}\n'
        '...[工具结果过长，已截断：原 ${content.length} 字符，仅显示前 $maxChars 字符]';
  }
}
