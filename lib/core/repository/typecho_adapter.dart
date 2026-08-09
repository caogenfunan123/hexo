import 'dart:convert';
import 'dart:io';

import '../../models/app_settings.dart';
import '../../models/blog_post.dart';
import '../../models/blog_site_config.dart';
import '../../services/html_to_markdown.dart';
import 'blog_repository.dart';
import 'js_challenge_guard.dart';

/// Typecho SecureApi 插件适配器
///
/// 适配 [SecureApi](https://gitee.com/nice_ch/typecho-plugin) 插件
/// （含增强版 createPost/updatePost/deletePost/uploadMedia 写接口）。
///
/// 协议要点：
/// - 端点：`/index.php/api`（未开启地址重写）或 `/api`（伪静态）
/// - 鉴权：GET 参数 `token` 或请求头 `X-API-Key`
/// - 读取：GET `?action=xxx`
/// - 写入：POST（表单参数）+ `?action=xxx`
/// - 响应：`{ success: true, data: {...} }` / `{ success: false, error: {...} }`
class TypechoAdapter implements BlogRepository {
  final BlogSiteConfig _config;
  final AppSettings _settings;
  HttpClient? _client;
  JsChallengeHttp? _challengeHttp;

  /// 常见的 SecureApi 插件端点路径
  static const _commonEndpoints = [
    '/index.php/api',
    '/api',
  ];

  TypechoAdapter(this._config, this._settings);

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
    return '/index.php/api';
  }

  /// 构建 SecureApi 请求 URL
  /// 所有请求都携带 action 与 token
  Uri _apiUri(String action, {String? ep, Map<String, String>? query}) {
    final params = <String, String>{
      'action': action,
      'token': _config.typechoToken ?? '',
      ...?query,
    };
    return Uri.parse('$_baseUrl${ep ?? _endpoint}')
        .replace(queryParameters: params);
  }

  /// 公共请求头（SecureApi 支持 X-API-Key 请求头鉴权，作为 token 的补充）
  Map<String, String> _commonHeaders({bool json = false}) => {
        'Accept': 'application/json',
        'User-Agent': 'HexoBlogManager/1.0',
        if (json) 'Content-Type': 'application/json',
        if ((_config.typechoToken ?? '').isNotEmpty)
          'X-API-Key': _config.typechoToken!,
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

  /// 解包 SecureApi 统一响应
  /// 成功返回 data 字段；失败抛出 [BlogRepositoryException]
  dynamic _unwrap(dynamic decoded, String action) {
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
      throw BlogRepositoryException(code, 'Typecho SecureApi 错误：$message', jsonEncode(decoded));
    }
    throw BlogRepositoryException(
      500,
      'Typecho 返回了无法识别的响应（action=$action）。\n'
      '请确认已安装 SecureApi 插件并开启 API。',
      decoded is String ? decoded : jsonEncode(decoded),
    );
  }

  /// 发送 HTTP 请求
  /// [form] 非空时以 application/x-www-form-urlencoded 发送 POST
  Future<dynamic> _request(
    String method,
    String action, {
    String? ep,
    Map<String, String>? query,
    Map<String, String>? form,
  }) async {
    final uri = _apiUri(action, ep: ep, query: query);
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
    return _unwrap(decoded, action);
  }

  /// 自动探测可用端点
  Future<String?> _detectEndpoint() async {
    for (final ep in _commonEndpoints) {
      try {
        final data = await _request('GET', 'getWebInfo', ep: ep);
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
            '未找到 SecureApi 插件端点。\n'
            '请确认已安装并激活 SecureApi 插件（建议使用增强版），\n'
            '并开启「API 开关」、正确设置密钥。',
            detail: '尝试过的端点：${_commonEndpoints.join(', ')}',
          );
        }
      }

      final data = await _request('GET', 'getWebInfo', ep: ep);
      final siteTitle = data is Map ? (data['title'] ?? '').toString() : '';
      return ConnectionResult.ok('连接成功！站点：$siteTitle（API：$ep）');
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
    final data = await _request('GET', 'getPosts', query: {
      'page': page.toString(),
      'limit': perPage.toString(),
    });

    List list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = (data['data'] ?? data['posts'] ?? data['items'] ?? []) as List;
    } else {
      list = [];
    }

    return list.map((item) {
      return _typechoPostToBlogPost(Map<String, dynamic>.from(item as Map));
    }).toList();
  }

  @override
  Future<BlogPost?> getPostById(int id) async {
    final data = await _request('GET', 'getArticleContent', query: {
      'cid': id.toString(),
    });
    if (data is Map) {
      return _typechoPostToBlogPost(Map<String, dynamic>.from(data));
    }
    return null;
  }

  @override
  Future<BlogPost> createPost(BlogPost post) async {
    final form = <String, String>{
      'title': post.title,
      'text': post.contentMd,
      'status': post.status == 'publish' ? 'publish' : 'draft',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug!,
      'tags': post.tags.join(','),
      'category': post.categories.join(','),
    };

    final data = await _request('POST', 'createPost', form: form);
    if (data is! Map) {
      throw BlogRepositoryException(500, 'Typecho 创建文章失败：未返回数据', '');
    }
    return _typechoPostToBlogPost(Map<String, dynamic>.from(data));
  }

  @override
  Future<BlogPost> updatePost(BlogPost post) async {
    if (post.id == null) {
      throw BlogRepositoryException(400, '更新文章需要远程 ID，请先发布文章。', '');
    }

    final form = <String, String>{
      'cid': '${post.id}',
      'status': post.status == 'publish' ? 'publish' : 'draft',
      if (post.title.isNotEmpty) 'title': post.title,
      if (post.contentMd.isNotEmpty) 'text': post.contentMd,
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug!,
      'tags': post.tags.join(','),
      'category': post.categories.join(','),
    };

    final data = await _request('POST', 'updatePost', form: form);
    if (data is! Map) {
      throw BlogRepositoryException(500, 'Typecho 更新文章失败：未返回数据', '');
    }
    return _typechoPostToBlogPost(Map<String, dynamic>.from(data));
  }

  @override
  Future<bool> deletePost(int postId) async {
    await _request('POST', 'deletePost', form: {'cid': '$postId'});
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

      final uri = _apiUri('uploadMedia');
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
            final url = (data['url'] ?? '').toString();
            if (url.isNotEmpty) {
              return MediaUploadResult.success(0, url);
            }
          }
        }
      }

      return MediaUploadResult.failure(
        '媒体上传失败。\n'
        '请确认 SecureApi 插件为增强版（支持 uploadMedia）。\n'
        'HTTP ${resp.statusCode}',
      );
    } catch (e) {
      return MediaUploadResult.failure('上传失败: $e');
    }
  }

  /// SecureApi 文章 → 统一 BlogPost 模型
  BlogPost _typechoPostToBlogPost(Map<String, dynamic> data) {
    final title = data['title']?.toString() ?? '';
    final contentHtml = data['content']?.toString() ?? data['text']?.toString() ?? '';
    final idStr = data['cid']?.toString() ?? data['id']?.toString() ?? '0';
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
      link: data['permalink']?.toString() ?? data['url']?.toString(),
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
