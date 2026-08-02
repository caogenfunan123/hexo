import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/ai_profile.dart';
import '../models/app_settings.dart';

/// SSE 流式块
class StreamChunk {
  final String content;
  final bool isDone;
  final String? finishReason;

  const StreamChunk({required this.content, this.isDone = false, this.finishReason});
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

  /// 流式请求：返回 SSE 文本块流，支持取消
  Stream<StreamChunk> completeStream({
    required AppSettings settings,
    required String systemPrompt,
    required String userPrompt,
    AiProfile? profile,
    double temperature = 0.7,
    List<Map<String, String>>? messages,
  }) async* {
    final p = resolveProfile(settings, override: profile);
    if (p.apiKey.isEmpty) {
      throw Exception('请先在设置中配置 AI 中转站并填写 API Key');
    }
    if (p.model.isEmpty) {
      throw Exception('请先选择模型');
    }

    final url = _chatUrl(p);
    final msgs = messages ??
        [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ];

    final body = {
      'model': p.model,
      'messages': msgs,
      'temperature': temperature,
      'stream': true,
    };

    final client = HttpClient();
    try {
      final uri = Uri.parse(url);
      final req = await client.openUrl('POST', uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'text/event-stream');
      if (p.apiKey.isNotEmpty) {
        if (p.useBearer) {
          req.headers.set('Authorization', 'Bearer ${p.apiKey}');
        } else {
          req.headers.set('Authorization', p.apiKey);
          req.headers.set('api-key', p.apiKey);
          req.headers.set('x-api-key', p.apiKey);
        }
      }
      final bytes = utf8.encode(jsonEncode(body));
      req.contentLength = bytes.length;
      req.add(bytes);

      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final errorText = await res.transform(utf8.decoder).join();
        throw Exception('HTTP ${res.statusCode}: $errorText');
      }

      final lineStream = res
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') {
            yield const StreamChunk(content: '', isDone: true);
            break;
          }
          try {
            final json = jsonDecode(data);
            if (json is Map && json['choices'] is List) {
              final choices = json['choices'] as List;
              if (choices.isNotEmpty) {
                final choice = choices.first;
                if (choice is Map) {
                  final delta = choice['delta'];
                  if (delta is Map && delta['content'] != null) {
                    yield StreamChunk(content: delta['content'].toString());
                  }
                  // 检查是否结束
                  final finish = choice['finish_reason'];
                  if (finish != null && finish.toString().isNotEmpty) {
                    yield StreamChunk(
                      content: '',
                      isDone: true,
                      finishReason: finish.toString(),
                    );
                  }
                }
              }
            }
          } catch (_) {
            // 跳过无法解析的行
          }
        }
      }
    } finally {
      client.close(force: true);
    }
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

  /// AI 生成 FrontMatter 模板
  Future<String> generateTemplate({
    required AppSettings settings,
    required String userPrompt,
    AiProfile? profile,
  }) async {
    return complete(
      settings: settings,
      profile: profile,
      systemPrompt: '''你是静态博客 FrontMatter 模板生成器。根据用户描述生成 YAML FrontMatter 模板（含 --- 包裹）。

规则：
1. 支持变量：{{title}} {{date}} {{tags}} {{categories}} {{slug}} {{draft}}
2. 根据框架自动适配字段：
   - Hexo: title, date, tags, categories, cover, comments
   - Hugo: title, date, draft, tags, categories, slug, type
   - Jekyll: layout, title, date, categories, tags, permalink
   - Astro: title, pubDate, draft, tags, layout
   - VuePress: title, date, tags, sidebar, navbar
   - Gatsby: title, date, slug, tags, featuredImage
   - Next.js: title, date, tags, excerpt, author
   - Pelican: Title, Date, Tags, Category, Slug, Summary
   - 11ty: title, date, tags, layout, eleventyExcludeFromCollections
3. 只输出模板代码，不要解释。''',
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
      systemPrompt: '''你是静态博客 FrontMatter 迁移工具。将输入的文章 FrontMatter 从 $sourceFramework 格式转换为 $targetFramework 格式。

转换规则：
- Hexo → Hugo: 添加 draft: true, title 加引号
- Hexo → Jekyll: 添加 layout: post, 改为 permalink 格式
- Hexo → Astro: date 改为 pubDate, 添加 draft
- Jekyll → Hexo: 移除 layout/permalink, 改为 date/tags
- Hugo → Hexo: 移除 draft, title 去引号
- 任意 → 任意: 保留所有能对应的字段，补全缺失的必需字段

只输出转换后的 FrontMatter（含 ---），不要解释。''',
      userPrompt: '请转换以下 FrontMatter：\n\n$frontMatter',
    );
  }
}
