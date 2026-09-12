# 修复2：markdown_syntax_highlighter.dart 重复解析实现收敛

日期：2026-09-12
范围：`lib/desktop/widgets/markdown_syntax_highlighter.dart`（945 行 → 614 行，消除 331 行重复）

## 问题描述

文件内 `BridgedSyntaxController`（桥接控制器，桌面源码模式实际使用）与
`MarkdownSyntaxController`（独立控制器）各自实现了**整套几乎相同的解析逻辑**：
`_parseHighlighting`（逐行解析 frontmatter/代码围栏/标题/引用/水平线/列表/表格）、
`_highlightFrontmatterLine`、`_highlightCodeBlockDelimiter`、`_highlightTableLine`、
`_highlightInline`（12 个内联正则）、`_hasOverlap`、`_mergeOverlappingSpans`，
合计约 400+ 行逐行近似重复，且 buildTextSpan 的 span 组装循环也是两份。
任何解析规则修改都要同步改两处，极易漏改产生行为分叉。

## 修复方案

- 新增私有 mixin `_MarkdownHighlightParsing on TextEditingController`，集中承载：
  解析缓存（_cacheText/_cacheSpans）、`parseHighlighting`、全部 `_highlight*` 辅助方法、
  `buildTextSpan`（含空文本分支与 span 组装循环）、缓存失效入口 `invalidateHighlightCache`。
- 两个控制器改为 `with _MarkdownHighlightParsing`，只保留各自真正差异化的部分：
  - `BridgedSyntaxController`：delegate 双向同步、dispose 解绑；
  - `MarkdownSyntaxController`：独立构造。
- 公共 API 完全不变（构造参数、`colors` 可变字段、`updateColors`、`buildTextSpan`）。
  现有唯一使用方 `BridgedSyntaxController`（shell_mode_ui_ext.dart 源码模式）零改动。

## 行为差异说明（原两份实现的细微分歧，统一后取更精确的一方）

1. 标题 `#` 后的空格：Bridged 版把该空格并入 50% 透明度的标题色 span，
   Markdown 版该空格为正文色。统一取 Markdown 版（不给空格着标题色，视觉差 1 字符）。
2. 空文本分支：Bridged 版附 `plainText` 色，Markdown 版未附。空文本渲染不可见，
   统一取带色版本，无可见影响。
其余逐行比对等价（列表内联偏移等写法不同但数值相同）。

## 验证

- `flutter analyze`：lib/ 0 error / 0 warning。
- `flutter test`：26/26 通过，其中 DesktopSplitEditor 端到端用例覆盖了
  高亮构建器路径（含代码块内容渲染）。
- 公共 API 签名未变，外部调用方无需改动。
