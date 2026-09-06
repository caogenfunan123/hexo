import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/repo_config.dart';

class PreviewScreen extends StatefulWidget {
  final RepoConfig? activeRepo;
  final String? sitePreviewUrl;

  const PreviewScreen({super.key, required this.activeRepo, this.sitePreviewUrl});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final TextEditingController _urlCtrl;
  InAppWebViewController? _webCtrl;
  PullToRefreshController? _pullToRefresh;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _webviewFailed = false;
  String? _failReason;
  Timer? _loadTimeout;
  bool _everStarted = false;

  /// 初始 URL 优先级：
  /// 1. 设置中的站点预览 URL（settings.sitePreviewUrl）
  /// 2. 当前仓库的 siteUrl
  /// 仅放行 http/https，非法时返回空串不加载
  String get _initialUrl => _sanitizeUrl(widget.sitePreviewUrl?.isNotEmpty == true
          ? widget.sitePreviewUrl!
          : (widget.activeRepo?.siteUrl.isNotEmpty == true
              ? widget.activeRepo!.siteUrl
              : '')) ??
      '';

  @override
  void initState() {
    super.initState();
    final url = _initialUrl;
    _urlCtrl = TextEditingController(text: url);
    _pullToRefresh = PullToRefreshController(
      onRefresh: () async {
        if (_loading) {
          _pullToRefresh?.endRefreshing();
          return;
        }
        _webCtrl?.reload();
      },
    );
    if (url.isNotEmpty) {
      // WebView2 缺失或加载静默失败时，超时后给出兜底提示
      _loadTimeout = Timer(const Duration(seconds: 15), () {
        if (!mounted || _webviewFailed || !_everStarted) return;
        setState(() {
          _webviewFailed = true;
          _failReason = '加载超时，可能是 WebView2 运行环境未安装';
        });
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    _urlCtrl.dispose();
    _pullToRefresh?.dispose();
    _webCtrl?.dispose();
    super.dispose();
  }

  /// 校验 URL 是否为可加载的 http/https 地址，返回规范化后的 URL；非法返回 null
  String? _sanitizeUrl(String raw) {
    var candidate = raw.trim();
    if (candidate.isEmpty) return null;
    if (!candidate.startsWith('http://') && !candidate.startsWith('https://')) {
      candidate = 'https://$candidate';
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.isAbsolute || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return candidate;
  }

  void _loadUrl(String text) {
    final candidate = _sanitizeUrl(text);
    if (candidate == null) {
      _showSnack('无效的网址');
      return;
    }
    _urlCtrl.text = candidate;
    _webCtrl?.loadUrl(
      urlRequest: URLRequest(url: WebUri(candidate)),
    );
    FocusScope.of(context).unfocus();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final url = _initialUrl;
    return Column(
      children: [
        // URL bar
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: _canGoBack ? () => _webCtrl?.goBack() : null,
              style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36)),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 20),
              onPressed: _canGoForward ? () => _webCtrl?.goForward() : null,
              style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36)),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => _webCtrl?.reload(),
              style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) => _loadUrl(_urlCtrl.text),
                  keyboardType: TextInputType.url,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 20, color: Color(0xFF0EA5E9)),
              onPressed: () => _loadUrl(_urlCtrl.text),
              style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36)),
            ),
          ]),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: url.isEmpty ? null : URLRequest(url: WebUri(url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              supportZoom: false,
              useShouldOverrideUrlLoading: false,
              mediaPlaybackRequiresUserGesture: false,
            ),
            onWebViewCreated: (controller) {
              _webCtrl = controller;
              _everStarted = true;
            },
            onLoadStart: (controller, url) {
              if (!mounted) return;
              _loadTimeout?.cancel();
              setState(() {
                _webviewFailed = false;
                _loading = true;
                _urlCtrl.text = url?.toString() ?? '';
              });
            },
            onLoadStop: (controller, url) async {
              if (!mounted) return;
              final canBack = await controller.canGoBack();
              final canForward = await controller.canGoForward();
              setState(() {
                _loading = false;
                _webviewFailed = false;
                _canGoBack = canBack;
                _canGoForward = canForward;
                _urlCtrl.text = url?.toString() ?? _urlCtrl.text;
              });
            },
            onReceivedError: (controller, request, error) {
              if (!mounted) return;
              _loadTimeout?.cancel();
              setState(() {
                _loading = false;
                _webviewFailed = true;
                _failReason = error.description;
              });
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri != null) {
                _urlCtrl.text = uri.toString();
                // 仅放行 http/https，阻止 file/data/javascript 等危险 scheme 注入
                if (uri.scheme != 'http' && uri.scheme != 'https') {
                  _showSnack('已阻止非 http/https 链接: ${uri.scheme}');
                  return NavigationActionPolicy.CANCEL;
                }
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
        ),
        if (_webviewFailed) _buildFallback(),
      ],
    );
  }

  /// WebView2 不可用或加载失败时的兜底界面
  Widget _buildFallback() {
    final currentUrl = _sanitizeUrl(_urlCtrl.text) ?? _initialUrl;
    return Expanded(
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.public_off, size: 48, color: Color(0xFF94A3B8)),
              const SizedBox(height: 12),
              const Text(
                '内嵌预览不可用',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _failReason ?? 'WebView2 运行环境可能未安装',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('在浏览器打开'),
                    onPressed: () => _openExternal(currentUrl),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重试'),
                    onPressed: () {
                      setState(() {
                        _webviewFailed = false;
                        _loading = true;
                      });
                      if (_webCtrl != null) {
                        _webCtrl!.reload();
                      } else if (currentUrl.isNotEmpty) {
                        _loadUrl(currentUrl);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _showSnack('无效的网址');
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _showSnack('无法打开浏览器');
    }
  }
}
