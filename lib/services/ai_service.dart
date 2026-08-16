import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/ai/ai_message_cleaner.dart';
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
  final String? reasoningContent;

  /// 断线重连标记：UI 收到后应清空当前消息的累积内容（重连从头重发）
  final bool resetStream;

  const StreamChunk({
    required this.content,
    this.isDone = false,
    this.finishReason,
    this.toolCalls,
    this.reasoningContent,
    this.resetStream = false,
  });
}

/// 拉取模型列表错误类型
enum FetchModelError {
  emptyList, // 返回空列表
  notImplemented, // 404 接口不存在
  tokenInvalid, // 401 鉴权失败
  forbidden, // 403 禁止访问
  timeout, // 网络超时
  unknown, // 其他错误
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
  /// 流式断线重连上限（总尝试次数）与指数退避延迟表（ms），
  /// 对标 MonkeyCode task-stream-client 的 RECONNECT_DELAYS_MS。
  static const int _kMaxStreamAttempts = 5;
  static const List<int> _kReconnectDelaysMs = [500, 1000, 2000, 4000, 8000];

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
    } else if (b.endsWith('/responses')) {
      b = b.substring(0, b.length - '/responses'.length);
    } else if (b.endsWith('/messages')) {
      b = b.substring(0, b.length - '/messages'.length);
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
    // https://host/api/plan/v3 (火山引擎)
    // https://host/api/paas/v4 (智谱)
    // https://host/v1beta/openai (Gemini OpenAI 兼容层)
    // 已包含版本段（v1/v2/v3/openai 兼容层等）时，直接作为 API root
    final uri = Uri.tryParse(base);
    if (uri != null) {
      final segs = uri.pathSegments;
      if (segs.isNotEmpty) {
        final last = segs.last.toLowerCase();
        if (last == 'openai' ||
            last == 'v1beta' ||
            RegExp(r'^v\d+$').hasMatch(last)) {
          return base;
        }
      }
    }
    if (RegExp(r'/v\d+$').hasMatch(base)) return base;
    if (RegExp(r'/openai$').hasMatch(base)) return base;
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
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
      final res = await req.close().timeout(const Duration(seconds: 60));
      final text = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 60));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}: $text');
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  /// 发送 SSE 流式 POST 请求，逐事件回调 [onEvent]。
  /// 兼容 OpenAI Chat（data: 单行 JSON）、Anthropic（event: + data:）、[DONE] 终止。
  Future<void> _ssePost({
    required String url,
    required String apiKey,
    required Map<String, dynamic> body,
    bool useBearer = true,
    bool anthropic = false,
    required void Function(String? event, String data) onEvent,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'text/event-stream');
      if (anthropic) {
        if (useBearer) {
          req.headers.set('Authorization', 'Bearer $apiKey');
        } else {
          req.headers.set('x-api-key', apiKey);
        }
        req.headers.set('anthropic-version', '2023-06-01');
      } else if (apiKey.isNotEmpty) {
        if (useBearer) {
          req.headers.set('Authorization', 'Bearer $apiKey');
        } else {
          req.headers.set('Authorization', apiKey);
          req.headers.set('api-key', apiKey);
          req.headers.set('x-api-key', apiKey);
        }
      }
      final bytes = utf8.encode(jsonEncode(body));
      req.contentLength = bytes.length;
      req.add(bytes);
      // 响应头超时 2 分钟：推理模型首 token 可能思考较久
      final res = await req.close().timeout(const Duration(seconds: 120));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final err = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 120));
        throw Exception('HTTP ${res.statusCode}: $err');
      }
      await _sseRead(res, onEvent);
    } finally {
      client.close(force: true);
    }
  }

  /// 逐行解析 SSE 字节流，按空行切分事件，回调 [onEvent]。
  /// 每事件间隔超过 60s（空闲超时）抛 TimeoutException，避免模型卡死。
  Future<void> _sseRead(
    HttpClientResponse res,
    void Function(String? event, String data) onEvent,
  ) async {
    String? pendingEvent;
    final dataLines = <String>[];
    final lineBuf = StringBuffer();
    // 空闲超时 5 分钟：推理模型思考期可能长时间无数据输出，
    // 之前 60s 太短导致"莫名其妙断开"（调用工具多/时间长时尤其明显）
    await for (final chunk in res
        .transform(utf8.decoder)
        .timeout(const Duration(minutes: 5))) {
      lineBuf.write(chunk);
      while (true) {
        final s = lineBuf.toString();
        final nl = s.indexOf('\n');
        if (nl < 0) break;
        var line = s.substring(0, nl);
        if (line.endsWith('\r')) {
          line = line.substring(0, line.length - 1);
        }
        lineBuf.clear();
        lineBuf.write(s.substring(nl + 1));
        if (line.isEmpty) {
          if (dataLines.isNotEmpty) {
            onEvent(pendingEvent, dataLines.join('\n'));
            dataLines.clear();
            pendingEvent = null;
          }
        } else if (line.startsWith('event:')) {
          pendingEvent = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trim());
        }
      }
    }
    if (dataLines.isNotEmpty) {
      onEvent(pendingEvent, dataLines.join('\n'));
    }
  }

  /// 流式版 completeWithTools：逐块通过 [onChunk] 回调文本/推理内容，
  /// 返回与 [completeWithTools] 一致的完整 [ToolCallResponse]（含 toolCalls）。
  Future<ToolCallResponse> completeWithToolsStreaming({
    required AppSettings settings,
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    AiProfile? profile,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int toolRound = 0,
    required void Function(StreamChunk chunk) onChunk,
  }) async {
    final p = resolveProfile(settings, override: profile);
    if (p.apiKey.isEmpty) {
      throw Exception('请先在设置中配置 AI 中转站并填写 API Key');
    }
    if (p.model.isEmpty) {
      throw Exception('请先选择模型');
    }

    // 断线重连（对标 MonkeyCode task-stream-client）：最多 [_kMaxStreamAttempts]
    // 次尝试，重试间隔按指数退避延迟表递增。重连前通过 resetStream 通知 UI
    // 清空已累积内容，避免与重连后从头流式输出的内容重复。
    for (var attempt = 0; attempt < _kMaxStreamAttempts; attempt++) {
      try {
        switch (p.interfaceType) {
          case InterfaceType.anthropic:
            return await _streamAnthropic(
              p,
              systemPrompt: systemPrompt,
              messages: messages,
              tools: tools,
              temperature: temperature,
              onChunk: onChunk,
            );
          case InterfaceType.openaiResponses:
            // Responses 接口暂回退非流式，通过 onChunk 一次性透出
            final resp = await _completeWithToolsOpenAIResponses(
              p,
              systemPrompt: systemPrompt,
              messages: messages,
              tools: tools,
              temperature: temperature,
            ).timeout(const Duration(seconds: 90));
            if (resp.content != null && resp.content!.isNotEmpty) {
              onChunk(StreamChunk(
                  content: resp.content!,
                  reasoningContent: resp.reasoningContent));
            }
            return resp;
          default:
            return await _streamOpenAIChat(
              p,
              systemPrompt: systemPrompt,
              messages: messages,
              tools: tools,
              temperature: temperature,
              toolRound: toolRound,
              onChunk: onChunk,
            );
        }
      } on SocketException {
        if (!await _scheduleStreamReconnect(attempt, onChunk)) rethrow;
      } on HttpException {
        if (!await _scheduleStreamReconnect(attempt, onChunk)) rethrow;
      } on TimeoutException {
        if (!await _scheduleStreamReconnect(attempt, onChunk)) rethrow;
      }
    }
    throw Exception('断线重连失败');
  }

  /// 流式重连调度：发 resetStream 通知 UI 清空累积，按指数退避表等待后
  /// 允许继续重试。返回 false 表示已达到重试上限，应终止重试。
  Future<bool> _scheduleStreamReconnect(
    int attempt,
    void Function(StreamChunk chunk) onChunk,
  ) async {
    if (attempt >= _kMaxStreamAttempts - 1) return false;
    onChunk(const StreamChunk(content: '', resetStream: true));
    final idx = attempt < _kReconnectDelaysMs.length
        ? attempt
        : _kReconnectDelaysMs.length - 1;
    await Future<void>.delayed(Duration(milliseconds: _kReconnectDelaysMs[idx]));
    return true;
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
  Future<List<String>> listModels(
    AppSettings settings, {
    AiProfile? profile,
    String? customModelsUrl,
  }) async {
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
        throw const FetchModelException(
          FetchModelError.emptyList,
          '密钥未开通可用模型，请检查账号额度，或手动填写模型 ID',
        );
      }
      return list;
    } on TimeoutException {
      throw const FetchModelException(
        FetchModelError.timeout,
        '拉取模型列表超时，请检查网络与 API 地址',
      );
    } on FetchModelException {
      rethrow;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('HTTP 404') || msg.contains('404')) {
        throw const FetchModelException(
          FetchModelError.notImplemented,
          '该服务商未实现标准模型列表接口，请手动填写模型 ID',
        );
      }
      if (msg.contains('HTTP 401') || msg.contains('401')) {
        throw const FetchModelException(
          FetchModelError.tokenInvalid,
          'API Token 鉴权失败，请核对密钥',
        );
      }
      if (msg.contains('HTTP 403') || msg.contains('403')) {
        throw const FetchModelException(
          FetchModelError.forbidden,
          '该密钥被禁止访问模型列表接口，请手动填写模型 ID',
        );
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
        return _completeAnthropic(
          p,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          temperature: temperature,
        );
      case InterfaceType.openaiResponses:
        return _completeOpenAIResponses(
          p,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          temperature: temperature,
        );
      case InterfaceType.openaiChat:
        return _completeOpenAIChat(
          p,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          temperature: temperature,
        );
    }
  }

  /// Anthropic Messages 协议请求
  Future<String> _completeAnthropic(
    AiProfile p, {
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.7,
  }) async {
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
    final text = await _httpAnthropic(
      url,
      p.apiKey,
      body,
      useBearer: p.useBearer,
    );
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
    throw Exception(
      'Anthropic 返回格式异常: ${text.length > 300 ? text.substring(0, 300) : text}',
    );
  }

  /// OpenAI Responses 协议请求
  Future<String> _completeOpenAIResponses(
    AiProfile p, {
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.7,
  }) async {
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
            if (part is Map &&
                part['type'] == 'output_text' &&
                part['text'] != null) {
              buf.write(part['text']);
            } else if (part is Map &&
                part['type'] == 'text' &&
                part['text'] != null) {
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
    if (data is Map &&
        data['choices'] is List &&
        (data['choices'] as List).isNotEmpty) {
      final c0 = (data['choices'] as List).first;
      if (c0 is Map) {
        if (c0['message'] is Map &&
            (c0['message'] as Map)['content'] is String) {
          return (c0['message'] as Map)['content'] as String;
        }
      }
    }
    throw Exception(
      'OpenAI Responses 返回格式异常: ${text.length > 300 ? text.substring(0, 300) : text}',
    );
  }

  /// Anthropic 专用 HTTP 请求（x-api-key header）
  Future<String> _httpAnthropic(
    String url,
    String apiKey,
    Map<String, dynamic> body, {
    bool useBearer = false,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final uri = Uri.parse(url);
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json');
      if (useBearer) {
        req.headers.set('Authorization', 'Bearer $apiKey');
      } else {
        req.headers.set('x-api-key', apiKey);
      }
      req.headers.set('anthropic-version', '2023-06-01');
      final bytes = utf8.encode(jsonEncode(body));
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(const Duration(seconds: 60));
      final text = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 60));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}: $text');
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _completeOpenAIChat(
    AiProfile p, {
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.7,
  }) async {
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
    if (data is Map &&
        data['choices'] is List &&
        (data['choices'] as List).isNotEmpty) {
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
    throw Exception(
      'AI 返回格式异常: ${text.length > 300 ? text.substring(0, 300) : text}',
    );
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
        return _completeWithToolsAnthropic(
          p,
          systemPrompt: systemPrompt,
          messages: messages,
          tools: tools,
          temperature: temperature,
        );
      case InterfaceType.openaiResponses:
        return _completeWithToolsOpenAIResponses(
          p,
          systemPrompt: systemPrompt,
          messages: messages,
          tools: tools,
          temperature: temperature,
        );
      case InterfaceType.openaiChat:
        return _completeWithToolsOpenAIChat(
          p,
          systemPrompt: systemPrompt,
          messages: messages,
          tools: tools,
          temperature: temperature,
          toolRound: toolRound,
        );
    }
  }

  /// 将历史中的增量摘要消息（is_summary 标记的 system 消息）合并进 system，
  /// Anthropic 协议不允许 system 消息出现在 messages 里，需单独放入 body.system。
  String _mergeSummaryIntoSystem(
    String systemPrompt,
    List<Map<String, dynamic>> messages,
  ) {
    final summary = messages
        .where((m) =>
            m['role'] == 'system' && m['is_summary'] == true)
        .map((m) => m['content']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .join('\n\n');
    if (summary.isEmpty) return systemPrompt;
    return '$systemPrompt\n\n[对话摘要]\n$summary';
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
        final raw = m['content'];
        final content = AiMessageCleaner.cleanForModel(_contentToText(raw));
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
                'id':
                    tc['id']?.toString() ??
                    'toolu_${DateTime.now().microsecondsSinceEpoch}',
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
              'content': _contentToText(m['content']),
            },
          ],
        });
      } else {
        out.add({'role': 'user', 'content': _contentToText(m['content'])});
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

  /// 从消息 content 字段提取纯文本（兼容 String 或 content blocks 数组）
  String _contentToText(dynamic raw) {
    if (raw is String) return raw.trim();
    if (raw is List) {
      final buf = StringBuffer();
      for (final part in raw) {
        if (part is Map) {
          if (part['type'] == 'tool_use' || part['type'] == 'tool_result')
            continue;
          final t = part['text']?.toString();
          if (t != null && t.isNotEmpty) buf.write(t);
        } else if (part is String) {
          buf.write(part);
        }
      }
      return buf.toString();
    }
    return raw?.toString() ?? '';
  }

  /// 将 OpenAI 风格历史转换为 Responses API 的 input 条目
  /// - assistant 消息 + tool_calls → function_call 条目
  /// - tool 消息 → function_call_output 条目
  List<Map<String, dynamic>> _toOpenAiResponsesInput(
    String systemPrompt,
    List<Map<String, dynamic>> messages,
  ) {
    final input = <Map<String, dynamic>>[];
    final hasSystem = messages.isNotEmpty && messages.first['role'] == 'system';
    if (!hasSystem && systemPrompt.isNotEmpty) {
      input.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      final role = m['role']?.toString() ?? 'user';
      if (role == 'system') {
        input.add({
          'role': 'system',
          'content': m['content']?.toString() ?? '',
        });
        continue;
      }
      if (role == 'assistant') {
        final text = AiMessageCleaner.cleanForModel(_contentToText(m['content']));
        final toolCalls = m['tool_calls'];
        if (toolCalls is List && toolCalls.isNotEmpty) {
          if (text.isNotEmpty) {
            input.add({
              'role': 'assistant',
              'content': [
                {'type': 'output_text', 'text': text},
              ],
            });
          }
          for (final tc in toolCalls) {
            if (tc is Map) {
              final fn = tc['function'] as Map<String, dynamic>? ?? {};
              final callId =
                  tc['id']?.toString() ?? tc['call_id']?.toString() ?? '';
              input.add({
                'type': 'function_call',
                'call_id': callId,
                'name': fn['name']?.toString() ?? '',
                'arguments': fn['arguments'] is String
                    ? fn['arguments'] as String
                    : jsonEncode(fn['arguments'] ?? {}),
              });
            }
          }
        } else {
          input.add({'role': 'assistant', 'content': text});
        }
      } else if (role == 'tool') {
        input.add({
          'type': 'function_call_output',
          'call_id': m['tool_call_id']?.toString() ?? '',
          'output': _contentToText(m['content']),
        });
      } else {
        input.add({'role': 'user', 'content': m['content']?.toString() ?? ''});
      }
    }
    return input;
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
      'max_tokens': 4096,
      'temperature': temperature,
      'system': _mergeSummaryIntoSystem(systemPrompt, messages),
      'messages': _toAnthropicMessages(messages),
    };
    if (p.thinkingEnabled) {
      body['thinking'] = {
        'type': 'enabled',
        'budget_tokens': p.reasoningBudgetTokens,
      };
    }
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = toAnthropicTools(tools);
      body['tool_choice'] = {'type': 'auto'};
    }
    final text = await _httpAnthropic(
      url,
      p.apiKey,
      body,
      useBearer: p.useBearer,
    );
    final data = jsonDecode(text);
    if (data is! Map) throw Exception('Anthropic 返回格式异常');
    final usage = UsageParser.fromAnthropic(data);

    final content = data['content'] as List? ?? [];
    final allMessages = <Map<String, dynamic>>[];
    final textBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    final toolCalls = <ToolCallRequest>[];
    final contentBlocks = <Map<String, dynamic>>[];

    for (final part in content) {
      if (part is! Map) continue;
      final type = part['type']?.toString();
      if (type == 'text') {
        final t = part['text']?.toString() ?? '';
        textBuf.write(t);
        contentBlocks.add({'type': 'text', 'text': t});
      } else if (type == 'thinking' || type == 'redacted_thinking') {
        final t = part['thinking']?.toString() ?? '';
        if (t.isNotEmpty) {
          reasoningBuf.write(t);
        }
      } else if (type == 'tool_use') {
        final tc = ToolCallRequest.fromAnthropic(
          Map<String, dynamic>.from(part),
        );
        toolCalls.add(tc);
        contentBlocks.add(Map<String, dynamic>.from(part));
      }
    }

    final reasoningText = reasoningBuf.isEmpty ? null : reasoningBuf.toString();

    final assistantMsg = {
      'role': 'assistant',
      if (contentBlocks.isNotEmpty) 'content': contentBlocks,
      if (toolCalls.isNotEmpty)
        'tool_calls': toolCalls
            .map(
              (tc) => {
                'id': tc.callId,
                'type': 'function',
                'function': {
                  'name': tc.toolId,
                  'arguments': jsonEncode(tc.arguments),
                },
              },
            )
            .toList(),
    };
    allMessages.addAll(messages);
    allMessages.add(assistantMsg);

    if (toolCalls.isNotEmpty) {
      return ToolCallResponse(
        content: textBuf.isEmpty ? null : textBuf.toString(),
        toolCalls: toolCalls,
        allMessages: allMessages,
        usage: usage,
        reasoningContent: reasoningText,
      );
    }
    final textContent = textBuf.toString();
    if (textContent.isNotEmpty)
      return ToolCallResponse(
        content: textContent,
        allMessages: allMessages,
        usage: usage,
        reasoningContent: reasoningText,
      );
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
    final input = _toOpenAiResponsesInput(systemPrompt, messages);
    final body = <String, dynamic>{
      'model': p.model,
      'temperature': temperature,
      'max_output_tokens': 4096,
      'input': input,
    };
    if (p.thinkingEnabled) {
      body['reasoning'] = {'effort': p.reasoningEffort};
    }
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools.map((t) {
        final fn = t['function'] as Map<String, dynamic>? ?? {};
        return {
          'type': 'function',
          'name': fn['name'] ?? '',
          'description': fn['description'] ?? '',
          'parameters':
              fn['parameters'] ?? {'type': 'object', 'properties': {}},
        };
      }).toList();
      body['tool_choice'] = 'auto';
    }

    final text = await _http(
      method: 'POST',
      url: url,
      apiKey: p.apiKey,
      useBearer: p.useBearer,
      body: body,
    );
    final data = jsonDecode(text);
    if (data is! Map) throw Exception('OpenAI Responses 返回格式异常');
    final usage = UsageParser.fromOpenAiResponses(data);

    final outputs = data['output'] as List? ?? [];
    final textBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
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
            } else if (pt == 'reasoning') {
              final t =
                  part['summary']?.toString() ?? part['text']?.toString() ?? '';
              if (t.isNotEmpty) reasoningBuf.write(t);
            }
          }
        }
      } else if (type == 'reasoning') {
        final t = out['summary']?.toString() ?? '';
        if (t.isNotEmpty) reasoningBuf.write(t);
      } else if (type == 'function_call') {
        if (out['name']?.toString().isNotEmpty == true) {
          toolCalls.add(
            ToolCallRequest.fromOpenAIResponses(Map<String, dynamic>.from(out)),
          );
        }
      }
    }
    final reasoningText = reasoningBuf.isEmpty ? null : reasoningBuf.toString();

    final assistantMsg = <String, dynamic>{
      'role': 'assistant',
      if (textBuf.isNotEmpty) 'content': textBuf.toString(),
      if (toolCalls.isNotEmpty)
        'tool_calls': toolCalls
            .map(
              (tc) => {
                'id': tc.callId,
                'type': 'function',
                'function': {
                  'name': tc.toolId,
                  'arguments': jsonEncode(tc.arguments),
                },
              },
            )
            .toList(),
    };
    final allMessages = <Map<String, dynamic>>[...messages, assistantMsg];

    if (toolCalls.isNotEmpty) {
      return ToolCallResponse(
        content: textBuf.isEmpty ? null : textBuf.toString(),
        toolCalls: toolCalls,
        allMessages: allMessages,
        usage: usage,
        reasoningContent: reasoningText,
      );
    }
    final content = textBuf.toString();
    if (content.isNotEmpty)
      return ToolCallResponse(
        content: content,
        allMessages: allMessages,
        usage: usage,
        reasoningContent: reasoningText,
      );
    throw Exception('OpenAI Responses 返回空内容');
  }

  /// OpenAI Chat 流式实现：SSE 逐块解析 delta.content / delta.reasoning_content /
  /// delta.tool_calls，实时通过 [onChunk] 回调，结束时返回完整 ToolCallResponse。
  Future<ToolCallResponse> _streamOpenAIChat(
    AiProfile p, {
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int toolRound = 0,
    required void Function(StreamChunk chunk) onChunk,
  }) async {
    final url = _chatUrl(p);
    final allMessages = <Map<String, dynamic>>[];
    final hasSystemPrompt =
        messages.isNotEmpty && messages.first['role'] == 'system';
    if (!hasSystemPrompt && systemPrompt.isNotEmpty) {
      allMessages.add({'role': 'system', 'content': systemPrompt});
    }
    // 归一化历史：Anthropic 产生的 content 为 blocks 数组，OpenAI Chat 要求字符串。
    // 保留 tool_calls 键以维持多轮工具配对。
    for (final m in messages) {
      final role = m['role']?.toString();
      if (role == 'system') {
        // 剥离 is_summary 内部标记，避免未知字段被严格校验的服务端拒绝
        allMessages.add(
          Map<String, dynamic>.from(m)..remove('is_summary'),
        );
        continue;
      }
      final normalized = Map<String, dynamic>.from(m);
      final text = _contentToText(m['content']);
      normalized['content'] = role == 'assistant'
          ? AiMessageCleaner.cleanForModel(text)
          : text;
      allMessages.add(normalized);
    }

    final body = <String, dynamic>{
      'model': p.model,
      'messages': allMessages,
      'temperature': temperature,
      'stream': true,
    };

    if (p.thinkingEnabled) {
      if (!VolcengineAdapter.isVolcengineArk(p.baseUrl)) {
        body['reasoning_effort'] = p.reasoningEffort;
      }
    }

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }

    final isVolcengine = VolcengineAdapter.isVolcengineArk(p.baseUrl);
    final finalBody = isVolcengine
        ? VolcengineAdapter.transformRequest(
            originBody: body,
            toolRound: toolRound,
          )
        : body;

    final textBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    final toolAcc = <int, _StreamToolCallAcc>{};
    String? finishReason;
    Map<String, dynamic>? usage;
    var completed = false;
    // 同一连接内按 data 原文去重，防御服务端重复推送同一事件
    final seenData = <String>{};

    try {
      await _ssePost(
        url: url,
        apiKey: p.apiKey,
        body: finalBody,
        useBearer: p.useBearer,
        onEvent: (event, data) {
          if (data == '[DONE]') {
            completed = true;
            return;
          }
          if (data.isEmpty || !seenData.add(data)) return;
          dynamic parsed;
          try {
            parsed = jsonDecode(data);
          } catch (_) {
            return;
          }
          if (parsed is! Map) return;
          if (parsed['usage'] is Map && usage == null) {
            usage = Map<String, dynamic>.from(parsed['usage'] as Map);
          }
          final choices = parsed['choices'];
          if (choices is! List || choices.isEmpty) return;
          final choice = choices.first;
          if (choice is! Map) return;
          final fr = choice['finish_reason']?.toString();
          if (fr != null && fr.isNotEmpty) {
            finishReason = fr;
            completed = true;
          }
          final delta = choice['delta'];
          if (delta is! Map) return;

          final c = delta['content']?.toString();
          if (c != null && c.isNotEmpty) {
            textBuf.write(c);
            onChunk(StreamChunk(content: c));
          }
          final reasoning = delta['reasoning_content']?.toString() ??
              delta['reasoning']?.toString();
          if (reasoning != null && reasoning.isNotEmpty) {
            reasoningBuf.write(reasoning);
            onChunk(StreamChunk(content: '', reasoningContent: reasoning));
          }
          final tcs = delta['tool_calls'];
          if (tcs is List) {
            for (final t in tcs) {
              if (t is! Map) continue;
              final index = (t['index'] as num?)?.toInt() ?? 0;
              final acc = toolAcc.putIfAbsent(index, () => _StreamToolCallAcc());
              if (t['id'] != null) acc.id = t['id'].toString();
              final fn = t['function'];
              if (fn is Map) {
                if (fn['name'] != null) acc.name = fn['name'].toString();
                final args = fn['arguments']?.toString();
                if (args != null && args.isNotEmpty) acc.arguments.write(args);
              }
            }
          }
        },
      );
    } on SocketException {
      if (!completed) rethrow;
    } on HttpException {
      if (!completed) rethrow;
    } on TimeoutException {
      if (!completed) rethrow;
    }

    final reasoningText = reasoningBuf.isEmpty ? null : reasoningBuf.toString();
    final toolCalls = toolAcc.values
        .where((a) => a.name.isNotEmpty)
        .map((a) => ToolCallRequest.fromOpenAi({
              'id': a.id,
              'function': {'name': a.name, 'arguments': a.arguments.toString()},
            }))
        .toList();

    final assistantMsg = <String, dynamic>{
      'role': 'assistant',
      if (textBuf.isNotEmpty) 'content': textBuf.toString(),
      if (toolCalls.isNotEmpty)
        'tool_calls': toolCalls
            .map(
              (tc) => {
                'id': tc.callId,
                'type': 'function',
                'function': {
                  'name': tc.toolId,
                  'arguments': jsonEncode(tc.arguments),
                },
              },
            )
            .toList(),
    };
    final allMsgs = <Map<String, dynamic>>[...messages, assistantMsg];
    final parsedUsage = usage == null ? null : UsageParser.fromOpenAiChat(usage!);

    if (toolCalls.isNotEmpty) {
      return ToolCallResponse(
        content: textBuf.isEmpty ? null : textBuf.toString(),
        toolCalls: toolCalls,
        allMessages: allMsgs,
        usage: parsedUsage,
        reasoningContent: reasoningText,
      );
    }
    final content = textBuf.toString();
    if (content.isNotEmpty) {
      return ToolCallResponse(
        content: content,
        allMessages: allMsgs,
        usage: parsedUsage,
        reasoningContent: reasoningText,
      );
    }
    throw Exception(
      'AI 流式返回空内容（finish_reason=$finishReason）',
    );
  }

  /// Anthropic 流式实现：SSE 事件 content_block_start / content_block_delta /
  /// message_delta / message_stop 逐块解析。
  Future<ToolCallResponse> _streamAnthropic(
    AiProfile p, {
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    required void Function(StreamChunk chunk) onChunk,
  }) async {
    final url = _joinUrl(_normalizeBase(p.baseUrl), '/messages');
    final body = <String, dynamic>{
      'model': p.model,
      'max_tokens': 4096,
      'temperature': temperature,
      'system': _mergeSummaryIntoSystem(systemPrompt, messages),
      'messages': _toAnthropicMessages(messages),
      'stream': true,
    };
    if (p.thinkingEnabled) {
      body['thinking'] = {
        'type': 'enabled',
        'budget_tokens': p.reasoningBudgetTokens,
      };
    }
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = toAnthropicTools(tools);
      body['tool_choice'] = {'type': 'auto'};
    }

    final textBlocks = <int, StringBuffer>{};
    final thinkingBlocks = <int, StringBuffer>{};
    final toolBlocks = <int, _StreamToolCallAcc>{};
    final blockOrder = <int>[];
    Map<String, dynamic>? usage;
    var completed = false;
    // 同一连接内按 data 原文去重，防御服务端重复推送同一事件
    final seenData = <String>{};

    try {
      await _ssePost(
        url: url,
        apiKey: p.apiKey,
        body: body,
        useBearer: p.useBearer,
        anthropic: true,
        onEvent: (event, data) {
          if (data == '[DONE]') {
            completed = true;
            return;
          }
          if (data.isEmpty || !seenData.add(data)) return;
          dynamic parsed;
          try {
            parsed = jsonDecode(data);
          } catch (_) {
            return;
          }
          if (parsed is! Map) return;
          final type = parsed['type']?.toString();
          final index = (parsed['index'] as num?)?.toInt() ?? 0;
          switch (type) {
            case 'content_block_start':
              final block = parsed['content_block'];
              if (block is Map) {
                if (!blockOrder.contains(index)) blockOrder.add(index);
                final btype = block['type']?.toString();
                if (btype == 'text') {
                  textBlocks.putIfAbsent(index, () => StringBuffer());
                } else if (btype == 'thinking' ||
                    btype == 'redacted_thinking') {
                  thinkingBlocks.putIfAbsent(index, () => StringBuffer());
                } else if (btype == 'tool_use') {
                  toolBlocks.putIfAbsent(index, () => _StreamToolCallAcc())
                    ..id = block['id']?.toString() ?? ''
                    ..name = block['name']?.toString() ?? '';
                }
              }
            case 'content_block_delta':
              final delta = parsed['delta'];
              if (delta is Map) {
                final dtype = delta['type']?.toString();
                if (dtype == 'text_delta') {
                  final t = delta['text']?.toString() ?? '';
                  if (t.isNotEmpty) {
                    textBlocks.putIfAbsent(index, () => StringBuffer()).write(t);
                    onChunk(StreamChunk(content: t));
                  }
                } else if (dtype == 'thinking_delta') {
                  final t = delta['thinking']?.toString() ?? '';
                  if (t.isNotEmpty) {
                    thinkingBlocks
                        .putIfAbsent(index, () => StringBuffer())
                        .write(t);
                    onChunk(StreamChunk(content: '', reasoningContent: t));
                  }
                } else if (dtype == 'input_json_delta') {
                  final t = delta['partial_json']?.toString() ?? '';
                  if (t.isNotEmpty) {
                    toolBlocks
                        .putIfAbsent(index, () => _StreamToolCallAcc())
                        .arguments
                        .write(t);
                  }
                }
              }
            case 'message_delta':
              final u = parsed['usage'];
              if (u is Map) usage = Map<String, dynamic>.from(u);
            case 'message_stop':
              completed = true;
              break;
          }
        },
      );
    } on SocketException {
      if (!completed) rethrow;
    } on HttpException {
      if (!completed) rethrow;
    } on TimeoutException {
      if (!completed) rethrow;
    }

    final textBuf = StringBuffer();
    final thinkingBuf = StringBuffer();
    final contentBlocks = <Map<String, dynamic>>[];
    final toolCalls = <ToolCallRequest>[];
    for (final index in blockOrder) {
      final t = textBlocks[index]?.toString();
      if (t != null && t.isNotEmpty) {
        textBuf.write(t);
        contentBlocks.add({'type': 'text', 'text': t});
      }
      final acc = toolBlocks[index];
      if (acc != null && acc.name.isNotEmpty) {
        toolCalls.add(ToolCallRequest.fromAnthropic({
          'id': acc.id,
          'name': acc.name,
          'input': acc.arguments.toString(),
        }));
        contentBlocks.add({
          'type': 'tool_use',
          'id': acc.id,
          'name': acc.name,
          'input': _parseJsonArg(acc.arguments.toString()),
        });
      }
    }
    for (final b in thinkingBlocks.values) {
      thinkingBuf.write(b.toString());
    }
    final reasoningText = thinkingBuf.isEmpty ? null : thinkingBuf.toString();
    final parsedUsage = usage == null ? null : UsageParser.fromAnthropic(usage!);
    // 统一存储为 OpenAI 风格（带 tool_calls 键），dispatcher 据此将消息与
    // 后续 tool 回执配对；content 保留原始 blocks 供 Anthropic 二次发送。
    final assistantMsg = <String, dynamic>{
      'role': 'assistant',
      if (contentBlocks.isNotEmpty) 'content': contentBlocks,
      if (toolCalls.isNotEmpty)
        'tool_calls': toolCalls
            .map((tc) => {
                  'id': tc.callId,
                  'type': 'function',
                  'function': {
                    'name': tc.toolId,
                    'arguments': jsonEncode(tc.arguments),
                  },
                })
            .toList(),
    };
    final allMsgs = <Map<String, dynamic>>[...messages, assistantMsg];

    if (toolCalls.isNotEmpty) {
      return ToolCallResponse(
        content: textBuf.isEmpty ? null : textBuf.toString(),
        toolCalls: toolCalls,
        allMessages: allMsgs,
        usage: parsedUsage,
        reasoningContent: reasoningText,
      );
    }
    final content = textBuf.toString();
    if (content.isNotEmpty) {
      return ToolCallResponse(
        content: content,
        allMessages: allMsgs,
        usage: parsedUsage,
        reasoningContent: reasoningText,
      );
    }
    throw Exception('Anthropic 流式返回空内容');
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
    final hasSystemPrompt =
        messages.isNotEmpty && messages.first['role'] == 'system';
    if (!hasSystemPrompt && systemPrompt.isNotEmpty) {
      allMessages.add({'role': 'system', 'content': systemPrompt});
    }
    // 归一化历史 content 为字符串（兼容 Anthropic 产生的 blocks 数组）
    for (final m in messages) {
      final role = m['role']?.toString();
      if (role == 'system') {
        // 剥离 is_summary 内部标记，避免未知字段被严格校验的服务端拒绝
        allMessages.add(
          Map<String, dynamic>.from(m)..remove('is_summary'),
        );
        continue;
      }
      final normalized = Map<String, dynamic>.from(m);
      final text = _contentToText(m['content']);
      normalized['content'] = role == 'assistant'
          ? AiMessageCleaner.cleanForModel(text)
          : text;
      allMessages.add(normalized);
    }

    final body = <String, dynamic>{
      'model': p.model,
      'messages': allMessages,
      'temperature': temperature,
      'stream': false,
    };

    if (p.thinkingEnabled) {
      if (VolcengineAdapter.isVolcengineArk(p.baseUrl)) {
        // 火山方舟不支持 reasoning_effort 参数
      } else {
        body['reasoning_effort'] = p.reasoningEffort;
      }
    }

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }

    final isVolcengine = VolcengineAdapter.isVolcengineArk(p.baseUrl);
    final finalBody = isVolcengine
        ? VolcengineAdapter.transformRequest(
            originBody: body,
            toolRound: toolRound,
          )
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
      throw Exception(
        'AI 返回格式异常: ${text.length > 300 ? text.substring(0, 300) : text}',
      );
    }

    // 检查是否有 tool_calls
    final toolCallsRaw = message['tool_calls'];
    final reasoning =
        message['reasoning_content']?.toString() ??
        message['reasoning']?.toString();
    if (toolCallsRaw is List && toolCallsRaw.isNotEmpty) {
      final toolCalls = toolCallsRaw
          .whereType<Map>()
          .map(
            (tc) => ToolCallRequest.fromOpenAi(Map<String, dynamic>.from(tc)),
          )
          .toList();

      // 将 assistant 消息（含 tool_calls）加入历史
      allMessages.add(Map<String, dynamic>.from(message));

      return ToolCallResponse(
        content: message['content']?.toString(),
        toolCalls: toolCalls,
        allMessages: allMessages,
        usage: usage,
        reasoningContent: reasoning,
      );
    }

    // 没有工具调用，返回纯文本
    final content = message['content']?.toString();
    if (content != null && content.isNotEmpty) {
      return ToolCallResponse(
        content: content,
        allMessages: allMessages,
        usage: usage,
        reasoningContent: reasoning,
      );
    }

    // 如果 content 为空且没有 tool_calls，可能是结束了
    final finishReason = choice['finish_reason']?.toString();
    if (finishReason == 'stop') {
      return ToolCallResponse(
        content: '',
        allMessages: allMessages,
        usage: usage,
        reasoningContent: reasoning,
      );
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

  Future<String> rewriteSelection(
    AppSettings s,
    String selection,
    String instruction,
  ) => complete(
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
      systemPrompt: AiSessionManager.migrateFrontMatterPrompt(
        sourceFramework,
        targetFramework,
      ),
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
  final Map<String, dynamic>?
  usage; // token 用量（inputTokens/outputTokens/cacheReadTokens...）
  final String? reasoningContent; // 推理过程文本（thinking/reasoning_content）

  const ToolCallResponse({
    this.content,
    this.toolCalls,
    this.allMessages = const [],
    this.usage,
    this.reasoningContent,
  });

  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;
}

/// SSE 流式中 tool_call 增量累积器（按 index 区分并行调用）
class _StreamToolCallAcc {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
