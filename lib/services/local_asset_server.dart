import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// 本地资产服务器：基于 `dart:io HttpServer` 自实现，不依赖
/// `InAppLocalhostServer`（避免其 `runZonedGuarded` + `completer` 可能
/// 永久挂起的 bug）。
///
/// 提供三个端点：
/// - `/preview.html` — 静态预览模板（从 asset bundle 读取，正文内联）
/// - `/web/*` — JS/CSS 静态资源
/// - `/content` — 当前文档 body HTML（动态，由 `updateContent` 更新）
///
/// WebView 通过 `initialUrlRequest` 加载
/// `http://127.0.0.1:18080/preview.html`，页面 HTML 本身很轻（~3KB），
/// JS/CSS 和 body 通过 HTTP 加载，完全不经过 MethodChannel，彻底避免
/// Android Binder 事务上限。
class LocalAssetServer {
  LocalAssetServer._();

  static final LocalAssetServer _instance = LocalAssetServer._();
  static LocalAssetServer get instance => _instance;

  /// 端口。若被占用会自动向后尝试 [portMax] 内的空闲端口。
  static const int port = 18080;
  static const int portMax = 18089;
  static const String _assetPrefix = 'assets/preview/web';

  HttpServer? _server;
  bool _started = false;
  int _actualPort = port;

  /// 当前文档 body HTML（通过 `updateContent` 设置）。
  String _content = '';
  int _contentVersion = 0;

  /// 启动日志回调（供调试面板展示），由调用方注入。
  void Function(String line)? onLog;

  static String _ts() {
    final t = DateTime.now();
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${t.hour}:${pad(t.minute)}:${pad(t.second)}.${(t.millisecond).toString().padLeft(3, '0')}';
  }

void _log(String s) {
    final line = '[${_ts()}] $s';
    stdout.writeln(line);
    onLog?.call(line);
  }

  /// 基础 URL（不含尾部斜杠），例如 `http://127.0.0.1:18080`。
  String get baseUrl => 'http://127.0.0.1:$_actualPort';

  /// 预览页面 URL，调用方通过 `?dark=` 参数控制主题。
  String get previewUrl => '$baseUrl/preview.html';

  /// 实际成功绑定的端口（启动失败时返回 `-1`）。
  int get actualPort => _started ? _actualPort : -1;

  /// 是否已启动。
  bool get isRunning => _started;

  /// 当前正文版本号，调试用。
  int get contentVersion => _contentVersion;

  /// 更新文档 body（内存操作，不经过 MethodChannel）。
  void updateContent(String body) {
    _content = body;
    _contentVersion++;
    _log('updateContent v$_contentVersion (${body.length} chars)');
  }

  /// 启动服务器。
  ///
  /// 返回 `true` 表示成功，`false` 表示启动失败（超时/端口全占）。
  /// 不会永久挂起。端口被占用时自动尝试下一个。
  Future<bool> ensureStarted() async {
    if (_started) return true;
    for (var p = port; p <= portMax; p++) {
      try {
        _server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          p,
          shared: true,
        ).timeout(const Duration(seconds: 5));
        _actualPort = p;
        _server!.listen(_handleRequest);
        _started = true;
        _log('Server bound 127.0.0.1:$p');
        return true;
      } on SocketException catch (e) {
        _log('port $p bind failed: $e, try next');
        continue;
      } catch (e) {
        _log('server start error: $e');
        break;
      }
    }
    _server = null;
    return false;
  }

  Future<void> shutdown() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _started = false;
    _content = '';
    _log('Server shutdown');
  }

  void _handleRequest(HttpRequest request) {
    final uri = request.requestedUri;
    final path = uri.path == '/' || uri.path.isEmpty ? '/preview.html' : uri.path;
    _log('HTTP ${request.method} $path');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Cache-Control', 'no-store');

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
      // 首次渲染直接把正文内联进 HTML，即使 JS fetch 失败也能显示内容。
      request.response.write(
        template.replaceAll(
          '<div id="content"></div>',
          '<div id="content">$_content</div>',
        ),
      );
      _log('serve /preview.html (content $_contentVersion, ${_content.length} chars)');
      await request.response.close();
    } catch (e) {
      _log('serve /preview.html failed: $e');
      _serve404(request);
    }
  }

  Future<void> _serveAsset(HttpRequest request, String path) async {
    final fileName = path.startsWith('/web/') ? path.substring(5) : path;
    final assetPath = '$_assetPrefix/$fileName';
    final data = await rootBundle.load(assetPath).timeout(
          const Duration(seconds: 5),
        );
    final mime = _mimeType(fileName);
    request.response.headers.contentType = ContentType.parse(mime);
    request.response.add(data.buffer.asUint8List());
    await request.response.close();
    _log('serve /$fileName (${data.lengthInBytes} bytes)');
    // rootBundle.load 对缺失资源抛异常，走 catch 兜底 404。
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