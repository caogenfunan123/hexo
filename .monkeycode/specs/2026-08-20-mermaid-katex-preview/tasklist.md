# 任务列表：全平台 Mermaid 与 KaTeX 公式渲染

## 实施清单

- [x] 设计技术方案：WebView + mermaid.js + KaTeX 渲染管线
- [x] 下载 mermaid.js / KaTeX / highlight.js 前端资源
- [x] 创建 HTML 模板（`assets/preview/web/preview_template.html`）
- [x] 创建 KaTeX 字体内联 CSS（`katex-inline.min.css`，base64 嵌入字体）
- [x] 创建 `lib/core/markdown/markdown_preview_builder.dart`（纯 Dart 转换器）
- [x] 创建 `lib/widgets/markdown_preview_webview.dart`（Flutter 组件）
- [x] 更新 `pubspec.yaml` 添加 assets 配置
- [x] 接入桌面端预览（`desktop_shell.dart`）
- [x] 接入移动端预览（`editor_remote_ext.dart`）
- [x] 更新 `main.dart` 添加 widget import
- [ ] 全量 `flutter analyze` 验证 0 error / 0 warning
- [ ] 功能自测确认渲染正确