import 'dart:convert';
import 'dart:io';

import '../../models/app_settings.dart';
import '../../models/blog_post.dart';
import '../../models/blog_site_config.dart';
import '../../services/html_to_markdown.dart';
import 'blog_repository.dart';

/// Typecho REST API 适配器
///
/// Typecho 没有官方 REST API，依赖第三方插件。
/// 常用插件：Typecho-Plugin-Restful、typecho-json-api
///
/// 鉴权：插件生成的 Token
///   - 用户操作：安装插件 → 插件设置页生成 Token → 粘贴到此处
///   - 请求头：Token: {token} 或 Authorization: Bearer {token}
///
/// 注意：不同插件的 JSON 结构存在差异，本适配器尝试兼容常见格式，
/// 如果遇到不兼容的插件，会返回友好提示让用户检查插件配置。
class TypechoAdapter implements BlogRepository {
  final BlogSiteConfig _config;
  final AppSettings _settings;
  HttpClient? _client;

  /// 常见的 Typecho REST API 端点路径
  static const _commonEndpoints = [
    '/api/posts',
    '/restful/posts',
    '/json-api/posts',
    '/action/posts',
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

  /// 获取 API 端点路径
  String get _endpoint {
    if (_config.typechoApiEndpoint != null && _config.typechoApiEndpoint!.isNotEmpty) {
      return _config.typechoApiEndpoint!;
    }
    return '/api/posts';
  }

  /// 构建 Typecho API URL
  Uri _apiUri(String path, [Map<String, String>? query]) {
    final base = _config.siteUrl.endsWith('/')
        ? _config.siteUrl.substring(0, _config.siteUrl.length - 1)
        : _config.siteUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  /// 发送 HTTP 请求
  Future<dynamic> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final client = _http;
    final req = method == 'GET'
        ? await client.getUrl(uri)
        : method == 'POST'
            ? await client.postUrl(uri)
            : method == 'PUT'
                ? await client.putUrl(uri)
                : await client.deleteUrl(uri);

    // Typecho 插件通常使用 Token 头部
    req.headers.set('Token', _config.typechoToken ?? '');
    req.headers.set('Authorization', 'Bearer ${_config.typechoToken ?? ''}');
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Accept', 'application/json');
    req.headers.set('User-Agent', 'HexoBlogManager/1.0');

    if (body != null) {
      req.write(jsonEncode(body));
    }

    final response = await req.close();
    final text = await response.transform(utf8.decoder).join();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (text.isEmpty) return {};
      try {
        return jsonDecode(text);
      } catch (_) {
        return {'raw': text};
      }
    }

    _handleError(response.statusCode, text);
    return {};
  }

  Never _handleError(int statusCode, String body) {
    String message;
    switch (statusCode) {
      case 401:
      case 403:
        message = '鉴权失败：Token 无效或已过期。请在 Typecho 插件设置页重新生成 Token。';
      case 404:
        message = 'API 端点不存在。请确认：\n'
            '1. 已安装 REST API 插件（推荐 Typecho-Plugin-Restful）\n'
            '2. 插件已正确配置\n'
            '3. API 端点路径正确（当前：$_endpoint）\n'
            '4. 尝试切换其他端点路径';
      case 500:
        message = 'Typecho 服务器内部错误。请检查插件日志。';
      case 0:
        message = '无法连接到 Typecho 站点。请检查 URL 是否正确。';
      default:
        message = 'Typecho HTTP $statusCode: 请求失败。';
    }
    throw BlogRepositoryException(statusCode, message, body);
  }

  /// 自动探测可用端点
  Future<String?> _detectEndpoint() async {
    for (final ep in _commonEndpoints) {
      try {
        final uri = _apiUri(ep, {'page': '1', 'perPage': '1'});
        final client = _http;
        final req = await client.getUrl(uri);
        req.headers.set('Token', _config.typechoToken ?? '');
        req.headers.set('Authorization', 'Bearer ${_config.typechoToken ?? ''}');
        req.headers.set('Accept', 'application/json');
        req.headers.set('User-Agent', 'HexoBlogManager/1.0');

        final response = await req.close();
        if (response.statusCode == 200) {
          return ep;
        }
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
            '未找到 Typecho REST API 端点。\n'
            '请确认已安装 REST API 插件（推荐 Typecho-Plugin-Restful），\n'
            '并在站点设置中手动指定 API 端点路径。',
            detail: '尝试过的端点：${_commonEndpoints.join(', ')}',
          );
        }
      }

      final uri = _apiUri(ep, {'page': '1', 'perPage': '1'});
      final client = _http;
      final req = await client.getUrl(uri);
      req.headers.set('Token', _config.typechoToken ?? '');
      req.headers.set('Authorization', 'Bearer ${_config.typechoToken ?? ''}');
      req.headers.set('Accept', 'application/json');
      req.headers.set('User-Agent', 'HexoBlogManager/1.0');

      final response = await req.close();
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        return ConnectionResult.ok('连接成功！API 端点：$ep');
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return ConnectionResult.fail(
          '鉴权失败：Token 无效。请在 Typecho 插件设置页生成 Token。',
          detail: 'API 端点：$ep',
        );
      }

      return ConnectionResult.fail(
        'HTTP ${response.statusCode}: 连接异常',
        detail: 'API 端点：$ep\n$text',
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
    final uri = _apiUri(_endpoint, {
      'page': page.toString(),
      'perPage': perPage.toString(),
    });
    final data = await _request('GET', uri);

    // 兼容不同插件返回格式
    List list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = (data['data'] ?? data['posts'] ?? data['items'] ?? []) as List;
    } else {
      list = [];
    }

    return list.map((item) {
      return _typechoPostToBlogPost(item as Map<String, dynamic>);
    }).toList();
  }

  @override
  Future<BlogPost?> getPostById(int id) async {
    final uri = _apiUri('$_endpoint/$id');
    final data = await _request('GET', uri);

    Map<String, dynamic> post;
    if (data is Map) {
      post = Map<String, dynamic>.from(data);
    } else if (data is List && data.isNotEmpty) {
      post = Map<String, dynamic>.from(data.first as Map);
    } else {
      return null;
    }

    return _typechoPostToBlogPost(post);
  }

  @override
  Future<BlogPost> createPost(BlogPost post) async {
    // Markdown → HTML（Typecho 原生支持 Markdown 解析插件）
    final html = _markdownToHtml(post.contentMd);

    final body = <String, dynamic>{
      'title': post.title,
      'text': html, // 或 'content'，兼容不同插件
      'content': html,
      'status': post.status == 'publish' ? 'publish' : 'draft',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
      if (post.tags.isNotEmpty) 'tags': post.tags.join(','),
      if (post.categories.isNotEmpty) 'category': post.categories.join(','),
    };

    final uri = _apiUri(_endpoint);
    final data = await _request('POST', uri, body: body);

    Map<String, dynamic> result;
    if (data is Map) {
      result = Map<String, dynamic>.from(data);
    } else if (data is List && data.isNotEmpty) {
      result = Map<String, dynamic>.from(data.first as Map);
    } else {
      throw BlogRepositoryException(500, 'Typecho 创建文章失败：未返回数据', '');
    }

    return _typechoPostToBlogPost(result);
  }

  @override
  Future<BlogPost> updatePost(BlogPost post) async {
    if (post.id == null) {
      throw BlogRepositoryException(400, '更新文章需要远程 ID，请先发布文章。', '');
    }

    final html = _markdownToHtml(post.contentMd);

    final body = <String, dynamic>{
      'title': post.title,
      'text': html,
      'content': html,
      'status': post.status == 'publish' ? 'publish' : 'draft',
      if (post.slug != null && post.slug!.isNotEmpty) 'slug': post.slug,
    };

    final uri = _apiUri('$_endpoint/${post.id}');
    final data = await _request('PUT', uri, body: body);

    Map<String, dynamic> result;
    if (data is Map) {
      result = Map<String, dynamic>.from(data);
    } else if (data is List && data.isNotEmpty) {
      result = Map<String, dynamic>.from(data.first as Map);
    } else {
      throw BlogRepositoryException(500, 'Typecho 更新文章失败：未返回数据', '');
    }

    return _typechoPostToBlogPost(result);
  }

  @override
  Future<bool> deletePost(int postId) async {
    final uri = _apiUri('$_endpoint/$postId');
    await _request('DELETE', uri);
    return true;
  }

  @override
  Future<MediaUploadResult> uploadMedia(String filePath) async {
    // Typecho 的媒体上传接口因插件而异，P0 提供基础实现
    try {
      final client = _http;
      // 从端点路径提取 API 基础路径，避免使用 .. 拼接
      final ep = _endpoint;
      final basePath = ep.substring(0, ep.lastIndexOf('/'));
      final uri = _apiUri('$basePath/media/upload');
      final req = await client.postUrl(uri);
      req.headers.set('Token', _config.typechoToken ?? '');
      req.headers.set('Authorization', 'Bearer ${_config.typechoToken ?? ''}');
      req.headers.set('User-Agent', 'HexoBlogManager/1.0');

      final file = File(filePath);
      if (!await file.exists()) {
        return MediaUploadResult.failure('文件不存在: $filePath');
      }

      final bytes = await file.readAsBytes();
      final boundary = '----FormBoundary${DateTime.now().millisecondsSinceEpoch}';
      req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');

      final body = utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="${filePath.split('/').last}"\r\n'
        'Content-Type: image/${_extension(filePath)}\r\n\r\n',
      );
      final footer = utf8.encode('\r\n--$boundary--\r\n');

      req.contentLength = body.length + bytes.length + footer.length;
      req.add(body);
      req.add(bytes);
      req.add(footer);

      final response = await req.close();
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = jsonDecode(text);
          final url = data is Map
              ? (data['url'] ?? data['file'] ?? data['path'] ?? '').toString()
              : '';
          if (url.isNotEmpty) {
            return MediaUploadResult.success(0, url);
          }
        } catch (_) {}
      }

      return MediaUploadResult.failure(
        '媒体上传功能依赖 Typecho 插件支持。\n'
        '请确认插件版本支持文件上传接口。\n'
        'HTTP ${response.statusCode}',
      );
    } catch (e) {
      return MediaUploadResult.failure('上传失败: $e');
    }
  }

  /// Typecho 文章 → 统一 BlogPost 模型
  BlogPost _typechoPostToBlogPost(Map<String, dynamic> data) {
    // 兼容不同插件的字段名
    final title = data['title']?.toString() ?? '';
    final contentHtml = data['text']?.toString() ?? data['content']?.toString() ?? '';
    final idStr = data['cid']?.toString() ?? data['id']?.toString() ?? '0';
    final id = int.tryParse(idStr) ?? 0;

    final tags = <String>[];
    final tagsRaw = data['tags'];
    if (tagsRaw is String && tagsRaw.isNotEmpty) {
      tags.addAll(tagsRaw.split(',').map((e) => e.trim()));
    } else if (tagsRaw is List) {
      tags.addAll(tagsRaw.map((e) => e.toString()));
    }

    final categories = <String>[];
    final catsRaw = data['category'] ?? data['categories'];
    if (catsRaw is String && catsRaw.isNotEmpty) {
      categories.addAll(catsRaw.split(',').map((e) => e.trim()));
    } else if (catsRaw is List) {
      categories.addAll(catsRaw.map((e) => e.toString()));
    }

    return BlogPost(
      id: id > 0 ? id : null,
      title: title,
      contentMd: HtmlToMarkdown.convert(contentHtml),
      contentHtml: contentHtml,
      date: DateTime.tryParse(data['created']?.toString() ?? data['date']?.toString() ?? '') ?? DateTime.now(),
      modifiedDate: DateTime.tryParse(data['modified']?.toString() ?? '') ?? DateTime.now(),
      status: data['status']?.toString() == 'publish' ? 'publish' : 'draft',
      slug: data['slug']?.toString(),
      tags: tags,
      categories: categories,
      siteId: config.id,
      siteType: BlogType.typecho,
      link: data['permalink']?.toString() ?? data['url']?.toString(),
    );
  }

  /// Markdown → HTML
  /// Typecho 原生支持 Markdown 解析插件，这里做基础转换
  static String _markdownToHtml(String md) {
    final buf = StringBuffer();
    final lines = md.split('\n');
    bool inCodeBlock = false;
    String? codeLang;
    StringBuffer codeBuf = StringBuffer();
    bool inTable = false;
    StringBuffer tableBuf = StringBuffer();
    bool inList = false;
    bool orderedList = false;

    void flushList() {
      if (!inList) return;
      if (orderedList) {
        buf.writeln('</ol>');
      } else {
        buf.writeln('</ul>');
      }
      inList = false;
      orderedList = false;
    }

    for (final line in lines) {
      if (line.trim().startsWith('```')) {
        flushList();
        if (inCodeBlock) {
          buf.writeln('<pre><code>${_escapeHtml(codeBuf.toString())}</code></pre>');
          codeBuf.clear();
          inCodeBlock = false;
        } else {
          inCodeBlock = true;
          codeLang = line.trim().substring(3).trim();
        }
        continue;
      }

      if (inCodeBlock) {
        codeBuf.writeln(line);
        continue;
      }

      // 表格
      if (line.trim().startsWith('|') && line.trim().endsWith('|')) {
        flushList();
        if (!inTable) {
          inTable = true;
          buf.writeln('<table>');
        }
        tableBuf.writeln(line);
        continue;
      } else if (inTable) {
        _flushHtmlTable(buf, tableBuf.toString());
        tableBuf.clear();
        inTable = false;
      }

      // 图片
      final imgMatch = RegExp(r'^!\[(.*?)\]\((.*?)\)$').firstMatch(line.trim());
      if (imgMatch != null) {
        flushList();
        final alt = imgMatch.group(1) ?? '';
        final src = imgMatch.group(2) ?? '';
        buf.writeln('<img src="$src" alt="${_escapeHtml(alt)}" />');
        continue;
      }

      // 标题
      if (line.startsWith('# ')) {
        flushList();
        buf.writeln('<h1>${_processInline(line.substring(2))}</h1>');
      } else if (line.startsWith('## ')) {
        flushList();
        buf.writeln('<h2>${_processInline(line.substring(3))}</h2>');
      } else if (line.startsWith('### ')) {
        flushList();
        buf.writeln('<h3>${_processInline(line.substring(4))}</h3>');
      } else if (line.startsWith('> ')) {
        flushList();
        buf.writeln('<blockquote><p>${_processInline(line.substring(2))}</p></blockquote>');
      } else if (line.trim().startsWith('- ') || line.trim().startsWith('* ')) {
        if (inList && orderedList) flushList();
        if (!inList) {
          orderedList = false;
          buf.writeln('<ul>');
        }
        inList = true;
        buf.writeln('<li>${_processInline(line.trim().substring(2))}</li>');
      } else if (RegExp(r'^\d+\. ').hasMatch(line.trim())) {
        if (inList && !orderedList) flushList();
        if (!inList) {
          orderedList = true;
          buf.writeln('<ol>');
        }
        inList = true;
        final text = line.trim().replaceFirst(RegExp(r'^\d+\. '), '');
        buf.writeln('<li>${_processInline(text)}</li>');
      } else if (line.trim().isEmpty) {
        flushList();
        // skip empty lines
      } else {
        flushList();
        buf.writeln('<p>${_processInline(line)}</p>');
      }
    }

    // 收尾
    if (inTable) {
      _flushHtmlTable(buf, tableBuf.toString());
    }
    flushList();

    return buf.toString().trim();
  }

  /// 输出 HTML 表格
  static void _flushHtmlTable(StringBuffer buf, String tableText) {
    final lines = tableText.trim().split('\n');
    if (lines.length < 2) return;
    for (var i = 0; i < lines.length; i++) {
      final cells = lines[i].split('|').where((c) => c.trim().isNotEmpty).toList();
      if (cells.isEmpty) continue;
      final tag = i == 0 ? 'th' : 'td';
      buf.write('<tr>');
      for (final cell in cells) {
        buf.write('<${tag}>${_processInline(cell.trim())}</${tag}>');
      }
      buf.writeln('</tr>');
      if (i == 0 && lines.length > 1 && lines[1].contains('---')) {
        i++;
      }
    }
    buf.writeln('</table>');
  }

  static String _processInline(String text) {
    var result = text;
    result = result.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => '<code>${m.group(1)}</code>');
    result = result.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), (m) => '<a href="${m.group(2)}">${m.group(1)}</a>');
    result = result.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => '<strong>${m.group(1)}</strong>');
    result = result.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => '<em>${m.group(1)}</em>');
    return result;
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
  }
}