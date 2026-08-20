import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../core/markdown/markdown_preview_builder.dart';
import '../services/local_asset_server.dart';
import '../services/preview_debug_store.dart';

/// 基于 WebView 的 Markdown 渲染预览组件（支持 Mermaid 与 KaTeX 公式）。
///
/// 加载策略：
/// - 非 Web 平台：启动本地 HTTP 服务器（`LocalAssetServer`），WebView 通过
///   `initialUrlRequest` 加载 `http://127.0.0.1:18080/preview.html`。HTML
///   只有 ~3KB,JS/CSS/内容通过 HTTP 加载，完全不经过 MethodChannel，
///   避免 Android Binder 事务上限导致卡死。内容更新时通过
///   `evaluateJavascript('refreshContent()')`（小指令）触发 JS 重新
///   `fetch('/content')`。
/// - Web 平台：无 Binder 限制，保留内联资源方式。
/// - Linux 桌面端：不支持 WebView，降级为 `flutter_markdown` 静态渲染。
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
  late Future<void> _initFuture;
  String _lastRenderedMarkdown = '';
  String? _inlineHtml;
  bool _serverFailed = false;
  bool _webViewError = false;

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
    _initFuture = _initPreview();
    _wireDebugLog();
  }

  void _wireDebugLog() {
    if (kIsWeb) return;
    LocalAssetServer.instance.onLog = (line) {
      PreviewDebugStore.instance.log('server', line);
    };
  }

  Future<void> _initPreview() async {
    if (kIsWeb) {
      _inlineHtml = await _buildHtmlInline(widget.markdown);
      return;
    }
    final ok = await LocalAssetServer.instance.ensureStarted();
    if (!ok) {
      _serverFailed = true;
      return;
    }
    LocalAssetServer.instance.updateContent(
      MarkdownPreviewBuilder.buildBody(widget.markdown),
    );
  }

  @override
  void didUpdateWidget(MarkdownPreviewWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contentChanged = oldWidget.markdown != widget.markdown;
    final themeChanged = oldWidget.darkTheme != widget.darkTheme;
    if (!contentChanged && !themeChanged) return;

    if (_webViewSupported && _webCtrl != null) {
      if (themeChanged) {
        _reloadFullPage();
      } else if (contentChanged) {
        _scheduleUpdate();
      }
    } else {
      _lastRenderedMarkdown = widget.markdown;
      _initFuture = _initPreview();
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
      if (kIsWeb) {
        try {
          await _webCtrl?.evaluateJavascript(
            source: 'setContent(${jsonEncode(body)})',
          );
        } catch (_) {}
      } else {
        LocalAssetServer.instance.updateContent(body);
        try {
          await _webCtrl?.evaluateJavascript(
            source: 'refreshContent()',
          );
        } catch (_) {}
      }
    });
  }

  Future<void> _reloadFullPage() async {
    _lastRenderedMarkdown = widget.markdown;
    if (!mounted || _webCtrl == null) return;
    try {
      if (kIsWeb) {
        _inlineHtml = await _buildHtmlInline(widget.markdown);
        await _webCtrl?.loadData(
          data: _inlineHtml!,
          mimeType: 'text/html',
          encoding: 'utf8',
          baseUrl: WebUri('about:blank'),
        );
      } else {
        if (_serverFailed) return;
        LocalAssetServer.instance.updateContent(
          MarkdownPreviewBuilder.buildBody(widget.markdown),
        );
        final url = LocalAssetServer.instance.previewUrl +
            (widget.darkTheme ? '?dark=1' : '?dark=0');
        await _webCtrl?.loadUrl(
          urlRequest: URLRequest(url: WebUri(url)),
        );
      }
    } catch (_) {}
  }

  /// Web 平台：内联全部 CSS/JS（无 Binder 限制）。
  Future<String> _buildHtmlInline(String markdown) async {
    final template = await _asset('assets/preview/web/preview_template.html');
    final dark = widget.darkTheme;
    return template
        .replaceAll(
          '<link rel="stylesheet" href="/web/katex-inline.min.css">',
          '<style>${await _asset('assets/preview/web/katex-inline.min.css')}</style>',
        )
        .replaceAll(
          '<link rel="stylesheet" href="/web/highlight-github.css" id="hl-css">',
          '<style>${await _asset(dark ? 'assets/preview/web/highlight-github-dark.css' : 'assets/preview/web/highlight-github.css')}</style>',
        )
        .replaceAll(
          '<script src="/web/katex.min.js"></script>',
          '<script>${await _asset('assets/preview/web/katex.min.js')}</script>',
        )
        .replaceAll(
          '<script src="/web/auto-render.min.js"></script>',
          '<script>${await _asset('assets/preview/web/auto-render.min.js')}</script>',
        )
        .replaceAll(
          '<script src="/web/highlight.min.js"></script>',
          '<script>${await _asset('assets/preview/web/highlight.min.js')}</script>',
        )
        .replaceAll(
          '<script src="/web/languages-dart.min.js"></script>',
          '<script>${await _asset('assets/preview/web/languages-dart.min.js')}</script>',
        )
        .replaceAll(
          '<script src="/web/mermaid.min.js"></script>',
          '<script>${await _asset('assets/preview/web/mermaid.min.js')}</script>',
        )
        .replaceAll(
          'var _dark = _params.get(\'dark\') === \'1\';',
          'var _dark = ${dark ? 'true' : 'false'};',
        )
        .replaceAll(
          '<div id="content"></div>',
          '<div id="content">${MarkdownPreviewBuilder.buildBody(markdown)}</div>',
        );
  }

  Future<String> _asset(String name) {
    return _assetCache.putIfAbsent(name, () => rootBundle.loadString(name));
  }

  @override
  Widget build(BuildContext context) {
    if (!_webViewSupported) {
      return _buildFallback();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: FutureBuilder<void>(
            future: _initFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              if (kIsWeb) {
                if (_inlineHtml == null) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                return _buildWebView(
                  initialData: InAppWebViewInitialData(
                    data: _inlineHtml!,
                    mimeType: 'text/html',
                    encoding: 'utf8',
                    baseUrl: WebUri('about:blank'),
                  ),
                );
              }
              if (_serverFailed) {
                return _buildFallback();
              }
              if (_webViewError) {
                return _buildFallback();
              }
              final url = LocalAssetServer.instance.previewUrl +
                  (widget.darkTheme ? '?dark=1' : '?dark=0');
              return _buildWebView(
                initialUrlRequest: URLRequest(url: WebUri(url)),
              );
            },
          ),
        ),
        if (!kIsWeb)
          Positioned(
            left: 8,
            bottom: 8,
            child: _DebugLogButton(
              title: '预览排错',
              onPressed: () => _showDebugLog(context),
            ),
          ),
      ],
    );
  }

  void _showDebugLog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetCtx) {
        return _DebugLogSheet(
          logs: PreviewDebugStore.instance.entries,
          onCopy: () {
            final text = PreviewDebugStore.instance.export();
            if (text.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                const SnackBar(content: Text('日志已复制')),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildWebView({InAppWebViewInitialData? initialData, URLRequest? initialUrlRequest}) {
    return InAppWebView(
      initialData: initialData,
      initialUrlRequest: initialUrlRequest,
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
      onReceivedError: (controller, request, error) {
        PreviewDebugStore.instance.log(
          'webview',
          'onReceivedError type=${error.type} desc=${error.description} url=${request.url}',
          level: LogLevel.error,
        );
        if (!mounted) return;
        setState(() => _webViewError = true);
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        PreviewDebugStore.instance.log(
          'webview',
          'onReceivedHttpError status=${errorResponse.statusCode} url=${request.url}',
          level: LogLevel.error,
        );
        if (!mounted) return;
        setState(() => _webViewError = true);
      },
      onConsoleMessage: (controller, consoleMessage) {
        _handleConsoleMessage(consoleMessage);
      },
      onProgressChanged: (controller, progress) {
        if (progress >= 100) {
          PreviewDebugStore.instance.log(
            'webview',
            'onProgressChanged 100% pageLoaded',
          );
        }
      },
    );
  }

  String _levelName(ConsoleMessageLevel level) {
    if (level == ConsoleMessageLevel.DEBUG) return 'debug';
    if (level == ConsoleMessageLevel.ERROR) return 'error';
    if (level == ConsoleMessageLevel.LOG) return 'log';
    if (level == ConsoleMessageLevel.WARNING) return 'warn';
    if (level == ConsoleMessageLevel.TIP) return 'tip';
    return 'unknown';
  }

  void _handleConsoleMessage(ConsoleMessage m) {
    PreviewDebugStore.instance.log(
      'js',
      '${_levelName(m.messageLevel)}: ${m.message}',
      level: (m.messageLevel == ConsoleMessageLevel.ERROR ||
              m.messageLevel == ConsoleMessageLevel.WARNING)
          ? LogLevel.error
          : LogLevel.info,
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
}

/// 预览页左下角排错按钮。
class _DebugLogButton extends StatelessWidget {
  const _DebugLogButton({required this.title, required this.onPressed});

  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.85),
      elevation: 2,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bug_report, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 排错日志底部弹层。
class _DebugLogSheet extends StatefulWidget {
  const _DebugLogSheet({required this.logs, required this.onCopy});

  final List<LogEntry> logs;
  final VoidCallback onCopy;

  @override
  State<_DebugLogSheet> createState() => _DebugLogSheetState();
}

class _DebugLogSheetState extends State<_DebugLogSheet> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = PreviewDebugStore.instance.entries.reversed.toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  '预览调试日志',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: widget.onCopy,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('复制日志'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    PreviewDebugStore.instance.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: '清空日志',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                height: 360,
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: entries.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无日志',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final e = entries[index];
                          final t = e.timestamp;
                          final ts =
                              '${t.hour}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';
                          return SelectableText(
                            '[$ts][${e.level.name}][${e.source}] ${e.message}',
                            style: TextStyle(
                              color: e.level == LogLevel.error
                                  ? const Color(0xFFEF5350)
                                  : const Color(0xFFBDBDBD),
                              fontSize: 11,
                              fontFamily: 'monospace',
                              height: 1.5,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}