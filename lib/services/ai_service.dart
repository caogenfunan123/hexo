import 'dart:convert';
import 'dart:io';

import '../models/ai_profile.dart';
import '../models/app_settings.dart';

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
    final uri = Uri.tryParse(base);
    if (uri != null && uri.pathSegments.contains('v1')) {
      return base;
    }
    if (base.endsWith('/v1')) return base;
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
    final client = HttpClient();
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
  Future<List<String>> listModels(AppSettings settings, {AiProfile? profile}) async {
    final p = resolveProfile(settings, override: profile);
    if (p.apiKey.isEmpty) {
      throw Exception('请先填写 API Key');
    }
    if (p.baseUrl.trim().isEmpty) {
      throw Exception('请先填写 Base URL');
    }
    final url = _modelsUrl(p);
    try {
      final text = await _http(
        method: 'GET',
        url: url,
        apiKey: p.apiKey,
        useBearer: p.useBearer,
      );
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
        throw Exception('未解析到模型列表，响应: ${text.length > 200 ? text.substring(0, 200) : text}');
      }
      return list;
    } catch (e) {
      throw Exception('获取模型失败（$url）: $e');
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

  Future<String> polish(AppSettings s, String content) => complete(
        settings: s,
        systemPrompt:
            '你是中文 Markdown 写作助手。润色用户文章，保持原意与 Markdown 结构（含代码块、列表、标题），只输出完整正文，不要解释。',
        userPrompt: content,
      );

  Future<String> continueWrite(AppSettings s, String content) => complete(
        settings: s,
        systemPrompt:
            '你是中文 Markdown 写作助手。根据已有内容自然续写，保持 Markdown 格式，只输出续写部分。',
        userPrompt: content,
      );

  Future<String> summarize(AppSettings s, String content) => complete(
        settings: s,
        systemPrompt: '用中文为文章生成 2-4 句摘要，以及 3-6 个标签（#标签 形式）。',
        userPrompt: content,
      );

  Future<String> generateOutline(AppSettings s, String topic) => complete(
        settings: s,
        systemPrompt: '根据主题生成 Hexo 博客 Markdown 大纲，含标题建议、小节与代码块占位说明。',
        userPrompt: topic,
      );

  Future<String> generateCode(AppSettings s, String prompt) => complete(
        settings: s,
        systemPrompt:
            '你是编程助手。根据用户需求输出可直接粘贴进 Markdown 的 fenced code block（带语言标记），必要时附简短说明。',
        userPrompt: prompt,
      );

  Future<String> rewriteSelection(AppSettings s, String selection, String instruction) =>
      complete(
        settings: s,
        systemPrompt: '按用户指令改写给定 Markdown 片段，只输出改写后的文本。',
        userPrompt: '指令: $instruction\n\n原文:\n$selection',
      );
}
