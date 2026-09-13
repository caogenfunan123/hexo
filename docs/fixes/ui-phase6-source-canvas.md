# 界面改版·阶段6：所见即所得左对齐、写作画布、表格与公式

日期：2026-09-13
范围：`lib/desktop/widgets/wysiwyg_editor_poc.dart`、`lib/desktop/widgets/desktop_split_editor.dart`、
`lib/widgets/debounced_markdown_preview.dart`、`lib/desktop/shell_parts/shell_workbench_ui_ext.dart`、
`lib/desktop/shell_parts/shell_mode_ui_ext.dart`、`lib/desktop/shell_action_bus.dart`、
`lib/desktop/desktop_shell.dart`、`lib/desktop/widgets/title_bar.dart`、`lib/desktop/widgets/status_bar.dart`、
`lib/desktop/shell_parts/shell_misc_ext.dart`、`lib/desktop/shell_parts/shell_style_ext.dart`、
删除 `lib/desktop/widgets/markdown_syntax_highlighter.dart`（本轮孤儿化死文件）

## 决策

用户实测阶段4所见即所得主编辑区后提出四点：

1. 所见即所得正文 760px 居中不合理，应像源码模式一样从左缘起排；
   底部「存草稿/发布」两个大按钮太刺眼，应去掉（顶栏已有发布，补保存入口即可）。
2. 源码模式（WorkMode.source）也改成所见即所得，做成手机端那样的
   「标题 + 正文一张连续画布」，支持自定义壁纸。
3. 桌面端补齐表格与数学公式（手机端预览已支持）。
4. 做全量代码复盘并同步框架文档（见 `docs/fixes/codebase-review-2026-09-13.md`）。

## 实现

### 1a. 所见即所得左对齐

`WysiwygMainEditor.stylesheet.documentPadding` 水平内边距 8 → 20（对标源码模式 20px 左缘）；
`DesktopSplitEditor._buildWysiwygEditor` 不再传 `maxWidth: 760`，去掉 Center/ConstrainedBox 居中。
同文件纯预览/分栏模式的 760px 居中保留（阅读形态不受影响）。

### 1b. 底栏降噪 + 顶栏补保存

- 底部操作栏移除「存草稿」「发布」两个 Expanded 大按钮，仅保留导出下拉菜单与
  （图片上传失败时才出现的）重试上传；状态行排版收紧。
- 存草稿/发布入口去向：顶栏新增保存按钮（`ShellActionBus` 新增 `onSaveLocal` 必填字段，
  desktop_shell 接线 `_saveLocal`；title_bar 插入 `save_outlined` 图标，tooltip 带 Ctrl+S）；
  发布本就在顶栏（Ctrl+P）；另有自动保存兜底，状态栏保留「已保存/未保存」指示灯。

### 2. 源码模式 → 写作画布（WorkMode.source 复用，UI 全部改名「写作画布」）

- `_buildSourceEditor` 重写为 `_buildCanvasEditor`：壁纸/纯黑/主题底色背景层（与专注模式同源，
  另修正旧画布暗色主题下白底白字的问题——非自定义背景时改用 `AppColor.surfaceBase`）+
  无边框大号标题输入 + `Expanded(WysiwygMainEditor(textColor: _deskTextColor))`，
  标题与正文同一张画布、无卡片无分割线，对标手机端编辑页。
- 旧的 28px「源码模式」chrome 条与 24px 底部状态条删除；顶栏对非 workspace 模式统一
  使用极简标题栏（`_buildTopBar` 条件从 `== focus` 改为 `!= workspace`），
  保存/预览/更多菜单（AI/发布/同步/元数据）全部可用。
- 专注模式的右侧预览面板与右抽屉抽成共用浮层 `_buildCanvasOverlays(mutedColor:)`，
  画布模式同样支持 Ctrl+E 抽屉与极简预览（互斥）。
- 语法高亮源码编辑器（BridgedSyntaxController）随之退役：字段/dispose/导入从
  desktop_shell.dart 删除，`markdown_syntax_highlighter.dart` 全库零引用后整文件删除。
  纯源码编辑仍保留在工作台分栏编辑器的「源码」模式（DesktopSplitEditor.sourceOnly）。
- 文案改名：状态栏按钮「源码」→「画布」（图标 auto_stories）、命令面板「源码模式」→
  「写作画布」、帮助卡片同步改写；枚举 `WorkMode.source` 值保持不变（会话持久化兼容）。

### 3. 表格与数学公式（对齐手机端）

根因两个：

- **表格**：super_editor 0.3.0-dev.52 的表格解析（TableSyntax）与序列化
  （TableBlockNodeSerializer）都在，但 `defaultComponentBuilders` **不含表格渲染组件**，
  导致表格「能存不能看」。`WysiwygMainEditor` 与 `WysiwygEditorPoc` 的 componentBuilders
  显式加入 `MarkdownTableComponentBuilder()`（块级选中，整表选中/整体编辑）。
- **公式**：桌面预览原用 flutter_markdown（不支持公式），手机端预览用
  flutter_smooth_markdown（原生表格 + 内联/块级公式 + mermaid）。`DebouncedMarkdownPreview`
  整体重写为 SmoothMarkdown 渲染引擎（保留 DebouncedMarkdownPreviewState API、
  200ms 防抖、60000 字素簇截断提示），样式按基准字号 16 等比缩放（对标 MarkdownPreviewSmooth）。
  `DesktopSplitEditor` 删除 flutter_markdown 依赖与 styleSheet 参数；WYSIWYG 内的
  `$...$` 保持原文不损坏（super_editor 无数学语法，原样往返），公式渲染走预览——与手机端行为一致。

## 验证

- `dart analyze`（本机 Dart SDK 3.x）：改动库文件 0 error / 0 warning（存量 withOpacity
  弃用 info 为历史噪音）。
- 测试：`preview_render_test.dart` 适配新 API（去 styleSheet）并新增表格渲染用例；
  `wysiwyg_poc_test.dart` 新增表格往返 + 表格渲染用例；`flutter test` 由 CI 执行。
- 真机验收关注点：画布模式壁纸字色自适应（亮壁纸黑字/暗壁纸白字）；极宽窗口下
  WYSIWYG 满宽排版（用户明确要求，不再做阅读宽度限制）；表格在所见即所得中块级选中。
