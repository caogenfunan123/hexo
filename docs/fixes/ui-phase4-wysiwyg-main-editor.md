# 界面改版·阶段4：所见即所得替换主编辑区

日期：2026-09-12
范围：`lib/desktop/widgets/wysiwyg_editor_poc.dart`（新增 WysiwygMainEditor）、`lib/desktop/widgets/desktop_split_editor.dart`、`lib/desktop/shell_parts/shell_workbench_ui_ext.dart`、`lib/desktop/desktop_shell.dart`

## 决策

用户实测阶段2实验对话框后拍板：**所见即所得成为主编辑区的默认模式**。
源码/分栏/预览保留为可随时切换的辅助模式（逃生舱），而非物理删除——
frontmatter 源码编辑、复杂表格排错仍需要它们。

## 实现

### 模式体系

`SplitEditorMode` 新增 `wysiwyg`（枚举首位），模式栏按钮顺序：所见即所得 → 源码 →
分栏 → 预览；壳默认 `_splitEditorMode = wysiwyg`。内容区 760px 居中纸面。

### WysiwygMainEditor（与 POC 对话框组件分离）

与 `contentCtrl` 双向绑定的富文本编辑器：

- **写出**：文档变更防抖 250ms → `serializeDocumentToMarkdown` → `controller.text =
  frontmatter + body`（自动触发 shell 既有链路：自动保存、字数统计、状态栏、预览）；
- **读入**：监听 controller，文本与最近序列化结果不一致（AI 改写/查找替换/片段插入/
  切文章等程序化写入）→ 整体重建文档（`_generation` 递增迫使 SuperEditor 重挂载），
  写回自身引起的变化经 `_lastBody` 比对判定回环、不重建；
- **frontmatter 拆分保管**：`---` 块解析时拆出、不参与富文本编辑，写回时原样前置；
  属性编辑仍走属性面板/源码模式；
- **防丢字**：dispose 时把防抖窗口内未写回的编辑强制同步回 controller
  （先摘自身监听再写，避免通知打到 defunct 元素）。

### 配套调整

- 源码格式工具栏（粗体/斜体/表格…基于 controller 选区操作）在所见即所得模式下
  隐藏（选区对富文本光标无意义）；图床插入仍可用拖拽（EditorDropTarget 在编辑区外层）。
- 专注模式暂不替换：其价值是打字机滚动 + 当前行高亮，super_editor 暂无对应能力，
  保持源码纸面形态（后续评估）。

## 验证

- `flutter analyze` 0 error / 0 warning；`flutter test` 29/29（新增主编辑区
  frontmatter 拆分 + 外部改动重建用例）。
- 已知边界（真机验收关注点）：表格/任务列表为 super_editor 内建语法支持；
  图片仅网络图渲染；外部写入后光标复位到文档头部属预期。
