import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../core/markdown/markdown_preview_builder.dart';
import '../services/preview_debug_store.dart';

/// 基于 WebView 的 Markdown 渲染预览组件（支持 Mermaid 与 KaTeX 公式）。
///
/// 资源加载策略：
/// - Android：使用 `WebViewAssetLoader` 把 `assets/preview/web/` 通过
///   `https://appassets.androidplatform.net/assets/*` 虚拟域原生提供给
///   WebView。JS/CSS 由系统 WebView 网络栈直接读 APK assets，全程不经过
///   MethodChannel / Binder，避免大负载卡死，也无本地端口与明文流量问题。
/// - iOS / Web / 桌面：无 Binder 限制（iOS 亦无 1MB 限制），将 JS/CSS
///   直接内联进 HTML，通过 `initialData` 加载。
///
/// 正文始终在构建 HTML 时内联进 `<div id="content">`，首屏渲染不依赖任何
/// 网络请求；内容更新通过 `evaluateJavascript('setContent(...)')`。
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

  /// Android 原生虚拟域（WebViewAssetLoader），只能映射 `/assets/` 前缀。
  static const String _assetDomain = 'appassets.androidplatform.net';

  InAppWebViewController? _webCtrl;
  Timer? _debounce;
  late Future<void> _initFuture;
  String _lastRenderedMarkdown = '';
  String? _html;
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

  bool get _useAssetLoader =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _lastRenderedMarkdown = widget.markdown;
    _initFuture = _initPreview();
  }

  Future<void> _initPreview() async {
    _html = await _buildHtml(widget.markdown);
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
      } else {
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

  /// 构建预览 HTML。
  ///
  /// Android 使用 [WebViewAssetLoader]：保留模板中的 `/assets/preview/web/*`
  /// 资源引用，配合 `initialData.baseUrl` 指向虚拟域解析资源；其余平台
  /// 将 JS/CSS 全部内联（避免 Binder 只是 Android 的约束）。
  Future<String> _buildHtml(String markdown) async {
    final template = await _asset('assets/preview/web/preview_template.html');
    final dark = widget.darkTheme;
    var html = template
        .replaceAll(
          'var _dark = _params.get(\'dark\') === \'1\';',
          'var _dark = ${dark ? 'true' : 'false'};',
        )
        .replaceAll(
          '<div id="content"></div>',
          '<div id="content">${MarkdownPreviewBuilder.buildBody(markdown)}</div>',
        );
    if (!_useAssetLoader) {
      html = html
          .replaceAll(
            '<link rel="stylesheet" href="/assets/preview/web/katex-inline.min.css">',
            '<style>${await _asset('assets/preview/web/katex-inline.min.css')}</style>',
          )
          .replaceAll(
            '<link rel="stylesheet" href="/assets/preview/web/highlight-github.css" id="hl-css">',
            '<style>${await _asset(dark ? 'assets/preview/web/highlight-github-dark.css' : 'assets/preview/web/highlight-github.css')}</style>',
          )
          .replaceAll(
            '<script src="/assets/preview/web/katex.min.js"></script>',
            '<script>${await _asset('assets/preview/web/katex.min.js')}</script>',
          )
          .replaceAll(
            '<script src="/assets/preview/web/auto-render.min.js"></script>',
            '<script>${await _asset('assets/preview/web/auto-render.min.js')}</script>',
          )
          .replaceAll(
            '<script src="/assets/preview/web/highlight.min.js"></script>',
            '<script>${await _asset('assets/preview/web/highlight.min.js')}</script>',
          )
          .replaceAll(
            '<script src="/assets/preview/web/languages-dart.min.js"></script>',
            '<script>${await _asset('assets/preview/web/languages-dart.min.js')}</script>',
          )
          .replaceAll(
            '<script src="/assets/preview/web/mermaid.min.js"></script>',
            '<script>${await _asset('assets/preview/web/mermaid.min.js')}</script>',
          );
    }
    return html;
  }

  Future<String> _asset(String name) {
    return _assetCache.putIfAbsent(name, () => rootBundle.loadString(name));
  }

  void _scheduleUpdate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted || _webCtrl == null) return;
      _setContent(widget.markdown);
    });
  }

  void _setContent(String markdown) {
    if (!mounted || _webCtrl == null) return;
    if (markdown == _lastRenderedMarkdown) return;
    _lastRenderedMarkdown = markdown;
    final body = MarkdownPreviewBuilder.buildBody(markdown);
    PreviewDebugStore.instance.log(
      'widget',
      'setContent body=${body.length} chars',
    );
    try {
      _webCtrl?.evaluateJavascript(
        source: 'setContent(${jsonEncode(body)})',
      );
    } catch (e) {
      PreviewDebugStore.instance.log(
        'widget',
        'evaluateJavascript setContent failed: $e',
        level: LogLevel.error,
      );
      _reloadFullPage();
    }
  }

  Future<void> _reloadFullPage() async {
    _lastRenderedMarkdown = widget.markdown;
    if (!mounted || _webCtrl == null || _html == null) return;
    PreviewDebugStore.instance.log(
      'widget',
      'reloadFullPage theme=${widget.darkTheme}',
    );
    final html = await _buildHtml(widget.markdown);
    if (!mounted) return;
    try {
      await _webCtrl?.loadData(
        data: html,
        mimeType: 'text/html',
        encoding: 'utf8',
        baseUrl: WebUri(
          _useAssetLoader ? 'https://$_assetDomain/' : 'about:blank',
        ),
      );
    } catch (e) {
      PreviewDebugStore.instance.log(
        'widget',
        'loadData failed: $e',
        level: LogLevel.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_webViewSupported) {
      return _buildFallback();
    }
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        if (_webViewError) {
          return _buildFallback();
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildWebView(
              initialData: InAppWebViewInitialData(
                data: _html!,
                mimeType: 'text/html',
                encoding: 'utf8',
                baseUrl: WebUri(
                  _useAssetLoader ? 'https://$_assetDomain/' : 'about:blank',
                ),
              ),
            ),
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
      },
    );
  }

  Widget _buildWebView({required InAppWebViewInitialData initialData}) {
    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      domStorageEnabled: true,
      supportZoom: false,
      transparentBackground: false,
      webViewAssetLoader: _useAssetLoader
          ? WebViewAssetLoader(
              domain: _assetDomain,
              pathHandlers: [
                AssetsPathHandler(path: '/assets/'),
              ],
            )
          : null,
    );
    return InAppWebView(
      initialData: initialData,
      initialSettings: settings,
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
        final url = request.url.toString();
        if (url.contains('preview.html')) {
          setState(() => _webViewError = true);
        }
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