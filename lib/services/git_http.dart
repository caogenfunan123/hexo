import 'dart:convert';
import 'dart:io';

/// 跨平台 Git API 通用 JSON/表单 HTTP 请求。
///
/// [jsonBody] 与 [formBody] 互斥；都不传时发起无 body 请求。
/// 2xx 返回解码后的 JSON（空响应返回 null），否则抛异常。
Future<dynamic> gitHttpRequest(
  String method,
  String url,
  Map<String, String> headers, {
  Object? jsonBody,
  String? formBody,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.openUrl(method, Uri.parse(url));
    headers.forEach(req.headers.set);
    if (jsonBody != null) {
      req.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode(jsonBody));
      req.headers.contentLength = bytes.length;
      req.add(bytes);
    } else if (formBody != null) {
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      final bytes = utf8.encode(formBody);
      req.headers.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close().timeout(const Duration(seconds: 30));
    final text = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 30));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (text.isEmpty) return null;
      return jsonDecode(text);
    }
    throw Exception('HTTP ${res.statusCode}: $text');
  } finally {
    client.close(force: true);
  }
}

/// 将路径逐段 URL 编码（保留 `/` 分隔符）
String encPathSegments(String path) => path
    .split('/')
    .where((e) => e.isNotEmpty)
    .map(Uri.encodeComponent)
    .join('/');

/// 完整路径一次 URL 编码（GitLab 等平台要求整条路径编码）
String encPathFull(String path) => Uri.encodeComponent(
    path.split('/').where((e) => e.isNotEmpty).join('/'));
