import 'dart:convert';
import 'dart:io';

class WebDavItem {
  final String name;
  final bool isDir;
  final int size;
  final DateTime modified;
  WebDavItem({required this.name, required this.isDir, this.size = 0, required this.modified});
  Map<String, dynamic> toJson() => {'name': name, 'isDir': isDir, 'size': size, 'modified': modified.toIso8601String()};
  factory WebDavItem.fromJson(Map<String, dynamic> j) => WebDavItem(
        name: j['name']?.toString() ?? '',
        isDir: j['isDir'] == true,
        size: (j['size'] as num?)?.toInt() ?? 0,
        modified: DateTime.tryParse(j['modified']?.toString() ?? '') ?? DateTime(2000),
      );
}

class WebDavService {
  bool allowSelfSigned = false;

  Future<HttpClient> _openClient() async {
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 25)
      ..badCertificateCallback = (cert, host, port) => allowSelfSigned;
  }

  Future<String> _put(String url, String token, List<int> bytes, {Map<String, String>? extraHeaders}) async {
    final client = await _openClient();
    try {
      final req = await client.putUrl(Uri.parse(url));
      req.headers.add('Authorization', 'Basic $token');
      if (extraHeaders != null) extraHeaders.forEach(req.headers.add);
      req.headers.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close();
      final status = res.statusCode;
      await res.drain();
      if (status >= 200 && status < 300) return '';
      final text = await Future.value('status $status');
      throw Exception('WebDAV PUT $status: $text');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _method(String method, String url, String token, {Map<String, String>? extraHeaders}) async {
    final client = await _openClient();
    try {
      final req = await client.openUrl(method, Uri.parse(url));
      req.headers.add('Authorization', 'Basic $token');
      if (extraHeaders != null) extraHeaders.forEach(req.headers.add);
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 200 && res.statusCode < 300) return text;
      final snippet =
          text.length > 300 ? text.substring(0, 300) : text;
      throw Exception('WebDAV $method ${res.statusCode}: $snippet');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<WebDavItem>> list(String baseUrl, String username, String password, String folder, {bool recursive = false}) async {
    final url = '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}${folder.isEmpty ? '' : '/' + folder.replaceFirst(RegExp(r'^/'), '')}';
    final body = await _method('PROPFIND', url, _basicToken(username, password), extraHeaders: {'Depth': recursive ? 'infinity' : '1'});
    return _parsePropfind(body, folder, baseUrl);
  }

  Future<void> ensureFolder(String baseUrl, String username, String password, String folder) async {
    if (folder.isEmpty) return;
    final dirs = folder.split('/').where((e) => e.isNotEmpty).toList();
    String current = '';
    for (final d in dirs) {
      current = current.isEmpty ? d : '$current/$d';
      await _mkcol(current, baseUrl, username, password).catchError((_) => null);
    }
  }

  Future<void> _mkcol(String path, String baseUrl, String username, String password) async {
    final url = '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}/${path.replaceFirst(RegExp(r'^/'), '')}';
    await _method('MKCOL', url, _basicToken(username, password)).catchError((_) => '');
  }

  Future<List<int>> downloadFile(String baseUrl, String username, String password, String folder, String name) async {
    final url = '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}/${_uriPath(folder, name)}';
    final client = await _openClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.add('Authorization', 'Basic ${_basicToken(username, password)}');
      final res = await req.close();
      final bytes = await res.fold<List<int>>(<int>[], (acc, chunk) {
        acc.addAll(chunk);
        return acc;
      });
      if (res.statusCode >= 200 && res.statusCode < 300) return bytes;
      throw Exception('WebDAV GET ${res.statusCode}');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> uploadFile(String baseUrl, String username, String password, String folder, String name, List<int> bytes) async {
    await ensureFolder(baseUrl, username, password, folder);
    final url = '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}/${_uriPath(folder, name)}';
    await _put(url, _basicToken(username, password), bytes, extraHeaders: {'Overwrite': 'T'});
  }

  Future<void> deleteFile(String baseUrl, String username, String password, String folder, String name) async {
    final url = '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}/${_uriPath(folder, name)}';
    await _method('DELETE', url, _basicToken(username, password));
  }

  Future<String> syncStatus(String baseUrl, String username, String password, String folder) async {
    final items = await list(baseUrl, username, password, folder);
    return '${items.length} items';
  }

  Future<void> createFolder(String baseUrl, String username, String password, String folder) async {
    await ensureFolder(baseUrl, username, password, folder);
  }

  Future<void> putFile(String baseUrl, String username, String password, String path, String content) async {
    final slash = path.lastIndexOf('/');
    final parent = slash >= 0 ? path.substring(0, slash) : '';
    await ensureFolder(baseUrl, username, password, parent);
    final url = '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}/${path.replaceFirst(RegExp(r'^/'), '')}';
    await _put(url, _basicToken(username, password), utf8.encode(content), extraHeaders: {'Overwrite': 'T'});
  }

  static String _basicToken(String username, String password) =>
      base64Encode(utf8.encode('$username:$password'));

  String _uriPath(String folder, String name) {
    // 对每一路径段单独编码，保留 '/' 分隔符，避免整段编码成 %2F
    final segments = name.split('/').map((s) => Uri.encodeComponent(s)).join('/');
    return '${folder.replaceFirst(RegExp(r'^/'), '')}/$segments'
        .replaceAll(RegExp(r'^/'), '');
  }

  static List<WebDavItem> _parsePropfind(String xml, String folder, String baseUrl) {
    final out = <WebDavItem>[];
    final re = RegExp(r'<d:response>.*?href=\"([^\"]+)\".*?displayname>([^<]+)</displayname>.*?getcontentlength>([^<]*)</getcontentlength>.*?getlastmodified>([^<]+)</getlastmodified>', dotAll: true);
    final base = Uri.parse(baseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final folderNorm = folder.replaceFirst(RegExp(r'^/'), '').replaceFirst(RegExp(r'/$'), '');
    final folderPath = '$basePath/${folderNorm.isEmpty ? '' : folderNorm}'.replaceAll('//', '/');

    for (final m in re.allMatches(xml)) {
      final hrefRaw = m.group(1)!;
      final decodedHref = Uri.decodeFull(hrefRaw);
      final isDir = hrefRaw.endsWith('/');
      final displayName = m.group(2) ?? '';
      if (displayName == '.' || displayName.isEmpty) continue;

      // 相对同步根目录的路径：剥离 basePath + folder 前缀
      String rel = decodedHref;
      if (rel.startsWith(folderPath)) {
        rel = rel.substring(folderPath.length);
      } else {
        final last = rel.lastIndexOf(folderNorm.isEmpty ? basePath : folderNorm);
        if (last >= 0) rel = rel.substring(last + (folderNorm.isEmpty ? basePath.length : folderNorm.length));
      }
      rel = rel.replaceFirst(RegExp(r'^/'), '');

      final mod = DateTime.tryParse(m.group(4) ?? '') ?? DateTime(2000);
      final size = int.tryParse(m.group(3) ?? '0') ?? 0;
      out.add(WebDavItem(
        name: rel.isEmpty ? displayName : rel,
        isDir: isDir,
        size: size,
        modified: mod,
      ));
    }
    if (out.isEmpty) {
      final simple = RegExp(r'href=\"([^\"]+)\"');
      for (final m in simple.allMatches(xml)) {
        final hrefRaw = m.group(1)!;
        final decodedHref = Uri.decodeFull(hrefRaw);
        String rel = decodedHref;
        if (rel.startsWith(folderPath)) {
          rel = rel.substring(folderPath.length);
        }
        rel = rel.replaceFirst(RegExp(r'^/'), '');
        if (rel.isEmpty || rel == '.') continue;
        final isDir = hrefRaw.endsWith('/');
        out.add(WebDavItem(name: rel, isDir: isDir, modified: DateTime(2000)));
      }
    }
    return out;
  }
}

/// Sync local drafts to/from WebDAV directory.
