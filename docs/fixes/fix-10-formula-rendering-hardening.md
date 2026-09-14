# 修复10：公式渲染链路加固——安卓 KaTeX 虚拟域兜底 + 预览端 CrNode 报错兜底

日期：2026-09-14
范围：`lib/widgets/wysiwyg_web_editor.dart`、`lib/widgets/safe_math_builders.dart`（新增）、
`markdown_preview_smooth.dart`、`debounced_markdown_preview.dart`、
`lib/mixins/editor_remote_ext.dart`、`lib/main.dart`、`pubspec.yaml`、
`test/preview_render_test.dart`

背景：真所见即所得（WebView TipTap）公式渲染修复后，用户反馈预览端报错
「Build Exception: Unsanitized build exception detected: Unsupported operation:
Temporary node CrNode encountered」。两处修复同属公式渲染链路。

## 问题一：安卓 KaTeX 虚拟域单点依赖

`wysiwyg_web_editor.dart` 在安卓用 WebViewAssetLoader 虚拟域
（`appassets.androidplatform.net`）加载 KaTeX css+js（合计约 642KB，超出
initialData 的 1MB Binder 限制只能外链；仓库历史 commit 848786f 曾因虚拟域
404 弃用过编辑器 bundle 的虚拟域方案）。虚拟域一旦失败，`window.katex`
缺失，公式回落 `math-raw` 显示 latex 原文（可见但无排版）。

修复：`onLoadStop` 中 init 前检测 `!!window.katex`，缺失时经 IPC 注入
rootBundle 读取的 katex.min.css（367KB）与 katex.min.js（275KB）——单次
evaluateJavascript 调用均低于 1MB Binder 限制，赶在编辑器 init 前完成，
公式节点首次渲染即有 KaTeX。注入失败仍保留 latex 原文兜底，编辑器可用。

## 问题二：预览端 flutter_math_fork CrNode 崩溃

预览组件（flutter_smooth_markdown）内部用 flutter_math_fork 渲染公式，
其 LaTeX 解析比 KaTeX JS 严格：`\\`（换行）在数组类环境（aligned/matrix 等）
外会留下 CrNode 临时节点活到构建期，`buildWidget` 抛
`UnsupportedError('Temporary node CrNode encountered.')`，被包内包装为
BuildException 显示成整段报错文本。KaTeX JS 对任意位置的 `\\` 均宽容支持，
所以同一篇文档 WebView 编辑端正常、Flutter 预览端报错。

修复：新增 `lib/widgets/safe_math_builders.dart`——`SafeInlineMathBuilder` /
`SafeBlockMathBuilder` 覆盖默认 `inline_math` / `block_math` builder，
`Math.tex` 传 `onErrorFallback` 回落显示 LaTeX 原文（等宽、继承正文样式），
与 WebView 端 `math-raw` 行为一致。三处 SmoothMarkdown 使用点统一接线
（`markdown_preview_smooth.dart`、`debounced_markdown_preview.dart`、
`editor_remote_ext.dart`）。为此把 flutter_math_fork（0.7.4，原传递依赖）
提升为直接依赖；颜色兜底走 `AppColor.textPrimary` 语义令牌。

## 验证

- jsdom 路径测试 9/9：无 katex → math-raw 原文可见、表格照常渲染、回转不丢；
  有 katex → 正常渲染、无 raw 回落。
- flutter analyze：改档 0 issue。
- flutter test：preview_render_test.dart 新增回归用例——`$$a \\ b$$` 不得出现
  「Build Exception」文本、回落显示原文、后续内容不受影响。
