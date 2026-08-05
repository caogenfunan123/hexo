import 'dart:convert';
import 'dart:io';

import '../../models/app_settings.dart';
import '../../models/blog_post.dart';
import '../../models/blog_site_config.dart';
import '../../services/html_to_markdown.dart';
import 'blog_repository.dart';

/// WordPress REST API 适配器
///
/// 鉴权：Application Password（WP 5.6+ 内置）
///   - 用户操作：WP后台 → 个人资料 → 应用程序密码 → 生成
///   - 请求头：Authorization: Basic base64(username:password)
///
/// 端点：/wp/v2/posts（CRUD）、/wp/v2/users/me（连通测试）
class WordPressAdapter implements BlogRepository {
  final BlogSiteConfig _config;
  final AppSettings _settings;
  HttpClient? _client;

  WordPressAdapter(this._config, this._settings);

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

  /// 构建 Basic Auth Header
  String get _authHeader {
    final credentials = base64Encode(
      utf8.encode('${_config.wpUsername}:${_config.wpAppPassword}'),
    );
    return 'Basic $credentials';
  }

  /// 构建 WordPress REST API URL
  Uri _apiUri(String path, [Map<String, String>? query]) {
    final base = _config.siteUrl.endsWith('/')
        ? _config.siteUrl.substring(0, _config.siteUrl.length - 1)
        : _config.siteUrl;
    return Uri.parse('$base/wp-json/wp/v2$path').replace(
      queryParameters: query,
    );
  }

  /// 发送 HTTP 请求
  Future<Map<String, dynamic>> _request(
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

    req.headers.set('Authorization', _authHeader);
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
        return jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        return {'raw': text};
      }
    }

    _handleError(response.statusCode, text);
  }

  /// 分类 HTTP 错误，抛出友好提示
  Never _handleError(int statusCode, String body) {
    String message;
    switch (statusCode) {
      case 401:
        message = '鉴权失败：应用密码错误或已过期。'
            '请在 WordPress 后台重新生成 Application Password。';
      case 403:
        message = '权限不足：该账号没有发布文章的权限。请检查用户角色。';
      case 404:
        message = '接口不存在：请确认站点是完整的 WordPress 站点（5.6+），'
            '且 REST API 未被禁用。';
      case 500:
        message = 'WordPress 服务器内部错误。请稍后重试。';
      case 502:
      case 503:
        message = 'WordPress 服务暂时不可用。请稍后重试。';
      case 0:
        message = '无法连接到站点：请检查 URL 是否正确，'
            '以及服务器防火墙是否开放。';
      default:
        message = 'HTTP $statusCode: 请求失败。';
    }
    throw BlogRepositoryException(statusCode, message, body);
  }

  @override
  Future<ConnectionResult> testConnection() async {
    try {
      final client = _http;
      final uri = _apiUri('/users/me');
      final req = await client.getUrl(uri);
      req.headers.set('Authorization', _authHeader);
      req.headers.set('Accept', 'application/json');
      req.headers.set('User-Agent', 'HexoBlogManager/1.0');

      final response = await req.close();
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final data = jsonDecode(text) as Map<String, dynamic>;
        final name = data['name']?.toString() ?? '未知';
        return ConnectionResult.ok('连接成功！已认证为：$name');
      }

      if (response.statusCode == 401) {
        return ConnectionResult.fail(
          '鉴权失败：应用密码错误。请确认使用 Application Password 而非登录密码。',
          detail: 'WP后台 → 用户 → 个人资料 → 底部「应用程序密码」生成',
        );
      }

      if (response.statusCode == 404) {
        return ConnectionResult.fail(
          '未找到 WordPress REST API。请确认站点是 WordPress 5.6+，且 REST API 未被禁用。',
          detail: '尝试访问: ${uri.toString()}',
        );
      }

      return ConnectionResult.fail(
        'HTTP ${response.statusCode}: 连接异常',
        detail: text,
      );
    } on SocketException catch (e) {
      return ConnectionResult.fail(
        '网络无法访问站点：${_config.siteUrl}',
        detail: '请检查：1) URL 是否正确 2) 服务器是否在线 3) 防火墙是否开放\n${e.message}',
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
    final uri = _apiUri('/posts', {
      'page': page.toString(),
      'per_page': perPage.toString(),
      'status': 'publish,draft',
      'orderby': 'date',
      'order': 'desc',
      '_embed': 'true',
    });

    final client = _http;
    final req = await client.getUrl(uri);
    req.headers.set('Authorization', _authHeader);
    req.headers.set('Accept', 'application/json');
    req.headers.set('User-Agent', 'HexoBlogManager/1.0');

    final response = await req.close();
    final text = await response.transform(utf8.decoder).join();

    if (response.statusCode == 200) {
      final list = jsonDecode(text) as List;

      return list.map((item) {
        final data = item as Map<String, dynamic>;
        return _wpPostToBlogPost(data);
      }).toList();
    }

    _handleError(response.statusCode, text);
  }

  @override
  Future<BlogPost?> getPostById(int id) async {
    final uri = _apiUri('/posts/$id', {'_embed': 'true'});

    final client = _http;
    final req = await client.getUrl(uri);
    req.headers.set('Authorization', _authHeader);
    req.headers.set('Accept', 'application/json');
    req.headers.set('User-Agent', 'HexoBlogManager/1.0');

    final response = await req.close();
    final text = await response.transform(utf8.decoder).join();

    if (response.statusCode == 200) {
      final data = jsonDecode(text) as Map<String, dynamic>;
      return _wpPostToBlogPost(data);
    }
    if (response.statusCode == 404) return null;

    _handleError(response.statusCode, text);
  }

  @override
  Future<BlogPost> createPost(BlogPost post) async {
    // Markdown 转 Gutenberg HTML
    final html = _markdownToGutenbergHtml(post.contentMd);

    final body = <String, dynamic>{
      'title': post.title,
      'content': html,
      'status': post.status == 'publish' ? 'publish' : 'draft',
    };

    if (post.slug != null && post.slug!.isNotEmpty) {
      body['slug'] = post.slug;
    }
    if (post.tags.isNotEmpty) {
      body['tags'] = post.tags;
    }
    if (post.categories.isNotEmpty) {
      body['categories'] = post.categories;
    }

    final uri = _apiUri('/posts');
    final data = await _request('POST', uri, body: body);

    return _wpPostToBlogPost(data);
  }

  @override
  Future<BlogPost> updatePost(BlogPost post) async {
    if (post.id == null) {
      throw BlogRepositoryException(400, '更新文章需要远程 ID，请先发布文章。', '');
    }

    final html = _markdownToGutenbergHtml(post.contentMd);

    final body = <String, dynamic>{
      'title': post.title,
      'content': html,
      'status': post.status == 'publish' ? 'publish' : 'draft',
    };

    if (post.slug != null && post.slug!.isNotEmpty) {
      body['slug'] = post.slug;
    }

    final uri = _apiUri('/posts/${post.id}');
    final data = await _request('PUT', uri, body: body);

    return _wpPostToBlogPost(data);
  }

  @override
  Future<bool> deletePost(int postId) async {
    final uri = _apiUri('/posts/$postId', {'force': 'true'});
    await _request('DELETE', uri);
    return true;
  }

  @override
  Future<MediaUploadResult> uploadMedia(String filePath) async {
    try {
      final client = _http;
      final uri = _apiUri('/media');
      final req = await client.postUrl(uri);
      req.headers.set('Authorization', _authHeader);
      req.headers.set('Content-Disposition', 'attachment; filename="${filePath.split('/').last}"');
      req.headers.set('User-Agent', 'HexoBlogManager/1.0');

      final file = File(filePath);
      if (!await file.exists()) {
        return MediaUploadResult.failure('文件不存在: $filePath');
      }

      final bytes = await file.readAsBytes();
      req.headers.set('Content-Type', 'image/${_extension(filePath)}');
      req.headers.set('Content-Length', bytes.length.toString());
      req.add(bytes);

      final response = await req.close();
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode == 201) {
        final data = jsonDecode(text) as Map<String, dynamic>;
        final id = (data['id'] as num?)?.toInt() ?? 0;
        final url = data['source_url']?.toString() ?? '';
        return MediaUploadResult.success(id, url);
      }

      return MediaUploadResult.failure('上传失败: HTTP ${response.statusCode}');
    } catch (e) {
      return MediaUploadResult.failure('上传失败: $e');
    }
  }

  /// WordPress REST API 文章 → 统一 BlogPost 模型
  BlogPost _wpPostToBlogPost(Map<String, dynamic> data) {
    final title = data['title'] is Map
        ? (data['title'] as Map)['rendered']?.toString() ?? ''
        : data['title']?.toString() ?? '';

    final contentHtml = data['content'] is Map
        ? (data['content'] as Map)['rendered']?.toString() ?? ''
        : data['content']?.toString() ?? '';

    // HTML → Markdown 反向转换，支持线上文章拉回编辑
    final contentMd = HtmlToMarkdown.fromGutenberg(contentHtml);

    final tags = <String>[];
    if (data['tags'] is List) {
      for (final t in data['tags'] as List) {
        if (t is Map) tags.add(t['name']?.toString() ?? '');
      }
    }

    final categories = <String>[];
    if (data['categories'] is List) {
      for (final c in data['categories'] as List) {
        if (c is Map) categories.add(c['name']?.toString() ?? '');
      }
    }

    return BlogPost(
      id: (data['id'] as num?)?.toInt(),
      title: title,
      contentMd: contentMd,
      contentHtml: contentHtml,
      date: DateTime.tryParse(data['date']?.toString() ?? '') ?? DateTime.now(),
      modifiedDate: DateTime.tryParse(data['modified']?.toString() ?? '') ?? DateTime.now(),
      status: data['status']?.toString() ?? 'draft',
      slug: data['slug']?.toString(),
      tags: tags,
      categories: categories,
      siteId: config.id,
      siteType: BlogType.wordpress,
      link: data['link']?.toString(),
    );
  }

  /// 获取文件扩展名
  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return 'png';
    return path.substring(dot + 1).toLowerCase();
  }

  /// Markdown → Gutenberg HTML 转换
  ///
  /// 生成带 WordPress block class 的语义化 HTML，
  /// 确保 Gutenberg 编辑器能正确识别每个 block
  static String _markdownToGutenbergHtml(String md) {
    final buf = StringBuffer();
    final lines = md.split('\n');
    bool inCodeBlock = false;
    String? codeLang;
    StringBuffer codeBuf = StringBuffer();
    bool inTable = false;
    StringBuffer tableBuf = StringBuffer();
    bool inList = false;
    bool orderedList = false;
    StringBuffer listBuf = StringBuffer();

    void flushParagraph(StringBuffer sb) {
      final text = sb.toString().trim();
      if (text.isEmpty) return;
      // 处理行内格式
      final processed = _processInline(text);
      buf.writeln('<!-- wp:paragraph -->');
      buf.writeln('<p>$processed</p>');
      buf.writeln('<!-- /wp:paragraph -->');
      buf.writeln();
      sb.clear();
    }

    void flushList() {
      if (!inList) return;
      final tag = orderedList ? 'ol' : 'ul';
      buf.writeln('<!-- wp:list -->');
      buf.writeln('<$tag>$listBuf</$tag>');
      buf.writeln('<!-- /wp:list -->');
      buf.writeln();
      listBuf.clear();
      inList = false;
      orderedList = false;
    }

    for (final line in lines) {
      // 代码块
      if (line.trim().startsWith('```')) {
        if (inCodeBlock) {
          // 结束代码块
          final code = codeBuf.toString();
          codeBuf.clear();
          inCodeBlock = false;
          buf.writeln('<!-- wp:code -->');
          buf.writeln('<pre class="wp-block-code"><code>${_escapeHtml(code)}</code></pre>');
          buf.writeln('<!-- /wp:code -->');
          buf.writeln();
        } else {
          // 开始代码块：先刷新之前累积的段落文本
          flushParagraph(codeBuf);
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

      // 表格
      if (line.trim().startsWith('|') && line.trim().endsWith('|')) {
        flushParagraph(codeBuf);
        if (!inTable) {
          inTable = true;
          tableBuf = StringBuffer();
        }
        tableBuf.writeln(line);
        continue;
      } else if (inTable) {
        // 表格结束
        _flushTable(buf, tableBuf.toString());
        inTable = false;
      }

      // 标题
      if (line.startsWith('##### ')) {
        flushParagraph(codeBuf);
        buf.writeln('<!-- wp:heading {"level":5} -->');
        buf.writeln('<h5 class="wp-block-heading">${_processInline(line.substring(6))}</h5>');
        buf.writeln('<!-- /wp:heading -->');
        buf.writeln();
        continue;
      }
      if (line.startsWith('#### ')) {
        flushParagraph(codeBuf);
        buf.writeln('<!-- wp:heading {"level":4} -->');
        buf.writeln('<h4 class="wp-block-heading">${_processInline(line.substring(5))}</h4>');
        buf.writeln('<!-- /wp:heading -->');
        buf.writeln();
        continue;
      }
      if (line.startsWith('### ')) {
        flushParagraph(codeBuf);
        buf.writeln('<!-- wp:heading {"level":3} -->');
        buf.writeln('<h3 class="wp-block-heading">${_processInline(line.substring(4))}</h3>');
        buf.writeln('<!-- /wp:heading -->');
        buf.writeln();
        continue;
      }
      if (line.startsWith('## ')) {
        flushParagraph(codeBuf);
        buf.writeln('<!-- wp:heading -->');
        buf.writeln('<h2 class="wp-block-heading">${_processInline(line.substring(3))}</h2>');
        buf.writeln('<!-- /wp:heading -->');
        buf.writeln();
        continue;
      }
      if (line.startsWith('# ')) {
        flushParagraph(codeBuf);
        buf.writeln('<!-- wp:heading {"level":1} -->');
        buf.writeln('<h1 class="wp-block-heading">${_processInline(line.substring(2))}</h1>');
        buf.writeln('<!-- /wp:heading -->');
        buf.writeln();
        continue;
      }

      // 图片
      final imgMatch = RegExp(r'^!\[(.*?)\]\((.*?)\)$').firstMatch(line.trim());
      if (imgMatch != null) {
        flushParagraph(codeBuf);
        final alt = imgMatch.group(1) ?? '';
        final src = imgMatch.group(2) ?? '';
        buf.writeln('<!-- wp:image -->');
        buf.writeln('<figure class="wp-block-image"><img src="$src" alt="${_escapeHtml(alt)}"/></figure>');
        buf.writeln('<!-- /wp:image -->');
        buf.writeln();
        continue;
      }

      // 引用
      if (line.startsWith('> ')) {
        flushParagraph(codeBuf);
        buf.writeln('<!-- wp:quote -->');
        buf.writeln('<blockquote class="wp-block-quote"><p>${_processInline(line.substring(2))}</p></blockquote>');
        buf.writeln('<!-- /wp:quote -->');
        buf.writeln();
        continue;
      }

      // 列表
      if (line.trim().startsWith('- ') || line.trim().startsWith('* ')) {
        flushParagraph(codeBuf);
        if (inList && orderedList) flushList();
        if (!inList) {
          orderedList = false;
        }
        inList = true;
        final text = line.trim().substring(2);
        listBuf.writeln('<li>${_processInline(text)}</li>');
        continue;
      }

      // 序号列表
      if (RegExp(r'^\d+\. ').hasMatch(line.trim())) {
        flushParagraph(codeBuf);
        if (inList && !orderedList) flushList();
        if (!inList) {
          orderedList = true;
        }
        inList = true;
        final text = line.trim().replaceFirst(RegExp(r'^\d+\. '), '');
        listBuf.writeln('<li>${_processInline(text)}</li>');
        continue;
      }

      // 非列表行 → 结束列表
      if (inList && !line.trim().startsWith('- ') && !line.trim().startsWith('* ') && !RegExp(r'^\d+\. ').hasMatch(line.trim())) {
        flushList();
      }

      // 空行 → 段落分隔
      if (line.trim().isEmpty) {
        flushParagraph(codeBuf);
        continue;
      }

      // 普通段落
      codeBuf.writeln(line);
    }

    // 收尾
    if (inTable) {
      _flushTable(buf, tableBuf.toString());
    }
    flushList();
    flushParagraph(codeBuf);

    return buf.toString().trim();
  }

  /// 处理行内格式（加粗、斜体、链接、行内代码）
  static String _processInline(String text) {
    var result = text;
    // 行内代码
    result = result.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (m) => '<code>${m.group(1)}</code>',
    );
    // 链接
    result = result.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      (m) => '<a href="${m.group(2)}">${m.group(1)}</a>',
    );
    // 加粗
    result = result.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'),
      (m) => '<strong>${m.group(1)}</strong>',
    );
    // 斜体
    result = result.replaceAllMapped(
      RegExp(r'\*([^*]+)\*'),
      (m) => '<em>${m.group(1)}</em>',
    );
    return result;
  }

  /// 输出表格
  static void _flushTable(StringBuffer buf, String tableText) {
    final lines = tableText.trim().split('\n');
    if (lines.length < 2) return;

    buf.writeln('<!-- wp:table -->');
    buf.writeln('<figure class="wp-block-table"><table>');
    for (var i = 0; i < lines.length; i++) {
      final cells = lines[i].split('|').where((c) => c.trim().isNotEmpty).toList();
      if (cells.isEmpty) continue;
      final tag = i == 0 ? 'th' : 'td';
      buf.write('<tr>');
      for (final cell in cells) {
        buf.write('<${tag}>${_processInline(cell.trim())}</${tag}>');
      }
      buf.writeln('</tr>');
      // 跳过表头分隔行
      if (i == 0 && lines.length > 1 && lines[1].contains('---')) {
        i++; // skip separator
      }
    }
    buf.writeln('</table></figure>');
    buf.writeln('<!-- /wp:table -->');
    buf.writeln();
  }

  /// HTML 转义
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