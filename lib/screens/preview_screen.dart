import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
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

  String get _initialUrl => widget.activeRepo?.siteUrl.isNotEmpty == true
      ? widget.activeRepo!.siteUrl
      : (widget.sitePreviewUrl?.isNotEmpty == true ? widget.sitePreviewUrl! : '');

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
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _pullToRefresh?.dispose();
    _webCtrl?.dispose();
    super.dispose();
  }

  void _loadUrl(String text) {
    final input = text.trim();
    if (input.isEmpty) return;
    // 未带协议时自动补全 https
    var candidate = input;
    if (!candidate.startsWith('http://') && !candidate.startsWith('https://')) {
      candidate = 'https://$candidate';
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.isAbsolute || (uri.scheme != 'http' && uri.scheme != 'https')) {
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
            onWebViewCreated: (controller) => _webCtrl = controller,
            onLoadStart: (controller, url) {
              if (!mounted) return;
              setState(() {
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
                _canGoBack = canBack;
                _canGoForward = canForward;
                _urlCtrl.text = url?.toString() ?? _urlCtrl.text;
              });
            },
            onReceivedError: (controller, request, error) {
              if (!mounted) return;
              setState(() => _loading = false);
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri != null) {
                _urlCtrl.text = uri.toString();
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
        ),
      ],
    );
  }
}
