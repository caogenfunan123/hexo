import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// 本地资产服务器：基于 `dart:io HttpServer` 自实现，不依赖
/// `InAppLocalhostServer`（避免其 `runZonedGuarded` + `completer` 可能
/// 永久挂起的 bug）。
///
/// 提供三个端点：
/// - `/preview.html` — 静态预览模板（从 asset bundle 读取）
/// - `/web/*` — JS/CSS 静态资源
/// - `/content` — 当前文档 body HTML（动态，由 `updateContent` 更新）
///
/// WebView 通过 `initialUrlRequest` 加载 `http://127.0.0.1:18080/preview.html`，
/// 页面 HTML 本身很轻（~3KB），JS/CSS 和 body 通过 HTTP 加载，完全不经过
/// MethodChannel，彻底避免 Android Binder 事务上限。
class LocalAssetServer {
  LocalAssetServer._();

  static final LocalAssetServer _instance = LocalAssetServer._();
  static LocalAssetServer get instance => _instance;

  static const int port = 18080;
  static const String _assetPrefix = 'assets/preview/web';

  HttpServer? _server;
  bool _started = false;

  /// 当前文档 body HTML（通过 `updateContent` 设置）。
  String _content = '';

  /// 基础 URL（不含尾部斜杠），例如 `http://127.0.0.1:18080`。
  String get baseUrl => 'http://127.0.0.1:$port';

  /// 预览页面 URL，调用方通过 `?dark=` 参数控制主题。
  String get previewUrl => '$baseUrl/preview.html';

  /// 是否已启动。
  bool get isRunning => _started;

  /// 更新文档 body（内存操作，不经过 MethodChannel）。
  void updateContent(String body) {
    _content = body;
  }

  /// 启动服务器。
  ///
  /// 返回 `true` 表示成功，`false` 表示启动失败（超时/端口占用等）。
  /// 不会永久挂起。
  Future<bool> ensureStarted() async {
    if (_started) return true;
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      ).timeout(const Duration(seconds: 5));
      _server!.listen(_handleRequest);
      _started = true;
      return true;
    } catch (e) {
      _server = null;
      return false;
    }
  }

  /// 关闭服务器。
  Future<void> shutdown() async {
    await _server?.close(force: true);
    _server = null;
    _started = false;
    _content = '';
  }

  void _handleRequest(HttpRequest request) {
    final uri = request.requestedUri;
    final path = uri.path == '/' || uri.path.isEmpty ? '/preview.html' : uri.path;

    request.response.headers.set('Access-Control-Allow-Origin', '*');

    if (path == '/content') {
      _serveContent(request);
      return;
    }

    if (path == '/preview.html') {
      _servePreview(request);
      return;
    }

    if (path.startsWith('/web/')) {
      _serveAsset(request, path);
      return;
    }

    _serve404(request);
  }

  void _serveContent(HttpRequest request) {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_content);
    request.response.close();
  }

  Future<void> _servePreview(HttpRequest request) async {
    try {
      final template = await rootBundle.loadString(
        '$_assetPrefix/preview_template.html',
      );
      request.response.headers.contentType = ContentType.html;
      request.response.write(template);
      await request.response.close();
    } catch (e) {
      _serve404(request);
    }
  }

  Future<void> _serveAsset(HttpRequest request, String path) async {
    final fileName = path.startsWith('/web/') ? path.substring(5) : path;
    final assetPath = '$_assetPrefix/$fileName';
    try {
      final data = await rootBundle.load(assetPath);
      final mime = _mimeType(fileName);
      request.response.headers.contentType = ContentType.parse(mime);
      request.response.add(data.buffer.asUint8List());
      await request.response.close();
    } catch (e) {
      _serve404(request);
    }
  }

  void _serve404(HttpRequest request) {
    request.response.statusCode = HttpStatus.notFound;
    request.response.write('Not found');
    request.response.close();
  }

  static String _mimeType(String name) {
    if (name.endsWith('.js')) return 'application/javascript';
    if (name.endsWith('.css')) return 'text/css';
    if (name.endsWith('.html')) return 'text/html';
    if (name.endsWith('.json')) return 'application/json';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.svg')) return 'image/svg+xml';
    return 'application/octet-stream';
  }
}