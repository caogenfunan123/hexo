import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/ai/ai_provider.dart';
import '../core/tools/tool_entity.dart';
import '../core/ai/ai_session_manager.dart';
import '../models/ai_profile.dart';
import '../models/app_settings.dart';
import 'usage_tracker.dart';
import 'volcengine_adapter.dart';

/// AI 回复块（非流式，兼容旧接口使用 Stream 返回）
class StreamChunk {
  final String content;
  final bool isDone;
  final String? finishReason;
  final List<Map<String, dynamic>>? toolCalls;

  const StreamChunk({required this.content, this.isDone = false, this.finishReason, this.toolCalls});
}

/// 拉取模型列表错误类型
enum FetchModelError {
  emptyList,      // 返回空列表
  notImplemented, // 404 接口不存在
  tokenInvalid,   // 401 鉴权失败
  forbidden,      // 403 禁止访问
  timeout,        // 网络超时
  unknown,        // 其他错误
}

/// 拉取模型列表异常
class FetchModelException implements Exception {
  final FetchModelError error;
  final String message;
  const FetchModelException(this.error, this.message);
  @override
  String toString() => message;
}

class AiService {
  String _joinUrl(String base, String path) {
    var b = base.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    var p = path.trim();
    if (!p.startsWith('/')) p = '/$p';
    return '$b$p';
  }

  String _normalizeBase(String base) {
    var b = base.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/chat/completions')) {
      b = b.substring(0, b.length - '/chat/completions'.length);
    }
    return b;
  }

  String _apiRoot(AiProfile profile) {
    var base = _normalizeBase(profile.baseUrl);
    // 用户可能填:
    // https://host
    // https://host/v1
    // https://host/openai/v1
    // https://host/v1/chat/completions (已在 normalize 去掉)
    // https://host/api/coding/v3 (火山引擎)
    // https://host/api/paas/v4 (智谱)
    final uri = Uri.tryParse(base);
    if (uri != null) {
      for (final seg in uri.pathSegments) {
        if (RegExp(r'^v\d+$').hasMatch(seg)) {
          return base;
        }
      }
    }
    if (RegExp(r'/v\d+$').hasMatch(base)) return base;
    return '$base/v1';
  }

  String _chatUrl(AiProfile profile) {
    final root = _apiRoot(profile);
    final path = (profile.apiPath == null || profile.apiPath!.trim().isEmpty)
        ? '/chat/completions'
        : (profile.apiPath!.startsWith('/')
            ? profile.apiPath!.trim()
            : '/${profile.apiPath!.trim()}');
    return _joinUrl(root, path);
  }

  String _modelsUrl(AiProfile profile) {
    final root = _apiRoot(profile);
    return _joinUrl(root, '/models');
  }

  Future<String> _http({
    required String method,
    required String url,
    required String apiKey,
    bool useBearer = true,
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final uri = Uri.parse(url);
      final req = await client.openUrl(method, uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json');
      if (apiKey.isNotEmpty) {
        if (useBearer) {
          req.headers.set('Authorization', 'Bearer $apiKey');
        } else {
          req.headers.set('Authorization', apiKey);
          req.headers.set('api-key', apiKey);
          req.headers.set('x-api-key', apiKey);
        }
      }
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}: $text');
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  AiProfile resolveProfile(AppSettings settings, {AiProfile? override}) {
    if (override != null) return override;
    final p = settings.activeAiProfile;
    if (p != null) return p;
    return AiProfile(
      id: 'temp',
      name: '临时',
      baseUrl: settings.aiBaseUrl,
      apiKey: settings.aiApiKey,
      model: settings.aiModel,
    );
  }

  /// 拉取 OpenAI 兼容 /models 列表，适配各类中转站。
  /// 拉取模型列表
  ///
  /// [customModelsUrl] 可选，当服务商不遵循标准 /v1/models 时，传入完整地址
  Future<List<String>> listModels(AppSettings settings, {AiProfile? profile, String? customModelsUrl}) async {
    final p = resolveProfile(settings, override: profile);
    if (p.apiKey.isEmpty) {
      throw Exception('请先填写 API Key');
    }
    if (p.baseUrl.trim().isEmpty) {
      throw Exception('请先填写 Base URL');
    }
    final url = customModelsUrl?.trim() ?? _modelsUrl(p);
    try {
      final text = await _http(
        method: 'GET',
        url: url,
        apiKey: p.apiKey,
        useBearer: p.useBearer,
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(text);
      final ids = <String>{};
      if (data is Map && data['data'] is List) {
        for (final item in data['data'] as List) {
          if (item is Map && item['id'] != null) {
            ids.add(item['id'].toString());
          } else if (item is String) {
            ids.add(item);
          }
        }
      } else if (data is List) {
        for (final item in data) {
          if (item is Map && item['id'] != null) {
            ids.add(item['id'].toString());
          } else if (item is String) {
            ids.add(item);
          }
        }
      } else if (data is Map && data['models'] is List) {
        for (final item in data['models'] as List) {
          if (item is Map && item['id'] != null) {
            ids.add(item['id'].toString());
          } else if (item is String) {
            ids.add(item);
          }
        }
      }
      final list = ids.toList()..sort();
      if (list.isEmpty) {
        throw const FetchModelException(FetchModelError.emptyList, '密钥未开通可用模型，请检查账号额度，或手动填写模型 ID');
      }
      return list;
    } on TimeoutException {
      throw const FetchModelException(FetchModelError.timeout, '拉取模型列表超时，请检查网络与 API 地址');
    } on FetchModelException {
      rethrow;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('HTTP 404') || msg.contains('404')) {
        throw const FetchModelException(FetchModelError.notImplemented, '该服务商未实现标准模型列表接口，请手动填写模型 ID');
      }
      if (msg.contains('HTTP 401') || msg.contains('401')) {
        throw const FetchModelException(FetchModelError.tokenInvalid, 'API Token 鉴权失败，请核对密钥');
      }
      if (msg.contains('HTTP 403') || msg.contains('403')) {
        throw const FetchModelException(FetchModelError.forbidden, '该密钥被禁止访问模型列表接口，请手动填写模型 ID');
      }
      throw FetchModelException(FetchModelError.unknown, '获取模型列表失败（$url）: $e');
    }
  }

  Future<String> complete({
    required AppSettings settings,
    required String systemPrompt,
    required String userPrompt,
    AiProfile? profile,
    double temperature = 0.7,
  }) async {
    final p = resolveProfile(settings, override: profile);
    if (p.apiKey.isEmpty) {
      throw Exception('请先在设置中配置 AI 中转站并填写 API Key');
    }
    if (p.model.isEmpty) {
      throw Exception('请先选择模型');
    }
    switch (p.interfaceType) {
      case InterfaceType.anthropic:
        return _completeAnthropic(p, systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: temperature);
      case InterfaceType.openaiResponses:
        return _completeOpenAIResponses(p, systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: temperature);
      case InterfaceType.openaiChat:
        return _completeOpenAIChat(p, systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: temperature);
    }
  }

  /// Anthropic Messages 协议请求
  Future<String> _completeAnthropic(AiProfile p, {required String systemPrompt, required String userPrompt, double temperature = 0.7}) async {
    final url = _joinUrl(_normalizeBase(p.baseUrl), '/messages');
    final body = {
      'model': p.model,
      'max_tokens': 4096,
      'temperature': temperature,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userPrompt},
      ],
    };
    final text = await _httpAnthropic(url, p.apiKey, body, useBearer: p.useBearer);
    final data = jsonDecode(text);
    if (data is Map && data['content'] is List) {
      final buf = StringBuffer();
      for (final part in data['content'] as List) {
        if (part is Map && part['type'] == 'text' && part['text'] != null) {
          buf.write(part['text']);
        }
      }
      if (buf.isNotEmpty) return buf.toString();
    }
    throw Exception('Anthropic 返回格式异常: ${text.length > 300 ? text.substring(0, 300) : text}');
  }

  /// OpenAI Responses 协议请求
  Future<String> _completeOpenAIResponses(AiProfile p, {required String systemPrompt, required String userPrompt, double temperature = 0.7}) async {
    final url = _joinUrl(_normalizeBase(p.baseUrl), '/responses');
    final body = {
      'model': p.model,
      'temperature': temperature,
      'max_output_tokens': 4096,
      'input': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    };
    final text = await _http(
      method: 'POST',
      url: url,
      apiKey: p.apiKey,
      useBearer: p.useBearer,
      body: body,
    );
    final data = jsonDecode(text);
    if (data is Map && data['output'] is List) {
      final buf = StringBuffer();
      for (final out in data['output'] as List) {
        if (out is Map && out['type'] == 'message' && out['content'] is List) {
          for (final part in out['content'] as List) {
            if (part is Map && part['type'] == 'output_text' && part['text'] != null) {
              buf.write(part['text']);
            } else if (part is Map && part['type'] == 'text' && part['text'] != null) {
              buf.write(part['text']);
            }
          }
        }
      }
      if (buf.isNotEmpty) return buf.toString();
    }
    if (data is Map && data['output_text'] != null) {
      return data['output_text'].toString();
    }
    throw Exception('OpenAI Responses 返回格式异常: ${text.length > 300 ? text.substring(0, 300) : text}');
  }

  /// Anthropic 专用 HTTP 请求（x-api-key header）
  Future<String> _httpAnthropic(String url, String apiKey, Map<String, dynamic> body, {bool useBearer = false}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final uri = Uri.parse(url);
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json');
      req.headers.set('x-api-key', apiKey);
      req.headers.set('anthropic-version', '2023-06-01');
      final bytes = utf8.encode(jsonEncode(body));
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}: $text');
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _completeOpenAIChat(AiProfile p, {required String systemPrompt, required String userPrompt, double temperature = 0.7}) async {
    final url = _chatUrl(p);
    final body = {
      'model': p.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'temperature': temperature,
      'stream': false,
    };
    final text = await _http(
      method: 'POST',
      url: url,
      apiKey: p.apiKey,
      useBearer: p.useBearer,
      body: body,
    );
    final data = jsonDecode(text);
    if (data is Map && data['choices'] is List && (data['choices'] as List).isNotEmpty) {
      final c0 = (data['choices'] as List).first;
      if (c0 is Map) {
        if (c0['message'] is Map) {
          final content = (c0['message'] as Map)['content'];
          if (content is String) return content;
          if (content is List) {
            // 部分中转返回 content 数组
            final buf = StringBuffer();
            for (final part in content) {
              if (part is Map && part['text'] != null) {
                buf.write(part['text']);
              } else if (part is String) {
                buf.write(part);
              }
            }
            return buf.toString();
          }
        }
        if (c0['text'] != null) return c0['text'].toString();
        if (c0['delta'] is Map && (c0['delta'] as Map)['content'] != null) {
          return (c0['delta'] as Map)['content'].toString();
        }
      }
    }
    if (data is Map && data['output_text'] != null) {
      return data['output_text'].toString();
    }
    throw Exception('AI 返回格式异常: ${text.length > 300 ? text.substring(0, 300) : text}');
  }

  /// 带工具调用的请求（支持 Function Calling）
  /// 返回 {content, toolCalls} —— 如果 AI 调用了工具，toolCalls 非空
  Future<ToolCallResponse> completeWithTools({
    required AppSettings settings,
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    AiProfile? profile,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int toolRound = 0,
  }) async {
    final p = resolveProfile(settings, override: profile);
    if (p.apiKey.isEmpty) {
      throw Exception('请先在设置中配置 AI 中转站并填写 API Key');
    }
    if (p.model.isEmpty) {
      throw Exception('请先选择模型');
    }
    switch (p.interfaceType) {
      case InterfaceType.anthropic:
        return _completeWithToolsAnthropic(p, systemPrompt: systemPrompt, messages: messages, tools: tools, temperature: temperature);
      case InterfaceType.openaiResponses:
        return _completeWithToolsOpenAIResponses(p, systemPrompt: systemPrompt, messages: messages, tools: tools, temperature: temperature);
      case InterfaceType.openaiChat:
        return _completeWithToolsOpenAIChat(p, systemPrompt: systemPrompt, messages: messages, tools: tools, temperature: temperature, toolRound: toolRound);
    }
  }

  /// 将 OpenAI 风格历史转换为 Anthropic 消息格式
  List<Map<String, dynamic>> _toAnthropicMessages(
    List<Map<String, dynamic>> messages,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      final role = m['role']?.toString() ?? 'user';
      if (role == 'system') continue; // system 单独传
      if (role == 'assistant') {
        final content = m['content']?.toString() ?? '';
        final toolCalls = m['tool_calls'];
        if (toolCalls is List && toolCalls.isNotEmpty) {
          final blocks = <Map<String, dynamic>>[];
          if (content.isNotEmpty) {
            blocks.add({'type': 'text', 'text': content});
          }
          for (final tc in toolCalls) {
            if (tc is Map) {
              final fn = tc['function'] as Map<String, dynamic>? ?? {};
              blocks.add({
                'type': 'tool_use',
                'id': tc['id']?.toString() ?? 'toolu_${DateTime.now().microsecondsSinceEpoch}',
                'name': fn['name']?.toString() ?? '',
                'input': _parseJsonArg(fn['arguments']),
              });
            }
          }
          out.add({'role': 'assistant', 'content': blocks});
        } else {
          out.add({'role': 'assistant', 'content': content});
        }
      } else if (role == 'tool') {
        out.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': m['tool_call_id']?.toString() ?? '',
              'content': m['content']?.toString() ?? '',
            },
          ],
        });
      } else {
        out.add({'role': 'user', 'content': m['content']?.toString() ?? ''});
      }
    }
    return out;
  }

  Map<String, dynamic> _parseJsonArg(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map) return Map<String, dynamic>.from(parsed);
      } catch (_) {}
    }
    return {};
  }

  /// Anthropic Messages + tool_use 协议
  Future<ToolCallResponse> _completeWithToolsAnthropic(
    AiProfile p, {
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
  }) async {
    final url = _joinUrl(_normalizeBase(p.baseUrl), '/messages');
    final body = <String, dynamic>{
      'model': p.model,
      'max_tokens': 8192,
      'temperature': temperature,
      'system': systemPrompt,
      'messages': _toAnthropicMessages(messages),
    };
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = toAnthropicTools(tools);
      body['tool_choice'] = {'type': 'auto'};
    }
    final text = await _httpAnthropic(url, p.apiKey, body, useBearer: p.useBearer);
    final data = jsonDecode(text);
    if (data is! Map) throw Exception('Anthropic 返回格式异常');
    final usage = UsageParser.fromAnthropic(data);

    final content = data['content'] as List? ?? [];
    final allMessages = <Map<String, dynamic>>[];
    final textBuf = StringBuffer();
    final toolCalls = <ToolCallRequest>[];
    final contentBlocks = <Map<String, dynamic>>[];

    for (final part in content) {
      if (part is! Map) continue;
      final type = part['type']?.toString();
      if (type == 'text') {
        final t = part['text']?.toString() ?? '';
        textBuf.write(t);
        contentBlocks.add({'type': 'text', 'text': t});
      } else if (type == 'tool_use') {
        final tc = ToolCallRequest.fromAnthropic(Map<String, dynamic>.from(part));
        toolCalls.add(tc);
        contentBlocks.add(Map<String, dynamic>.from(part));
      }
    }

    final assistantMsg = {
      'role': 'assistant',
      if (contentBlocks.isNotEmpty) 'content': contentBlocks,
      if (toolCalls.isNotEmpty)
        'tool_calls': toolCalls
            .map((tc) => {
                  'id': tc.callId,
                  'type': 'function',
                  'function': {'name': tc.toolId, 'arguments': jsonEncode(tc.arguments)},
                })
            .toList(),
    };
    allMessages.addAll(messages);
    allMessages.add(assistantMsg);

    if (toolCalls.isNotEmpty) {
      return ToolCallResponse(content: textBuf.isEmpty ? null : textBuf.toString(), toolCalls: toolCalls, allMessages: allMessages, usage: usage);
    }
    final textContent = textBuf.toString();
    if (textContent.isNotEmpty) return ToolCallResponse(content: textContent, allMessages: allMessages, usage: usage);
    throw Exception('Anthropic 返回空内容');
  }

  /// OpenAI Responses + function_call 协议
  Future<ToolCallResponse> _completeWithToolsOpenAIResponses(
    AiProfile p, {
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
  }) async {
    final url = _joinUrl(_normalizeBase(p.baseUrl), '/responses');
    final input = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];
    final body = <String, dynamic>{
      'model': p.model,
      'temperature': temperature,
      'max_output_tokens': 4096,
      'input': input,
    };
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools.map((t) {
        final fn = t['function'] as Map<String, dynamic>? ?? {};
        return {
          'type': 'function',
          'name': fn['name'] ?? '',
          'description': fn['description'] ?? '',
          'parameters': fn['parameters'] ?? {'type': 'object', 'properties': {}},
        };
      }).toList();
      body['tool_choice'] = 'auto';
    }

    final text = await _http(method: 'POST', url: url, apiKey: p.apiKey, useBearer: p.useBearer, body: body);
    final data = jsonDecode(text);
    if (data is! Map) throw Exception('OpenAI Responses 返回格式异常');
    final usage = UsageParser.fromOpenAiResponses(data);

    final outputs = data['output'] as List? ?? [];
    final textBuf = StringBuffer();
    final toolCalls = <ToolCallRequest>[];
    final outBlocks = <Map<String, dynamic>>[];

    for (final out in outputs) {
      if (out is! Map) continue;
      final type = out['type']?.toString();
      if (type == 'message' && out['content'] is List) {
        for (final part in out['content'] as List) {
          if (part is Map) {
            final pt = part['type']?.toString();
            if (pt == 'output_text' || pt == 'text') {
              final t = part['text']?.toString() ?? '';
              textBuf.write(t);
              outBlocks.add({'type': 'output_text', 'text': t});
            }
          }
        }
      } else if (type == 'function_call') {
        toolCalls.add(ToolCallRequest.fromOpenAIResponses(Map<String, dynamic>.from(out)));
      }
    }

    final assistantMsg = <String, dynamic>{
      'role': 'assistant',
      if (textBuf.isNotEmpty) 'content': textBuf.toString(),
      if (toolCalls.isNotEmpty)
        'tool_calls': toolCalls
            .map((tc) => {
                  'id': tc.callId,
                  'type': 'function',
                  'function': {'name': tc.toolId, 'arguments': jsonEncode(tc.arguments)},
                })
            .toList(),
    };
    final allMessages = <Map<String, dynamic>>[...messages, assistantMsg];

    if (toolCalls.isNotEmpty) {
      return ToolCallResponse(content: textBuf.isEmpty ? null : textBuf.toString(), toolCalls: toolCalls, allMessages: allMessages, usage: usage);
    }
    final content = textBuf.toString();
    if (content.isNotEmpty) return ToolCallResponse(content: content, allMessages: allMessages, usage: usage);
    throw Exception('OpenAI Responses 返回空内容');
  }

  Future<ToolCallResponse> _completeWithToolsOpenAIChat(
    AiProfile p, {
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int toolRound = 0,
  }) async {
    final url = _chatUrl(p);
    final allMessages = <Map<String, dynamic>>[];
    final hasSystemPrompt = messages.isNotEmpty && messages.first['role'] == 'system';
    if (!hasSystemPrompt) {
      allMessages.add({'role': 'system', 'content': systemPrompt});
    }
    allMessages.addAll(messages);

    final body = <String, dynamic>{
      'model': p.model,
      'messages': allMessages,
      'temperature': temperature,
      'stream': false,
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }

    final isVolcengine = VolcengineAdapter.isVolcengineArk(p.baseUrl);
    final finalBody = isVolcengine
        ? VolcengineAdapter.transformRequest(originBody: body, toolRound: toolRound)
        : body;

    final text = await _http(
      method: 'POST',
      url: url,
      apiKey: p.apiKey,
      useBearer: p.useBearer,
      body: finalBody,
    );

    final data = jsonDecode(text);
    if (data is! Map) {
      throw Exception('AI 返回格式异常');
    }
    final usage = UsageParser.fromOpenAiChat(data);

    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('AI 返回无 choices');
    }

    final choice = choices.first as Map;
    final message = choice['message'] as Map?;

    if (message == null) {
      // 兼容非标准格式
      if (choice['text'] != null) {
        return ToolCallResponse(content: choice['text'].toString());
      }
      throw Exception('AI 返回格式异常: ${text.length > 300 ? text.substring(0, 300) : text}');
    }

    // 检查是否有 tool_calls
    final toolCallsRaw = message['tool_calls'];
    if (toolCallsRaw is List && toolCallsRaw.isNotEmpty) {
      final toolCalls = toolCallsRaw
          .whereType<Map>()
          .map((tc) => ToolCallRequest.fromOpenAi(Map<String, dynamic>.from(tc)))
          .toList();

      // 将 assistant 消息（含 tool_calls）加入历史
      allMessages.add(Map<String, dynamic>.from(message));

      return ToolCallResponse(
        content: message['content']?.toString(),
        toolCalls: toolCalls,
        allMessages: allMessages,
        usage: usage,
      );
    }

    // 没有工具调用，返回纯文本
    final content = message['content']?.toString();
    if (content != null && content.isNotEmpty) {
      return ToolCallResponse(content: content, allMessages: allMessages, usage: usage);
    }

    // 如果 content 为空且没有 tool_calls，可能是结束了
    final finishReason = choice['finish_reason']?.toString();
    if (finishReason == 'stop') {
      return ToolCallResponse(content: '', allMessages: allMessages, usage: usage);
    }

    throw Exception('AI 返回空内容');
  }

  /// 将工具执行结果发回 AI 并获取最终回复
  Future<ToolCallResponse> submitToolResults({
    required AppSettings settings,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> toolResults,
    AiProfile? profile,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int toolRound = 0,
  }) async {
    final p = resolveProfile(settings, override: profile);
    if (p.apiKey.isEmpty) {
      throw Exception('请先配置 API Key');
    }
    if (p.model.isEmpty) {
      throw Exception('请先选择模型');
    }

    final allMessages = <Map<String, dynamic>>[...messages, ...toolResults];
    return completeWithTools(
      settings: settings,
      systemPrompt: '',
      messages: allMessages,
      profile: p,
      tools: tools,
      temperature: temperature,
      toolRound: toolRound,
    );
  }

  Future<String> polish(AppSettings s, String content) => complete(
        settings: s,
        systemPrompt: AiSessionManager.polishPrompt,
        userPrompt: content,
      );

  Future<String> continueWrite(AppSettings s, String content) => complete(
        settings: s,
        systemPrompt: AiSessionManager.continueWritePrompt,
        userPrompt: content,
      );

  Future<String> summarize(AppSettings s, String content) => complete(
        settings: s,
        systemPrompt: AiSessionManager.summarizePrompt,
        userPrompt: content,
      );

  Future<String> generateOutline(AppSettings s, String topic) => complete(
        settings: s,
        systemPrompt: AiSessionManager.generateOutlinePrompt,
        userPrompt: topic,
      );

  Future<String> generateCode(AppSettings s, String prompt) => complete(
        settings: s,
        systemPrompt: AiSessionManager.generateCodePrompt,
        userPrompt: prompt,
      );

  Future<String> rewriteSelection(AppSettings s, String selection, String instruction) =>
      complete(
        settings: s,
        systemPrompt: AiSessionManager.rewriteSelectionPrompt,
        userPrompt: '指令: $instruction\n\n原文:\n$selection',
      );

  /// AI 生成 FrontMatter 模板
  Future<String> generateTemplate({
    required AppSettings settings,
    required String userPrompt,
    AiProfile? profile,
  }) async {
    return complete(
      settings: settings,
      profile: profile,
      systemPrompt: AiSessionManager.generateTemplatePrompt,
      userPrompt: '请生成以下模板：\n$userPrompt',
    );
  }

  /// AI 批量迁移：转换 FrontMatter
  Future<String> migrateFrontMatter({
    required AppSettings settings,
    required String sourceFramework,
    required String targetFramework,
    required String frontMatter,
    AiProfile? profile,
  }) async {
    return complete(
      settings: settings,
      profile: profile,
      systemPrompt: AiSessionManager.migrateFrontMatterPrompt(sourceFramework, targetFramework),
      userPrompt: '请转换以下 FrontMatter：\n\n$frontMatter',
    );
  }

  /// AI 分析仓库：自动检测博客框架并生成适配模板
  ///
  /// [repoInfo] 包含仓库中读取到的关键文件内容（配置文件、示例文章等）
  Future<Map<String, dynamic>> analyzeRepoForTemplate({
    required AppSettings settings,
    required String repoInfo,
    AiProfile? profile,
  }) async {
    final result = await complete(
      settings: settings,
      profile: profile,
      systemPrompt: AiSessionManager.analyzeRepoPrompt,
      userPrompt: '请分析以下仓库信息并生成适配的 FrontMatter 模板：\n\n$repoInfo',
    );
    // 提取 JSON 部分
    try {
      final jsonStart = result.indexOf('{');
      final jsonEnd = result.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        final jsonStr = result.substring(jsonStart, jsonEnd + 1);
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'error': '无法解析 AI 返回结果', 'raw': result};
  }
}

/// 工具调用响应
class ToolCallResponse {
  final String? content;
  final List<ToolCallRequest>? toolCalls;
  final List<Map<String, dynamic>> allMessages;
  final Map<String, dynamic>? usage; // token 用量（inputTokens/outputTokens/cacheReadTokens...）

  const ToolCallResponse({
    this.content,
    this.toolCalls,
    this.allMessages = const [],
    this.usage,
  });

  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;
}
