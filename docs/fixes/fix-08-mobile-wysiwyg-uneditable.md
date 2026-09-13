# 修复8：手机端真所见即所得无法编辑 + 编辑回写内容丢失

日期：2026-09-13
范围：`tools/wysiwyg-builder/editor.js`、`assets/wysiwyg/web/editor.min.js`（产物）

## 问题描述

手机端「真所见即所得」（WebView 内 TipTap/ProseMirror）打开后完全无法编辑：
`WysiwygBridge.init` 抛异常 → `_reportFatal` → 宿主静默回退源码模式。
另有确认存在的回写退化：公式节点与代码块内的 `$` 在每次编辑防抖回写时丢失/变形。

## 根因与修复

### 1. init 崩溃：扩展字段函数拿不到自定义 config 键（已修，本次提交）

TipTap `getExtensionField` 把扩展的字段函数 bind 到
`{ name, options, storage, editor, parent }`——自定义键（`selector`/`tag`）不在其上。
`MathBase` 里 `this.selector` 为 undefined → `parseHTML()` 返回 `[undefined]` →
schema 构建抛 `Cannot use 'in' operator to search for 'style' in undefined`。

修复：`MathBase` 对象展开改为 `createMathNode({ name, tag, selector, inline, group })`
闭包工厂，`parseHTML`/`renderHTML` 通过闭包取值，不依赖 `this`。
重建 `editor.min.js`（esbuild，`npm run build`）。

### 2. turndown blankRule 吞掉公式节点（已修，本次提交）

turndown `Rules.forNode` 对 `node.isBlank` 直接走内置 blankRule 返回空串，
自定义规则（mathNode）根本不会被调用。公式 span/div 无文本内容 →
每次编辑防抖（400ms）回写公式全部被删。

修复：`getMarkdown` 改为 `htmlToMarkdown`（占位符方案）——
先把 `[data-math]` 节点替换为占位文本（`\uE000<idx>\uE001`，display 独占段落），
turndown 转换后在 markdown 里还原 `$..$` / `$$..$$`，彻底绕开 isBlank 分支。

### 3. 代码段内的 `$` 被抽成公式（已修，本次提交）

`extractMath` 在 marked 解析前全文扫描，围栏代码块/行内代码里的
`$5 和 $10` 之类被误抽为公式。

修复：新增 `protectCode`——先把 ``` / ~~~ 围栏行与行内 `` ` `` 段替换为
`\uE002<idx>\uE003` 占位，公式抽取完毕后原样还原，再交给 marked。
Safari 14 兼容（无 lookbehind，字符扫描用 `indexOf`）。

### 4. 表格/列表回转退化（已修，本次提交）

- TipTap 表格带 `<colgroup>`：turndown-plugin-gfm 表格规则直接放弃，
  整表退化为裸 HTML → 预处理剥掉 `colgroup`。
- 单元格/列表项内是块级 `<p>`：gfm 规则只认内联内容 → 单元格漏出换行、
  列表被判成松散格式（`-   ` + 项内空行）→ 预处理拆掉 td/th/li 内的 `<p>`。

## 已知边界（有意不改）

- markdown 无「空段落」语义：用户敲的空行在回写时会收敛为段落分隔符
  （块级图片提升后遗留的空 `<p>` 会被删除，避免多出一组换行）。
- 列表标记输出为 `-   item`（turndown 固定风格，marked 可回解析，二次回转稳定）。
- 与文字同行书写 `![]()` 图片时，因 Image 扩展 `inline: false`，
  图片会独立成段（`和\n\n![图]`），二次回转稳定。

## 验证

jsdom 加载重建后的 `editor.min.js`（模板占位符注入，runScripts: dangerously）：

- init 成功，`.ProseMirror` `contenteditable=true`（plain / 行内公式 / 块级公式 / 表格 / 任务列表）。
- 两轮回转稳定性 + 11 组边界用例全部 PASS：plain、行内/块级/同行多公式、
  任务列表、代码块含 `$`、行内代码含 `$`、有序/无序列表、H1-H6、
  粗斜删除线、分隔线+链接、引用+代码、独立图片。
