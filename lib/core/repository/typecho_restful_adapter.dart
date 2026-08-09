import 'dart:convert';
import 'dart:io';

import '../../models/app_settings.dart';
import '../../models/blog_post.dart';
import '../../models/blog_site_config.dart';
import '../../services/html_to_markdown.dart';
import 'blog_repository.dart';
import 'js_challenge_guard.dart';

/// Typecho Restful 插件适配器
///
/// 适配 [moefront/typecho-plugin-Restful](https://github.com/moefront/typecho-plugin-Restful) 插件
/// 支持 RESTful API 风格的完整读写操作。
///
/// 协议要点：
/// - 端点：`/api/posts`（文章）、`/api/media`（媒体）
/// - 方法：GET/POST/PUT/DELETE
/// - 鉴权：请求头 `Authorization: Bearer <token>`
/// - 响应：JSON 格式
class TypechoRestfulAdapter implements BlogRepository {
  final BlogSiteConfig _config;
  final AppSettings _settings;
  HttpClient? _client;
  JsChallengeHttp? _challengeHttp;

  TypechoRestfulAdapter(this._config, this._settings);

  @override
  BlogSiteConfig get config => _config;

  HttpClient get _http {
    _client ??= HttpClient()
      ..connectionTimeout = Duration(seconds: _settings.httpTimeoutSeconds)
      ..badCertificateCallback = (_settings.allowInsecureHttps || _config.ignoreSsl)
          ? (cert, host, port) => true
          : null;
    return _client!;
  }

  /// 带 slowAES 反爬挑战处理的请求客户端
  JsChallengeHttp get _js {
    _challengeHttp ??= JsChallengeHttp(_http);
    return _challengeHttp!;
  }

  /// 站点根地址（去掉末尾斜杠）
  String get _baseUrl {
    final url = _config.siteUrl;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// 构建 RESTful API 请求 URL
  Uri _restfulUri(String endpoint) {
    return Uri.parse('$_baseUrl$endpoint');
  }

  /// 公共请求头（RESTful API 使用 Bearer Token 认证）
  Map<String, String> _commonHeaders({bool json = false}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'HexoBlogManager/1.0',
    };

    if (json) {
      headers['Content-Type'] = 'application/json';
    }

    // 添加 Bearer Token 认证
    if ((_config.typechoToken ?? '').isNotEmpty) {
      headers['Authorization'] = 'Bearer ${_config.typechoToken}';
    }

    return headers;
  }

  /// 尝试解析 JSON，失败返回 null
  dynamic _tryDecode(String text) {
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// 解包 RESTful API 响应
  /// 成功返回 data 字段；失败抛出 [BlogRepositoryException]
  dynamic _unwrap(dynamic decoded, String endpoint) {
    if (decoded is Map && decoded['success'] == true) {
      return decoded['data'];
    }
    if (decoded is Map && decoded['success'] == false) {
      final err = decoded['error'];
      String message = '未知错误';
      int code = 500;
      if (err is Map) {
        message = err['message']?.toString() ?? message;
        code = (err['code'] as num?)?.toInt() ?? code;
      } else if (err != null) {
        message = err.toString();
      }
      throw BlogRepositoryException(code, 'Typecho Restful API 错误：$message', jsonEncode(decoded));
    }
    throw BlogRepositoryException(
      500,
      'Typecho 返回了无法识别的响应（endpoint=$endpoint）。\n'
      '请确认已安装 Restful 插件并开启 API。',
      decoded is String ? decoded : jsonEncode(decoded),
    );
  }

  /// 发送 HTTP 请求
  /// [jsonBody] 非空时以 application/json 发送
  Future<dynamic> _request(
    String method,
    String endpoint, {
    Object? jsonBody,
    Map<String, String>? queryParams,
  }) async {
    var uri = _restfulUri(endpoint);
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }
    final headers = _commonHeaders(json: jsonBody != null);
    String? body;

    if (jsonBody != null) {
      body = jsonEncode(jsonBody);
    }

    final resp = await _js.send(
      method,
      uri,
      headers: headers,
      body: body,
    );

    final decoded = _tryDecode(resp.text);
    if (decoded == null) {
      if (resp.statusCode >= 200 && resp.statusCode < 300) return {};
      throw BlogRepositoryException(
        resp.statusCode,
        'Typecho 响应不是有效 JSON（HTTP ${resp.statusCode}）。\n'
        '请确认 API 端点路径正确（当前：$endpoint）',
        resp.text,
      );
    }
    return _unwrap(decoded, endpoint);
  }

  @override
  Future<ConnectionResult> testConnection() async {
    try {
      final data = await _request('GET', '/api/posts', queryParams: {
        'limit': '1',
      });
      
      if (data is Map && data['total'] != null) {
        return ConnectionResult.ok('连接成功！Restful API 可用');
      }
      
      return ConnectionResult.fail(
        '连接测试失败：无法获取文章列表',
        detail: '请确认 Restful 插件已正确安装并激活',
      );
    } on BlogRepositoryException catch (e) {
      return ConnectionResult.fail(e.message, detail: e.body);
    } on SocketException catch (e) {
      return ConnectionResult.fail(
        '网络无法访问站点：${_config.siteUrl}',
        detail: e.message,
      );
    } on HandshakeException catch (e) {
      return ConnectionResult.fail(
        'SSL 证书验证失败。如果站点使用自签名证书，请勾选「忽略 SSL 证书错误」。',
        detail: e.message,
      );
    } catch (e) {
      return ConnectionResult.fail(
        '连接测试失败',
        detail: e.toString(),
      );
    }
  }

  @override
  Future<List<BlogPost>> getPosts({int page = 1, int perPage = 10}) async {
    final data = await _request('GET', '/api/posts', queryParams: {
      'page': page.toString(),
      'limit': perPage.toString(),
    });

    List list;
    if (data is Map && data['posts'] != null) {
      list = data['posts'] as List;
    } else if (data is List) {
      list = data;
    } else {
      list = [];
    }

    return list.map((item) {
      return _restfulPostToBlogPost(Map<String, dynamic>.from(item));
    }).toList();
  }

  @override
  Future<BlogPost?> getPostById(int id) async {
    final data = await _request('GET', '/api/posts/$id');
    if (data is Map) {
      return _restfulPostToBlogPost(Map<String, dynamic>.from(data));
    }
    return null;
  }

  @override
  Future<BlogPost> createPost(BlogPost post) async {
    final jsonBody = {
      'title': post.title,
      'content': post.contentMd, // Restful API 可能使用 content 而不是 text
      'status': post.status == 'publish' ? 'publish' : 'draft',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
      'tags': post.tags,
      'categories': post.categories,
    };

    final data = await _request('POST', '/api/posts', jsonBody: jsonBody);
    if (data is! Map) {
      throw BlogRepositoryException(500, 'Typecho 创建文章失败：未返回数据', '');
    }
    return _restfulPostToBlogPost(Map<String, dynamic>.from(data));
  }

  @override
  Future<BlogPost> updatePost(BlogPost post) async {
    if (post.id == null) {
      throw BlogRepositoryException(400, '更新文章需要远程 ID，请先发布文章。', '');
    }

    final jsonBody = {
      'title': post.title,
      'content': post.contentMd,
      'status': post.status == 'publish' ? 'publish' : 'draft',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
      'tags': post.tags,
      'categories': post.categories,
    };

    final data = await _request('PUT', '/api/posts/${post.id}', jsonBody: jsonBody);
    if (data is! Map) {
      throw BlogRepositoryException(500, 'Typecho 更新文章失败：未返回数据', '');
    }
    return _restfulPostToBlogPost(Map<String, dynamic>.from(data));
  }

  @override
  Future<bool> deletePost(int postId) async {
    await _request('DELETE', '/api/posts/$postId');
    return true;
  }

  @override
  Future<MediaUploadResult> uploadMedia(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return MediaUploadResult.failure('文件不存在: $filePath');
      }

      final bytes = await file.readAsBytes();
      final boundary = '----HexoBoundary${DateTime.now().millisecondsSinceEpoch}';

      final header = utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="${filePath.split('/').last}"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n',
      );
      final footer = utf8.encode('\r\n--$boundary--\r\n');
      final bodyBytes = <int>[...header, ...bytes, ...footer];

      final uri = _restfulUri('/api/media');
      final resp = await _js.send(
        'POST',
        uri,
        headers: {
          ..._commonHeaders(),
          'Content-Type': 'multipart/form-data; boundary=$boundary',
        },
        rawBody: bodyBytes,
        contentLength: bodyBytes.length,
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = _tryDecode(resp.text);
        if (decoded != null) {
          final data = _unwrap(decoded, 'uploadMedia');
          if (data is Map) {
            final url = (data['url'] ?? data['path'] ?? '').toString();
            if (url.isNotEmpty) {
              return MediaUploadResult.success(0, url);
            }
          }
        }
      }

      return MediaUploadResult.failure(
        '媒体上传失败。\n'
        '请确认 Restful 插件支持媒体上传功能。\n'
        'HTTP ${resp.statusCode}',
      );
    } catch (e) {
      return MediaUploadResult.failure('上传失败: $e');
    }
  }

  /// Restful API 文章 → 统一 BlogPost 模型
  BlogPost _restfulPostToBlogPost(Map<String, dynamic> data) {
    final title = data['title']?.toString() ?? '';
    final contentHtml = data['content']?.toString() ?? data['text']?.toString() ?? '';
    final idStr = data['id']?.toString() ?? data['cid']?.toString() ?? '0';
    final id = int.tryParse(idStr) ?? 0;

    final tags = <String>[];
    final tagsRaw = data['tags'];
    if (tagsRaw is String) {
      tags.addAll(tagsRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    } else if (tagsRaw is List) {
      tags.addAll(tagsRaw
          .map((e) => e is Map ? (e['name']?.toString() ?? '') : e.toString())
          .where((e) => e.isNotEmpty));
    }

    final categories = <String>[];
    final catsRaw = data['categories'];
    if (catsRaw is String) {
      categories.addAll(catsRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    } else if (catsRaw is List) {
      categories.addAll(catsRaw
          .map((e) => e is Map ? (e['name']?.toString() ?? '') : e.toString())
          .where((e) => e.isNotEmpty));
    }

    return BlogPost(
      id: id > 0 ? id : null,
      title: title,
      contentMd: HtmlToMarkdown.convert(contentHtml),
      contentHtml: contentHtml,
      date: DateTime.tryParse(data['created']?.toString() ?? '') ?? DateTime.now(),
      modifiedDate: DateTime.tryParse(
            data['updated']?.toString() ?? data['modified']?.toString() ?? '',
          ) ??
          DateTime.now(),
      status: data['status']?.toString() == 'publish' ? 'publish' : 'draft',
      slug: data['slug']?.toString(),
      tags: tags,
      categories: categories,
      siteId: config.id,
      siteType: BlogType.typecho,
      link: data['url']?.toString() ?? data['permalink']?.toString(),
    );
  }

  @override
  void dispose() {
    _client?.close(force: true);
    _client = null;
    _challengeHttp = null;
  }

  /// 静态博客专用方法：Typecho 为动态 CMS，直接返回当前文章内容
  @override
  Future<BlogPost> getPostContent(String postId) async {
    final id = int.tryParse(postId);
    if (id == null) throw Exception('无效的文章 ID: $postId');
    final post = await getPostById(id);
    if (post == null) throw Exception('文章不存在: $postId');
    return post;
  }

  /// 是否为静态博客适配器
  @override
  bool get isStatic => false;
}