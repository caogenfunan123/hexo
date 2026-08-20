# 全平台 Mermaid 图表与 KaTeX 数学公式渲染

## 背景

软件支持 Markdown 编辑，已有桌面端 `_buildMarkdownPreview` 对 Mermaid 和 LaTeX 的源码识别能力，但仅限于"展示源码"而非真正渲染：
- 桌面端 `_buildMermaidPreview` 仅显示 Mermaid 源码卡片
- 桌面端 `_buildLatexPreview` 仅以斜体文本显示 LaTeX 源码
- 移动端 `_openArticlePreview` 直接用 `flutter_markdown` 的 `Markdown` 组件，无任何特殊处理
- `flutter_math_fork` 因 Windows 构建失败已被移除

## 目标

手机端（Android/iOS）和电脑端（macOS/Windows/Linux）均支持真正的 Mermaid 图表渲染和 LaTeX 数学公式渲染。

## 技术方案

统一走 **WebView + mermaid.js + KaTeX** 渲染管线：

```
编辑器文本 → Dart 侧占位符保护 + markdownToHtml → 拼入 HTML 模板 → WebView 加载
                                                              ↓
                                              浏览器侧：KaTeX auto-render + mermaid.js + highlight.js
```

### 渲染流程

1. Markdown 文本在 Dart 侧做预处理（代码块/公式提取为占位符，避免 `markdown` 包破坏 `$` 标记）
2. `markdown` 包完成 Markdown → HTML 转换
3. 还原占位符（公式保留 `$...$` 原文交给 KaTeX，mermaid 输出 `<pre class="mermaid">`）
4. 拼入完整 HTML 模板（内联 mermaid.js、KaTeX、highlight.js），WebView 加载
5. 浏览器侧依次执行：KaTeX auto-render → highlight.js → mermaid.js

### 差异说明

- Android/iOS/macOS/Web：`flutter_inappwebview` 6.x 原生支持
- Windows：`flutter_inappwebview_windows` 0.6.0（已在 lock 中）
- Linux：`flutter_inappwebview` 不支持，降级为 `flutter_markdown` 静态渲染

### 关键设计

- KaTeX 字体通过 base64 内联到 CSS，避免 WebView 跨域加载字体文件
- 公式占位符保护采用 Unicode 私用区字符 `\uE000` + 序号 + `\uE001`，确保 `markdown` 包不会破坏 `$x_i$` 中的下划线
- 内容变更时增量更新（`setContent` JS 函数），主题切换时整页重载
- 事件属性/script/iframe 在 Dart 侧 sanitize 后拼入 HTML，防止 XSS