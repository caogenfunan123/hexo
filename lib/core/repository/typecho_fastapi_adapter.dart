import 'dart:convert';
import 'dart:io';

import '../../models/app_settings.dart';
import '../../models/blog_post.dart';
import '../../models/blog_site_config.dart';
import '../../services/html_to_markdown.dart';
import 'blog_repository.dart';
import 'js_challenge_guard.dart';

/// TypechoFastApi 插件适配器
///
/// 适配 [TypechoFastApi](https://github.com/s-Ruthless/TypechoFastApi) 插件
///
/// 协议要点：
/// - 端点：`/api/v1`（伪静态）或 `/index.php/api/v1`（未开启地址重写）
/// - 鉴权：GET 参数 `apiKey` 或请求头 `api_key`
/// - 请求：RESTful 风格
/// - 响应：`{ code: 200, message: 'success', data: {...} }`
///
/// 注意：TypechoFastApi 只提供只读接口，不支持文章发布/更新/删除
class TypechoFastApiAdapter implements BlogRepository {
  final BlogSiteConfig _config;
  final AppSettings _settings;
  HttpClient? _client;
  JsChallengeHttp? _challengeHttp;

  /// 常见的 TypechoFastApi 插件端点路径
  static const _commonEndpoints = [
    '/api/v1',
    '/index.php/api/v1',
  ];

  TypechoFastApiAdapter(this._config, this._settings);

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

  /// 获取 API 端点路径
  String get _endpoint {
    final configured = _config.typechoApiEndpoint;
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    return '/api/v1';
  }

  /// 构建 TypechoFastApi 请求 URL
  /// 所有请求都携带 apiKey
  Uri _apiUri(String path, {String? ep, Map<String, String>? query}) {
    final params = <String, String>{
      'apiKey': _config.typechoToken ?? '',
      ...?query,
    };
    return Uri.parse('$_baseUrl${ep ?? _endpoint}$path')
        .replace(queryParameters: params);
  }

  /// 公共请求头（TypechoFastApi 支持 api_key 请求头鉴权）
  Map<String, String> _commonHeaders({bool json = false}) => {
        'Accept': 'application/json',
        'User-Agent': 'HexoBlogManager/1.0',
        if (json) 'Content-Type': 'application/json',
        if ((_config.typechoToken ?? '').isNotEmpty)
          'api_key': _config.typechoToken!,
      };

  /// 尝试解析 JSON，失败返回 null
  dynamic _tryDecode(String text) {
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// 解包 TypechoFastApi 统一响应
  /// 成功返回 data 字段；失败抛出 [BlogRepositoryException]
  dynamic _unwrap(dynamic decoded, String operation) {
    if (decoded is Map && decoded['code'] == 200) {
      return decoded['data'];
    }
    if (decoded is Map && decoded['code'] == 401) {
      throw BlogRepositoryException(
        401,
        'TypechoFastApi 认证失败：API 密钥错误',
        jsonEncode(decoded),
      );
    }
    if (decoded is Map && decoded['code'] != null) {
      final message = decoded['message']?.toString() ?? '未知错误';
      final code = (decoded['code'] as num?)?.toInt() ?? 500;
      throw BlogRepositoryException(
        code,
        'TypechoFastApi 错误（$operation）：$message',
        jsonEncode(decoded),
      );
    }
    throw BlogRepositoryException(
      500,
      'Typecho 返回了无法识别的响应（operation=$operation）。\n'
      '请确认已安装 TypechoFastApi 插件并正确设置密钥。',
      decoded is String ? decoded : jsonEncode(decoded),
    );
  }

  /// 发送 HTTP 请求
  Future<dynamic> _request(
    String method,
    String path, {
    String? ep,
    Map<String, String>? query,
    Map<String, String>? form,
  }) async {
    final uri = _apiUri(path, ep: ep, query: query);
    final headers = _commonHeaders();
    String? body;
    if (form != null) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      body = Uri(queryParameters: form).query;
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
        '请确认 API 端点路径正确（当前：${ep ?? _endpoint}）',
        resp.text,
      );
    }
    return _unwrap(decoded, '$method $path');
  }

  /// 自动探测可用端点
  Future<String?> _detectEndpoint() async {
    for (final ep in _commonEndpoints) {
      try {
        final data = await _request('GET', '/site/stats', ep: ep);
        if (data is Map) return ep;
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<ConnectionResult> testConnection() async {
    try {
      // 如果没有指定端点，先自动探测
      String? ep = _config.typechoApiEndpoint;
      if (ep == null || ep.isEmpty) {
        ep = await _detectEndpoint();
        if (ep == null) {
          return ConnectionResult.fail(
            '未找到 TypechoFastApi 插件端点。\n'
            '请确认已安装并激活 TypechoFastApi 插件，\n'
            '并正确设置 API 密钥。',
            detail: '尝试过的端点：${_commonEndpoints.join(', ')}',
          );
        }
      }

      final data = await _request('GET', '/site/stats', ep: ep);
      final postsCount = data is Map && data['posts'] is Map
          ? (data['posts']['total'] ?? 0).toString()
          : '?';
      return ConnectionResult.ok('连接成功！站点共有 $postsCount 篇文章（API：$ep）');
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
    final data = await _request('GET', '/posts', query: {
      'page': page.toString(),
      'pageSize': perPage.toString(),
    });

    List list;
    if (data is Map && data['list'] is List) {
      list = data['list'];
    } else if (data is List) {
      list = data;
    } else {
      list = [];
    }

    return list.map((item) {
      return _typechoPostToBlogPost(Map<String, dynamic>.from(item as Map));
    }).toList();
  }

  @override
  Future<BlogPost?> getPostById(int id) async {
    final data = await _request('GET', '/posts/$id');
    if (data is Map) {
      return _typechoPostToBlogPost(Map<String, dynamic>.from(data));
    }
    return null;
  }

  @override
  Future<BlogPost> createPost(BlogPost post) async {
    throw BlogRepositoryException(
      400,
      'TypechoFastApi 插件只提供只读接口，不支持发布文章。\n'
      '如需发布文章，请使用 SecureApi 插件（增强版）。',
      '',
    );
  }

  @override
  Future<BlogPost> updatePost(BlogPost post) async {
    throw BlogRepositoryException(
      400,
      'TypechoFastApi 插件只提供只读接口，不支持更新文章。\n'
      '如需更新文章，请使用 SecureApi 插件（增强版）。',
      '',
    );
  }

  @override
  Future<bool> deletePost(int postId) async {
    throw BlogRepositoryException(
      400,
      'TypechoFastApi 插件只提供只读接口，不支持删除文章。\n'
      '如需删除文章，请使用 SecureApi 插件（增强版）。',
      '',
    );
  }

  @override
  Future<MediaUploadResult> uploadMedia(String filePath) async {
    throw BlogRepositoryException(
      400,
      'TypechoFastApi 插件只提供只读接口，不支持媒体上传。\n'
      '如需上传媒体，请使用 SecureApi 插件（增强版）。',
      '',
    );
  }

  /// TypechoFastApi 文章 → 统一 BlogPost 模型
  BlogPost _typechoPostToBlogPost(Map<String, dynamic> data) {
    final title = data['title']?.toString() ?? '';
    final contentHtml = data['content']?.toString() ?? data['summary']?.toString() ?? '';
    final idStr = data['id']?.toString() ?? '0';
    final id = int.tryParse(idStr) ?? 0;

    return BlogPost(
      id: id > 0 ? id : null,
      title: title,
      contentMd: HtmlToMarkdown.convert(contentHtml),
      contentHtml: contentHtml,
      date: DateTime.tryParse(data['created']?.toString() ?? '') ?? DateTime.now(),
      modifiedDate: DateTime.tryParse(
            data['modified']?.toString() ?? '',
          ) ??
          DateTime.now(),
      status: 'publish', // TypechoFastApi 只返回已发布的文章
      slug: data['slug']?.toString(),
      tags: [], // TypechoFastApi 不返回标签信息
      categories: [], // TypechoFastApi 不返回分类信息
      siteId: config.id,
      siteType: BlogType.typecho,
      link: '$_baseUrl/archives/${id > 0 ? id : ''}.html',
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