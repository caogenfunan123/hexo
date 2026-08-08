import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../models/app_settings.dart';
import '../../models/blog_post.dart';
import '../../models/blog_site_config.dart';
import '../../services/html_to_markdown.dart';
import 'blog_repository.dart';
import 'js_challenge_guard.dart';

/// Ghost Admin API 适配器
///
/// 鉴权：Admin API Key → JWT Token
///   - 用户操作：Ghost后台 → Settings → Integrations → Add custom integration
///   - Admin API Key 格式为 "id:secret"
///   - 客户端用 id:secret 签发 HS256 JWT，请求头：Authorization: Ghost {jwt}
///
/// 端点：/ghost/api/admin/posts（CRUD）
class GhostAdapter implements BlogRepository {
  final BlogSiteConfig _config;
  final AppSettings _settings;
  HttpClient? _client;
  JsChallengeHttp? _challengeHttp;
  String? _jwtToken;
  DateTime? _tokenExpiry;

  GhostAdapter(this._config, this._settings);

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

  /// 解析 Admin API Key（"id:secret" 格式）
  String get _apiKeyId {
    final parts = (_config.ghostAdminApiKey ?? ':').split(':');
    return parts[0];
  }

  String get _apiKeySecret {
    final parts = (_config.ghostAdminApiKey ?? ':').split(':');
    return parts.length > 1 ? parts[1] : '';
  }

  /// 构建 Ghost API URL
  Uri _apiUri(String path) {
    final base = _config.siteUrl.endsWith('/')
        ? _config.siteUrl.substring(0, _config.siteUrl.length - 1)
        : _config.siteUrl;
    return Uri.parse('$base/ghost/api/admin$path');
  }

  /// 获取 JWT Token（过期时自动刷新）
  Future<String> _getJwt() {
    if (_jwtToken != null && _tokenExpiry != null && _tokenExpiry!.isAfter(DateTime.now())) {
      return Future.value(_jwtToken);
    }
    return Future.value(_createJwt());
  }

  /// 签发 HS256 JWT
  ///
  /// Ghost 使用 HS256 算法，secret 为 Admin API Key 的 secret 部分
  /// 载荷包含：iat, exp, aud
  String _createJwt() {
    // JWT Header
    final header = base64UrlEncode(
      utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT', 'kid': _apiKeyId})),
    ).replaceAll('=', '');

    // JWT Payload
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payload = base64UrlEncode(
      utf8.encode(jsonEncode({
        'iat': now,
        'exp': now + 300, // 5 分钟
        'aud': '/admin/',
      })),
    ).replaceAll('=', '');

    // HMAC-SHA256 签名
    final signingInput = '$header.$payload';
    final hmac = Hmac(sha256, utf8.encode(_apiKeySecret));
    final signature = hmac.convert(utf8.encode(signingInput));
    final sig = base64UrlEncode(signature.bytes).replaceAll('=', '');

    _jwtToken = '$signingInput.$sig';
    _tokenExpiry = DateTime.now().add(const Duration(minutes: 4));
    return _jwtToken!;
  }

  /// 发送 HTTP 请求
  Future<dynamic> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _getJwt();
    final resp = await _js.send(
      method,
      uri,
      headers: _commonHeaders(token, json: body != null),
      body: body != null ? jsonEncode(body) : null,
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.text.isEmpty) return {};
      try {
        return jsonDecode(resp.text);
      } catch (_) {
        return {'raw': resp.text};
      }
    }

    _handleError(resp.statusCode, resp.text);
  }

  /// 公共请求头
  Map<String, String> _commonHeaders(String token, {bool json = false}) => {
        'Authorization': 'Ghost $token',
        'Accept-Version': 'v5.0',
        if (json) 'Content-Type': 'application/json',
        'User-Agent': 'HexoBlogManager/1.0',
      };

  Never _handleError(int statusCode, String body) {
    String message;
    switch (statusCode) {
      case 401:
        message = '鉴权失败：Admin API Key 无效或已过期。请在 Ghost 后台重新生成。';
      case 403:
        message = '权限不足：该 API Key 没有 Admin 权限。请确认使用的是 Admin API Key 而非 Content API Key。';
      case 404:
        message = 'API 不存在。请确认站点是 Ghost 3.0+，Admin API 已开启。';
      case 422:
        message = '请求数据格式错误：$body';
      case 0:
        message = '无法连接到 Ghost 站点。请检查 URL 是否正确。';
      default:
        message = 'Ghost HTTP $statusCode: 请求失败。';
    }
    throw BlogRepositoryException(statusCode, message, body);
  }

  @override
  Future<ConnectionResult> testConnection() async {
    try {
      final token = _createJwt();
      final uri = _apiUri('/site/');
      final resp = await _js.send('GET', uri, headers: _commonHeaders(token));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.text) as Map<String, dynamic>;
        final site = data['site'] as Map<String, dynamic>?;
        final title = site?['title']?.toString() ?? 'Ghost 站点';
        return ConnectionResult.ok('连接成功！站点：$title');
      }

      if (resp.statusCode == 401) {
        return ConnectionResult.fail(
          '鉴权失败：Admin API Key 无效。请确认格式为 "id:secret"。',
          detail: 'Ghost后台 → Settings → Integrations → Add custom integration 生成',
        );
      }

      return ConnectionResult.fail(
        'HTTP ${resp.statusCode}: 连接异常',
        detail: resp.text,
      );
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
    final uri = _apiUri('/posts/?limit=$perPage&page=$page&formats=mobiledoc,html&order=published_at%20desc');
    final data = await _request('GET', uri);
    final posts = data['posts'] as List? ?? [];
    return posts.map((p) => _ghostPostToBlogPost(p as Map<String, dynamic>)).toList();
  }

  @override
  Future<BlogPost?> getPostById(int id) async {
    final uri = _apiUri('/posts/$id/?formats=mobiledoc,html');
    final data = await _request('GET', uri);
    final posts = data['posts'] as List? ?? [];
    if (posts.isEmpty) return null;
    return _ghostPostToBlogPost(posts.first as Map<String, dynamic>);
  }

  @override
  Future<BlogPost> createPost(BlogPost post) async {
    // Markdown → Mobiledoc JSON
    final mobiledoc = _markdownToMobiledoc(post.contentMd);

    final body = <String, dynamic>{
      'posts': [
        {
          'title': post.title,
          'mobiledoc': jsonEncode(mobiledoc),
          'status': post.status == 'publish' ? 'published' : 'draft',
          if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
          if (post.tags.isNotEmpty)
            'tags': post.tags.map((t) => {'name': t}).toList(),
        }
      ],
    };

    final uri = _apiUri('/posts/?source=html');
    final data = await _request('POST', uri, body: body);
    final posts = data['posts'] as List? ?? [];
    if (posts.isEmpty) throw BlogRepositoryException(500, 'Ghost 创建文章失败：未返回数据', '');
    return _ghostPostToBlogPost(posts.first as Map<String, dynamic>);
  }

  @override
  Future<BlogPost> updatePost(BlogPost post) async {
    if (post.id == null) {
      throw BlogRepositoryException(400, '更新文章需要远程 ID，请先发布文章。', '');
    }

    final mobiledoc = _markdownToMobiledoc(post.contentMd);

    final body = <String, dynamic>{
      'posts': [
        {
          'title': post.title,
          'mobiledoc': jsonEncode(mobiledoc),
          'status': post.status == 'publish' ? 'published' : 'draft',
          if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
        }
      ],
    };

    final uri = _apiUri('/posts/${post.id}/?source=html');
    final data = await _request('PUT', uri, body: body);
    final posts = data['posts'] as List? ?? [];
    if (posts.isEmpty) throw BlogRepositoryException(500, 'Ghost 更新文章失败：未返回数据', '');
    return _ghostPostToBlogPost(posts.first as Map<String, dynamic>);
  }

  @override
  Future<bool> deletePost(int postId) async {
    final uri = _apiUri('/posts/$postId');
    await _request('DELETE', uri);
    return true;
  }

  @override
  Future<MediaUploadResult> uploadMedia(String filePath) async {
    try {
      final token = await _getJwt();
      final uri = _apiUri('/images/upload/');

      final file = File(filePath);
      if (!await file.exists()) {
        return MediaUploadResult.failure('文件不存在: $filePath');
      }

      final bytes = await file.readAsBytes();
      final boundary = '----FormBoundary${DateTime.now().millisecondsSinceEpoch}';

      final header = utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="${filePath.split('/').last}"\r\n'
        'Content-Type: image/${_extension(filePath)}\r\n\r\n',
      );
      final footer = utf8.encode('\r\n--$boundary--\r\n');
      final bodyBytes = <int>[...header, ...bytes, ...footer];

      final resp = await _js.send(
        'POST',
        uri,
        headers: {
          ..._commonHeaders(token),
          'Content-Type': 'multipart/form-data; boundary=$boundary',
        },
        rawBody: bodyBytes,
        contentLength: bodyBytes.length,
      );

      if (resp.statusCode == 201) {
        final data = jsonDecode(resp.text) as Map<String, dynamic>;
        final images = data['images'] as List? ?? [];
        if (images.isNotEmpty) {
          final img = images.first as Map<String, dynamic>;
          final url = img['url']?.toString() ?? '';
          return MediaUploadResult.success(0, url);
        }
      }

      return MediaUploadResult.failure('上传失败: HTTP ${resp.statusCode}');
    } catch (e) {
      return MediaUploadResult.failure('上传失败: $e');
    }
  }

  /// Ghost 文章 → 统一 BlogPost 模型
  BlogPost _ghostPostToBlogPost(Map<String, dynamic> data) {
    final tags = <String>[];
    if (data['tags'] is List) {
      for (final t in data['tags'] as List) {
        if (t is Map) tags.add(t['name']?.toString() ?? '');
      }
    }

    // 从 HTML 或 mobiledoc 中提取 Markdown 用于编辑
    String contentMd = '';
    if (data['html'] is String && (data['html'] as String).isNotEmpty) {
      contentMd = HtmlToMarkdown.convert(data['html'] as String);
    } else if (data['mobiledoc'] != null) {
      try {
        final doc = data['mobiledoc'] is String
            ? jsonDecode(data['mobiledoc'] as String)
            : data['mobiledoc'];
        final plainText = _mobiledocToPlainText(doc);
        if (plainText.isNotEmpty) {
          contentMd = plainText;
        }
      } catch (_) {}
    }

    return BlogPost(
      id: (data['id'] is String) ? int.tryParse(data['id'] as String) : (data['id'] as num?)?.toInt(),
      title: data['title']?.toString() ?? '',
      contentMd: contentMd,
      contentHtml: data['html']?.toString(),
      date: DateTime.tryParse(data['published_at']?.toString() ?? data['created_at']?.toString() ?? '') ?? DateTime.now(),
      modifiedDate: DateTime.tryParse(data['updated_at']?.toString() ?? '') ?? DateTime.now(),
      status: data['status']?.toString() == 'published' ? 'publish' : 'draft',
      slug: data['slug']?.toString(),
      tags: tags,
      siteId: config.id,
      siteType: BlogType.ghost,
      link: data['url']?.toString(),
    );
  }

  /// Mobiledoc → 纯文本（P0 简化版，不做完整反转换）
  String _mobiledocToPlainText(dynamic doc) {
    if (doc is! Map) return '';
    final cards = (doc['cards'] as List?) ?? [];
    final buf = StringBuffer();

    for (final card in cards) {
      if (card is! List || card.length < 2) continue;
      final type = card[0]?.toString() ?? '';
      final payload = card.length > 1 ? card[1] : null;

      switch (type) {
        case 'markdown':
          if (payload is Map) {
            buf.writeln(payload['markdown']?.toString() ?? '');
          }
          break;
        case 'html':
          if (payload is Map) {
            // 简单 HTML 标签剥离
            final html = payload['html']?.toString() ?? '';
            buf.writeln(html.replaceAll(RegExp(r'<[^>]+>'), ''));
          }
          break;
        case 'image':
          if (payload is Map) {
            final src = payload['src']?.toString() ?? '';
            final alt = payload['alt']?.toString() ?? '';
            buf.writeln('![$alt]($src)');
          }
          break;
        case 'heading':
          if (payload is Map) {
            buf.writeln(payload['text']?.toString() ?? '');
          }
          break;
      }
    }

    return buf.toString().trim();
  }

  /// Markdown → Mobiledoc JSON 结构
  ///
  /// Ghost 的 Mobiledoc 格式：
  /// ```json
  /// {
  ///   "version": "0.3.1",
  ///   "atoms": [],
  ///   "cards": [["card-name", {payload}]],
  ///   "markups": [],
  ///   "sections": [[10, cardIndex], [1, "p", [[0, [], 0, "text"]]]]
  /// }
  /// ```
  Map<String, dynamic> _markdownToMobiledoc(String md) {
    final cards = <List<dynamic>>[];
    final sections = <List<dynamic>>[];
    final lines = md.split('\n');
    bool inCodeBlock = false;
    StringBuffer codeBuf = StringBuffer();
    String? codeLang;
    StringBuffer paragraphBuf = StringBuffer();

    void flushParagraph() {
      final text = paragraphBuf.toString().trim();
      paragraphBuf.clear();
      if (text.isEmpty) return;
      cards.add(['markdown', {'markdown': text}]);
      sections.add([10, cards.length - 1]);
    }

    for (final line in lines) {
      // 代码块
      if (line.trim().startsWith('```')) {
        flushParagraph();
        if (inCodeBlock) {
          final code = codeBuf.toString();
          codeBuf.clear();
          inCodeBlock = false;
          cards.add(['code', {'code': code, 'language': codeLang ?? 'plaintext'}]);
          sections.add([10, cards.length - 1]);
        } else {
          inCodeBlock = true;
          codeLang = line.trim().substring(3).trim();
          if (codeLang.isEmpty) codeLang = null;
        }
        continue;
      }

      if (inCodeBlock) {
        codeBuf.writeln(line);
        continue;
      }

      // 图片
      final imgMatch = RegExp(r'^!\[(.*?)\]\((.*?)\)$').firstMatch(line.trim());
      if (imgMatch != null) {
        flushParagraph();
        final alt = imgMatch.group(1) ?? '';
        final src = imgMatch.group(2) ?? '';
        cards.add(['image', {'src': src, 'alt': alt}]);
        sections.add([10, cards.length - 1]);
        continue;
      }

      // 标题
      if (line.startsWith('# ')) {
        flushParagraph();
        cards.add(['heading', {'text': line.substring(2).trim(), 'level': 1}]);
        sections.add([10, cards.length - 1]);
        continue;
      }
      if (line.startsWith('## ')) {
        flushParagraph();
        cards.add(['heading', {'text': line.substring(3).trim(), 'level': 2}]);
        sections.add([10, cards.length - 1]);
        continue;
      }
      if (line.startsWith('### ')) {
        flushParagraph();
        cards.add(['heading', {'text': line.substring(4).trim(), 'level': 3}]);
        sections.add([10, cards.length - 1]);
        continue;
      }

      // 引用
      if (line.startsWith('> ')) {
        flushParagraph();
        cards.add(['html', {'html': '<blockquote>${_escapeHtml(line.substring(2))}</blockquote>'}]);
        sections.add([10, cards.length - 1]);
        continue;
      }

      // 空行 → 段落分隔
      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }

      // 普通段落 → 累积到 buffer
      if (paragraphBuf.isEmpty) {
        paragraphBuf.write(line);
      } else {
        paragraphBuf.write('\n$line');
      }
    }

    // 收尾
    flushParagraph();

    return {
      'version': '0.3.1',
      'atoms': [],
      'cards': cards,
      'markups': [],
      'sections': sections,
    };
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return 'png';
    return path.substring(dot + 1).toLowerCase();
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  @override
  void dispose() {
    _client?.close(force: true);
    _client = null;
    _challengeHttp = null;
    _jwtToken = null;
    _tokenExpiry = null;
  }
}