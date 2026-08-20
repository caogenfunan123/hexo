import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 本地资产服务：基于 `InAppLocalhostServer` 在应用内启动 HTTP 服务器，
/// 从 Flutter asset bundle 直接提供 `assets/preview/` 目录下的静态资源。
///
/// 用于替代「把 4MB 的 mermaid / KaTeX / highlight.js 内联进 HTML」的做法，
/// 避免 Android WebView 通过 MethodChannel 传输大数据（Binder 事务 ~1MB 上限）
/// 导致 `TransactionTooLargeException` 卡死。
///
/// - Android / iOS / macOS 使用平台原生实现；
/// - Windows / Linux 使用 `DefaultInAppLocalhostServer`（基于 `dart:io`）；
/// - Web 平台不支持本地 HTTP 服务器，直接返回 Web 端内联 URL（由调用方处理）。
class LocalAssetServer {
  LocalAssetServer._();

  static final LocalAssetServer _instance = LocalAssetServer._();

  /// 全局单例，供所有预览组件共享一个端口。
  static LocalAssetServer get instance => _instance;

  static const int port = 18080;

  InAppLocalhostServer? _server;
  bool _started = false;

  /// 基地址，例如 `http://localhost:18080`。
  /// Web 平台返回空字符串，调用方需自行内联资源。
  String get baseUrl {
    if (kIsWeb) return '';
    return 'http://localhost:$port';
  }

  /// 确保本地服务器已启动（幂等）。
  Future<void> ensureStarted() async {
    if (_started || kIsWeb) return;
    _server = InAppLocalhostServer(
      port: port,
      documentRoot: 'assets/preview/',
    );
    await _server!.start();
    _started = true;
  }

  /// 关闭本地服务器。
  Future<void> shutdown() async {
    if (_server != null) {
      await _server!.close();
    }
    _server = null;
    _started = false;
  }
}