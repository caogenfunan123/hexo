import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../core/markdown/markdown_preview_builder.dart';
import '../services/local_asset_server.dart';

/// 基于 WebView 的 Markdown 渲染预览组件（支持 Mermaid 与 KaTeX 公式）。
///
/// 通过 `flutter_inappwebview` 6.x 加载本地 HTML：使用 `InAppLocalhostServer`
/// 提供 mermaid.js / KaTeX / highlight.js 等静态资源（非 Web 平台），
/// 避免因内联 ~4MB 的 JS/CSS 通过 MethodChannel 传输触发 Android
/// `TransactionTooLargeException`。Web 端保留内联方式。
/// Linux 桌面端不支持 WebView，自动降级为 `flutter_markdown` 静态渲染。
///
/// 内容变更时组件内部做 200ms 防抖，通过 `setContent` 增量更新页面，
/// 避免整页重载闪烁。
class MarkdownPreviewWebView extends StatefulWidget {
  const MarkdownPreviewWebView({
    super.key,
    required this.markdown,
    this.darkTheme = false,
    this.onOpenLink,
    this.fallbackBuilder,
  });

  final String markdown;
  final bool darkTheme;

  /// 预览中链接被点击时回调（需自行用 url_launcher 等打开）。
  final ValueChanged<String>? onOpenLink;

  /// 不支持 WebView 的平台（如 Linux 桌面端）使用的降级渲染构建器；
  /// 为空时使用 `flutter_markdown` 静态渲染。
  final Widget Function(BuildContext context, String markdown)? fallbackBuilder;

  @override
  State<MarkdownPreviewWebView> createState() =>
      _MarkdownPreviewWebViewState();
}

class _MarkdownPreviewWebViewState extends State<MarkdownPreviewWebView> {
  static final Map<String, Future<String>> _assetCache = {};

  InAppWebViewController? _webCtrl;
  Timer? _debounce;
  late Future<String> _htmlFuture;
  String _lastRenderedMarkdown = '';

  bool get _webViewSupported {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return true;
      default:
        return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _lastRenderedMarkdown = widget.markdown;
    _htmlFuture = _buildHtml(widget.markdown);
  }

  @override
  void didUpdateWidget(MarkdownPreviewWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contentChanged = oldWidget.markdown != widget.markdown;
    final themeChanged = oldWidget.darkTheme != widget.darkTheme;
    if (!contentChanged && !themeChanged) return;

    if (_webViewSupported && _webCtrl != null) {
      if (themeChanged) {
        _reloadFullHtml();
      } else if (contentChanged) {
        _scheduleUpdate();
      }
    } else {
      _lastRenderedMarkdown = widget.markdown;
      _htmlFuture = _buildHtml(widget.markdown);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _webCtrl?.dispose();
    super.dispose();
  }

  void _scheduleUpdate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      if (!mounted || _webCtrl == null) return;
      if (widget.markdown == _lastRenderedMarkdown) return;
      _lastRenderedMarkdown = widget.markdown;
      final body = MarkdownPreviewBuilder.buildBody(widget.markdown);
      try {
        await _webCtrl?.evaluateJavascript(
          source: 'setContent(${jsonEncode(body)})',
        );
      } catch (_) {}
    });
  }

  Future<void> _reloadFullHtml() async {
    _lastRenderedMarkdown = widget.markdown;
    final html = await _buildHtml(widget.markdown);
    if (!mounted || _webCtrl == null) return;
    try {
      await _webCtrl?.loadData(
        data: html,
        mimeType: 'text/html',
        encoding: 'utf8',
        baseUrl: WebUri('about:blank'),
      );
    } catch (_) {}
  }

  Future<String> _buildHtml(String markdown) async {
    if (kIsWeb) {
      return _buildHtmlInline(markdown);
    }
    await LocalAssetServer.instance.ensureStarted();
    return _buildHtmlExternal(markdown);
  }

  /// Web 平台：保留旧的内联方式（无 Binder 限制）。
  Future<String> _buildHtmlInline(String markdown) async {
    final template = await _asset('assets/preview/web/preview_template.html');
    final dark = widget.darkTheme;
    final mermaidTheme = dark ? 'dark' : 'default';
    return template
        .replaceAll('/*__BASE_URL__*/', '')
        .replaceAll(
          '<link rel="stylesheet" href="web/katex-inline.min.css">',
          '<style>${await _asset('assets/preview/web/katex-inline.min.css')}</style>',
        )
        .replaceAll(
          '<link rel="stylesheet" href="web/__HIGHLIGHT_CSS_FILENAME__">',
          '<style>${await _asset(dark ? 'assets/preview/web/highlight-github-dark.css' : 'assets/preview/web/highlight-github.css')}</style>',
        )
        .replaceAll(
          '<script src="web/katex.min.js"></script>',
          '<script>${await _asset('assets/preview/web/katex.min.js')}</script>',
        )
        .replaceAll(
          '<script src="web/auto-render.min.js"></script>',
          '<script>${await _asset('assets/preview/web/auto-render.min.js')}</script>',
        )
        .replaceAll(
          '<script src="web/highlight.min.js"></script>',
          '<script>${await _asset('assets/preview/web/highlight.min.js')}</script>',
        )
        .replaceAll(
          '<script src="web/languages-dart.min.js"></script>',
          '<script>${await _asset('assets/preview/web/languages-dart.min.js')}</script>',
        )
        .replaceAll(
          '<script src="web/mermaid.min.js"></script>',
          '<script>${await _asset('assets/preview/web/mermaid.min.js')}</script>',
        )
        .replaceAll('/*__BODY_CLASS__*/', dark ? 'theme-dark' : 'theme-light')
        .replaceAll('/*__INIT_JS__*/', _initJs(mermaidTheme))
        .replaceAll('__CONTENT__', MarkdownPreviewBuilder.buildBody(markdown));
  }

  /// 非 Web 平台：使用 `InAppLocalhostServer` 外部引用 JS/CSS。
  Future<String> _buildHtmlExternal(String markdown) async {
    final template = await _asset('assets/preview/web/preview_template.html');
    final dark = widget.darkTheme;
    final mermaidTheme = dark ? 'dark' : 'default';
    final baseUrl = LocalAssetServer.instance.baseUrl;
    return template
        .replaceAll('/*__BASE_URL__*/', baseUrl)
        .replaceAll(
          '/*__HIGHLIGHT_CSS_FILENAME__*/',
          dark ? 'highlight-github-dark.css' : 'highlight-github.css',
        )
        .replaceAll('/*__BODY_CLASS__*/', dark ? 'theme-dark' : 'theme-light')
        .replaceAll('/*__INIT_JS__*/', _initJs(mermaidTheme))
        .replaceAll('__CONTENT__', MarkdownPreviewBuilder.buildBody(markdown));
  }

  Future<String> _asset(String name) {
    return _assetCache.putIfAbsent(name, () => rootBundle.loadString(name));
  }

  @override
  Widget build(BuildContext context) {
    if (!_webViewSupported) {
      return _buildFallback();
    }
    return FutureBuilder<String>(
      future: _htmlFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        return InAppWebView(
          initialData: InAppWebViewInitialData(
            data: snapshot.data!,
            mimeType: 'text/html',
            encoding: 'utf8',
            baseUrl: WebUri('about:blank'),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            supportZoom: false,
            transparentBackground: false,
          ),
          onWebViewCreated: (controller) {
            _webCtrl = controller;
            controller.addJavaScriptHandler(
              handlerName: 'linkHandler',
              callback: (args) {
                final url = args.isNotEmpty ? args.first as String? : null;
                if (url != null && url.isNotEmpty) {
                  widget.onOpenLink?.call(url);
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFallback() {
    if (widget.fallbackBuilder != null) {
      return widget.fallbackBuilder!(context, widget.markdown);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Markdown(
        data: widget.markdown,
        selectable: true,
      ),
    );
  }

  String _initJs(String mermaidTheme) => '''
function renderAll() {
  var el = document.getElementById('content');
  if (!el) return;
  if (window.renderMathInElement) {
    try {
      renderMathInElement(el, {
        delimiters: [
          {left: '\u0024\u0024', right: '\u0024\u0024', display: true},
          {left: '\u0024', right: '\u0024', display: false}
        ],
        throwOnError: false,
        strict: false
      });
    } catch (e) {}
  }
  if (window.hljs) {
    try {
      document.querySelectorAll('pre code').forEach(function (block) {
        hljs.highlightElement(block);
      });
    } catch (e) {}
  }
  if (window.mermaid) {
    try {
      mermaid.initialize({
        startOnLoad: false,
        theme: '$mermaidTheme',
        securityLevel: 'loose',
        fontFamily: 'sans-serif'
      });
      mermaid.run({ nodes: document.querySelectorAll('pre.mermaid') });
    } catch (e) {}
  }
}
function setContent(html) {
  var el = document.getElementById('content');
  if (!el) return;
  el.innerHTML = html;
  renderAll();
}
document.addEventListener('DOMContentLoaded', renderAll);
document.addEventListener('click', function (e) {
  var a = e.target;
  while (a && a.tagName !== 'A') { a = a.parentNode; }
  if (a && a.getAttribute && a.getAttribute('href')) {
    var href = a.getAttribute('href');
    if (window.linkHandler) { window.linkHandler(href); }
  }
}, true);
''';
}