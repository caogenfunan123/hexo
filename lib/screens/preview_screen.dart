import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/repo_config.dart';

class PreviewScreen extends StatefulWidget {
  final RepoConfig? activeRepo;

  const PreviewScreen({super.key, required this.activeRepo});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final TextEditingController _urlCtrl;
  late WebViewController _webCtrl;
  bool _loading = true;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.activeRepo?.siteUrl ?? 'https://caogenfunan.me/';
    _urlCtrl = TextEditingController(text: _currentUrl);
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
      ))
      ..loadRequest(Uri.parse(_currentUrl));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _navigate() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    _currentUrl = url;
    _webCtrl.loadRequest(Uri.parse(url));
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // URL bar
        Container(
          padding: const EdgeInsets.all(10),
          color: Colors.white,
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () => _webCtrl.goBack(),
              style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36)),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 20),
              onPressed: () => _webCtrl.goForward(),
              style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36)),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => _webCtrl.reload(),
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
                  onSubmitted: (_) => _navigate(),
                  keyboardType: TextInputType.url,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 20, color: Color(0xFF0EA5E9)),
              onPressed: _navigate,
              style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36)),
            ),
          ]),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: WebViewWidget(controller: _webCtrl)),
      ],
    );
  }
}