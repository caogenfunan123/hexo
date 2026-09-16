import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 手机端 WebView 真·所见即所得编辑器（路线一：TipTap/ProseMirror）。
///
/// 为什么用 WebView：中文输入法由系统 WebView 处理（与浏览器打字一致地稳），
/// 渲染是增量 DOM 更新（无整页重排卡顿），编辑引擎是业界最成熟的 ProseMirror。
/// 编辑面 v1 边界：数学/mermaid 保持代码文本态（渲染由分屏预览/阅读页负责）。
///
/// 数据流（唯一事实源是 contentCtrl）：
/// - 加载：contentCtrl 拆出 frontmatter 后，正文 markdown 经 marked 转 HTML
///   灌入 TipTap；
/// - 编辑：JS 侧防抖 400ms → getHTML → turndown(GFM) 转 markdown →
///   callHandler 回 Dart → 写回 contentCtrl（含 frontmatter 前置）→
///   onContentChanged（未保存标记 + 自动保存链路）；
/// - 外部改动（AI/图床/切文章）：监听 contentCtrl，正文与编辑器当前内容
///   不一致时 setMarkdown 推回 WebView（回环由 _lastKnownMarkdown 比对挡住）。
///
/// 加载策略：editor.min.js（约 416KB）**全平台内联**进 initialData HTML——
/// 远低于安卓 Binder 1MB 事务上限，不依赖任何虚拟域/子资源请求，
/// 从根上排除「脚本 404 → 编辑器空白」的失败类（曾因此报加载失败）。
/// KaTeX（css+js 共 642KB，超限）在 onLoadStop 后经 IPC 注入，
/// 每步带 8s 超时：渲染进程卡死时要么降级 math-raw，要么显式 fatal，
/// 绝不会出现无 init、无 fatal 的静默空白。
/// WebView 失败时回调 onFatalError(reason)，宿主自动退回源码编辑模式。
class WysiwygWebViewEditor extends StatefulWidget {
  const WysiwygWebViewEditor({
    super.key,
    required this.contentCtrl,
    required this.dark,
    required this.onContentChanged,
    this.onFatalError,
  });

  final TextEditingController contentCtrl;
  final bool dark;
  final VoidCallback onContentChanged;

  /// WebView 不可用（加载失败）时回调，宿主应退回源码模式
  final VoidCallback? onFatalError;

  @override
  State<WysiwygWebViewEditor> createState() => WysiwygWebViewEditorState();
}

class WysiwygWebViewEditorState extends State<WysiwygWebViewEditor> {
  static const String _assetDomain = 'appassets.androidplatform.net';
  static final RegExp _frontmatterRegex =
      RegExp('^' + r'-{3}[\s\S]*?-{3}' + r'\r?\n?');

  InAppWebViewController? _webCtrl;
  bool _ready = false;
  bool _fatal = false;
  bool _editorIsWriting = false;
  String _frontmatter = '';
  String _lastKnownBody = '';
  String? _lastJsError;
  late Future<String> _htmlFuture;

  /// 仅安卓给 WebView 配虚拟域 baseUrl + AssetLoader（https 安全上下文 +
  /// 兜住零星绝对路径请求 404，不落到真实网络）；KaTeX 已不依赖它加载
  bool get _useAssetLoader =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    final m = _frontmatterRegex.firstMatch(widget.contentCtrl.text);
    _frontmatter = m?.group(0) ?? '';
    _lastKnownBody = widget.contentCtrl.text.substring(_frontmatter.length);
    widget.contentCtrl.addListener(_onExternalChanged);
    _htmlFuture = _buildHtml();
  }

  @override
  void didUpdateWidget(covariant WysiwygWebViewEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentCtrl != widget.contentCtrl) {
      oldWidget.contentCtrl.removeListener(_onExternalChanged);
      widget.contentCtrl.addListener(_onExternalChanged);
      _syncFrontmatterAndBody();
      _pushIfReady();
    }
    // dark 变化走 build 的 ValueKey 整体重建（元素重建，不会进本方法），
    // init 时已带 dark 参数，无需单独 setDark
  }

  @override
  void dispose() {
    widget.contentCtrl.removeListener(_onExternalChanged);
    _webCtrl?.dispose();
    super.dispose();
  }

  void _syncFrontmatterAndBody() {
    final m = _frontmatterRegex.firstMatch(widget.contentCtrl.text);
    _frontmatter = m?.group(0) ?? '';
    _lastKnownBody = widget.contentCtrl.text.substring(_frontmatter.length);
  }

  /// 外部改动（AI 改写/图床插入/切文章）：推给 WebView。
  /// 装载完成前也要更新基线（否则 init 会用陈旧内容装载，
  /// 编辑器一打字就把装载期间的外部新内容覆盖回去）
  void _onExternalChanged() {
    if (_editorIsWriting) return;
    final m = _frontmatterRegex.firstMatch(widget.contentCtrl.text);
    final front = m?.group(0) ?? '';
    final body = widget.contentCtrl.text.substring(front.length);
    if (body == _lastKnownBody && front == _frontmatter) return;
    _frontmatter = front;
    _lastKnownBody = body;
    if (!_ready) return;
    _webCtrl?.evaluateJavascript(
      source: 'WysiwygBridge.setMarkdown(${jsonEncode(body)})',
    );
  }

  void _pushIfReady() {
    if (!_ready) return;
    _webCtrl?.evaluateJavascript(
      source: 'WysiwygBridge.setMarkdown(${jsonEncode(_lastKnownBody)})',
    );
  }

  /// JS → Dart：编辑器防抖后的 markdown
  void _onEditorMarkdown(dynamic args) {
    final md = args is List && args.isNotEmpty ? args.first as String? : null;
    if (md == null || !_ready) return;
    if (md == _lastKnownBody) return;
    _lastKnownBody = md;
    _editorIsWriting = true;
    try {
      widget.contentCtrl.text = _frontmatter + md;
    } finally {
      _editorIsWriting = false;
    }
    widget.onContentChanged();
  }

  /// 主动把 WebView 内最新 markdown 拉回 contentCtrl（App 转后台/切模式/
  /// 切文章前调用）：JS 侧还有 400ms 防抖窗口，那里的输入只能从这里救回。
  /// 返回是否发生了回写。
  Future<bool> flushToController() async {
    if (!_ready || _webCtrl == null || _fatal) return false;
    final dynamic res =
        await _webCtrl!.evaluateJavascript(source: 'WysiwygBridge.getMarkdown()');
    final md = res is String ? res : null;
    if (md == null || md == _lastKnownBody) return false;
    _lastKnownBody = md;
    _editorIsWriting = true;
    try {
      widget.contentCtrl.text = _frontmatter + md;
    } finally {
      _editorIsWriting = false;
    }
    widget.onContentChanged();
    return true;
  }

  /// 模板 + 编辑器 bundle 内联；KaTeX 不进 HTML，统一 onLoadStop IPC 注入。
  /// （安卓 initialData 走 Binder，上限 1MB：编辑器包 410KB 内联安全，
  /// KaTeX css+js 642KB 超限只能后注入；iOS/桌面无此限制，但同样走注入，
  /// 全平台单一路径。安卓曾用 WebViewAssetLoader 虚拟域外链，但 androidx
  /// AssetsPathHandler 以安卓资产根为基准、Flutter 资产带 flutter_assets/
  /// 前缀，必然 404（848786f 历史），且外链请求一旦落到真实网络会卡死
  /// load 事件→onLoadStop 永不触发→无 fatal 的纯空白，彻底弃用。）
  Future<String> _buildHtml() async {
    final template =
        await rootBundle.loadString('assets/wysiwyg/web/editor.template.html');
    final js = await rootBundle.loadString('assets/wysiwyg/web/editor.min.js');
    final html = template.replaceAll(
      '<script src="__EDITOR_JS__"></script>',
      '<script>${js.replaceAll('</script>', '<\\/script>')}</script>',
    );
    return html
        .replaceAll('__KATEX_CSS__', '')
        .replaceAll('__KATEX_JS__', '');
  }

  @override
  Widget build(BuildContext context) {
    if (_fatal) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '所见即所得加载失败，已可切回源码编辑\n(${_lastJsError ?? '未知原因'})',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return FutureBuilder<String>(
      future: _htmlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          debugPrint('WysiwygWebView: html build failed: ${snapshot.error}');
          _lastJsError = 'HTML构建: ${snapshot.error}';
          WidgetsBinding.instance.addPostFrameCallback((_) => _reportFatal());
          return const SizedBox.shrink();
        }
        final html = snapshot.data!;
        return InAppWebView(
          key: ValueKey('wysiwyg-webview-${widget.dark}'),
          initialData: InAppWebViewInitialData(
            data: html,
            mimeType: 'text/html',
            encoding: 'utf8',
            baseUrl: WebUri(
                _useAssetLoader ? 'https://$_assetDomain/' : 'about:blank'),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            transparentBackground: true,
            supportZoom: false,
            disableContextMenu: false,
            webViewAssetLoader: _useAssetLoader
                ? WebViewAssetLoader(
                    domain: _assetDomain,
                    pathHandlers: [
                      AssetsPathHandler(path: '/assets/'),
                    ],
                  )
                : null,
          ),
          onWebViewCreated: (ctrl) {
            _webCtrl = ctrl;
            ctrl.addJavaScriptHandler(
              handlerName: 'wysiwygMarkdown',
              callback: _onEditorMarkdown,
            );
          },
          onConsoleMessage: (ctrl, msg) {
            if (msg.messageLevel == ConsoleMessageLevel.ERROR) {
              debugPrint('WysiwygWebView console: ${msg.message}');
              _lastJsError = msg.message;
            }
          },
          onLoadStop: (ctrl, url) async {
            // KaTeX 统一经 IPC 注入（HTML 内无任何外链，load 不依赖网络）：
            // css 367KB / js 275KB，单次调用均低于 1MB Binder 限制，赶在
            // init 前完成，公式节点首次渲染即有 KaTeX。
            // 每步都带超时：WebView 渲染进程卡死时 evaluateJavascript 永不
            // 返回，若无超时整个 onLoadStop 悬挂→无 init、无 fatal 的纯空白。
            // window.katex 探测天然兼容 load 重复触发与 dark 重建的新 WebView。
            // 独立 try：注入失败只降级为 latex 原文显示（JS 侧 math-raw），
            // 绝不能冒泡到 init 的 fatal 路径把整个编辑器判死
            try {
              final hasKatex = await _evalTimed(
                ctrl,
                '!!window.katex',
                stage: 'katex-probe',
              );
              if (hasKatex == null) {
                // 探测无响应（渲染进程卡死/IPC 异常）：继续注入只会连环
                // 超时白等 20 多秒，直接判死给用户可见的失败态
                debugPrint('WysiwygWebView: katex probe no response');
                _lastJsError = 'KaTeX 探测无响应，WebView 可能已卡死';
                _reportFatal();
                return;
              }
              if (hasKatex != true) {
                final katexCss = await rootBundle
                    .loadString('assets/wysiwyg/web/katex.min.css');
                final katexJs = await rootBundle
                    .loadString('assets/wysiwyg/web/katex.min.js');
                await _evalTimed(
                  ctrl,
                  "var s=document.createElement('style');s.textContent=${jsonEncode(katexCss)};document.head.appendChild(s);",
                  stage: 'katex-css',
                );
                await _evalTimed(ctrl, katexJs, stage: 'katex-js');
              }
            } catch (e) {
              debugPrint('WysiwygWebView: katex inject fallback failed: $e');
            }
            // dark 切换会因 ValueKey 重建 WebView：异步窗口期后旧续体
            // 继续操作已销毁的 controller 会误报 fatal，直接作废
            if (!mounted || _webCtrl != ctrl) return;
            try {
              // 安卓上 JS 抛错（如 WysiwygBridge 未定义）时 evaluateJavascript
              // 返回 null 而非抛 PlatformException，必须用返回值确认 init 成功
              final ok = await _evalTimed(
                ctrl,
                'WysiwygBridge.init({content: ${jsonEncode(_lastKnownBody)}, dark: ${widget.dark}})',
                stage: 'init',
              );
              if (!mounted || _webCtrl != ctrl) return;
              if (ok == true) {
                if (mounted) setState(() => _ready = true);
              } else {
                debugPrint('WysiwygWebView: init not confirmed: $ok');
                _lastJsError =
                    'init 未确认（返回 $ok）${_lastJsError != null ? ' / $_lastJsError' : ''}';
                _reportFatal();
              }
            } catch (e) {
              if (!mounted || _webCtrl != ctrl) return;
              debugPrint('WysiwygWebView: init failed: $e');
              _lastJsError = 'init: $e${_lastJsError != null ? ' / $_lastJsError' : ''}';
              _reportFatal();
            }
          },
          onReceivedError: (ctrl, request, error) {
            debugPrint(
                'WysiwygWebView receivedError: ${error.description} ${request.url}');
            // 只把主框架加载失败当致命（favicon 等子资源 404 不影响编辑器）
            if (request.isForMainFrame == true) {
              _lastJsError = '${error.description}';
              _reportFatal();
            }
          },
        );
      },
    );
  }

  /// 带超时的 evaluateJavascript：渲染进程卡死/IPC 挂起时不会悬挂调用方。
  /// 超时返回 null（katex 步骤降级、init 步骤走 fatal），stage 用于日志定位。
  Future<Object?> _evalTimed(
    InAppWebViewController ctrl,
    String source, {
    required String stage,
  }) {
    return ctrl
        .evaluateJavascript(source: source)
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            debugPrint('WysiwygWebView: eval timeout at $stage');
            _lastJsError = '$stage 求值超时';
            return null;
          },
        );
  }

  void _reportFatal() {
    if (_fatal) return;
    // 组件已被移除（切文章/切模式）时宿主无需再感知致命错误，
    // 继续回调会让宿主对已不存在的编辑器切回源码模式并弹误导性 toast
    if (!mounted) return;
    _fatal = true;
    setState(() {});
    widget.onFatalError?.call();
  }
}
