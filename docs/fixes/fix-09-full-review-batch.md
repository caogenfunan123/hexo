# 修复9：全仓复盘——切文章丢稿/跨文章污染/预览配色反转等 12 项

日期：2026-09-13
范围：`lib/main.dart`、`lib/mixins/editor_text_ext.dart`、`editor_publish_ext.dart`、
`editor_ui_ext.dart`、`lib/desktop/shell_parts/shell_autosave_ext.dart`、
`shell_publish_ext.dart`、`lib/widgets/wysiwyg_web_editor.dart`、`split_preview_pane.dart`、
`lib/services/session_service.dart`、`tools/wysiwyg-builder/editor.js`（+产物）

复盘方法：flutter analyze 全仓（0 error/0 warning）+ flutter test 全量（45/45）+
双 agent 交叉审查 61bd97c/fa62401 高危 diff + jsdom 回转语义用例 18 组。

## 修复清单

### 高

1. **手机端切文章后 2s 防抖窗口编辑被静默丢弃**（61bd97c 回归）
   `editor_text_ext.dart`：定时器到点先 `remove` 再因"已切走"直接 return，
   兜底 flush 永远见不到该条目。改为无条件 `_autoSaveSnapshot`（isCurrent
   守卫已在内部防串草稿/防降级）。

2. **分屏预览 darkTheme 判断写反**：`split_preview_pane.dart` 白底黑字
   （默认）时反而用暗色样式，两种背景下预览均不可读。`< 0.5` → `> 0.5`。

### 中

3. **发布完成回写跨文章污染（双端四条路径）**：发布 await（10s+）期间切走
   文章后 `userEdited` 恒真，`updateCurrentArticleMeta(pub)` 会把文章 A 的
   标题/内容/标签整体套到文章 B 上并落盘。四条路径（mobile `_publish`/
   `_publishToCms`、desktop `_executePublish`/`_publishToCms`）统一加
   `publishArticleId` 绑定校验：已切走则发布结果只落回原文章草稿。

4. **桌面端防抖数据未捕获元数据 + flush 结构缺陷**（`shell_autosave_ext.dart`）：
   tags/categories/cover 在触发时读控制器（已是新文章的）；flush 对裸 Timer
   闭包里的内容无能为力（当前文章 ≤2s 窗口输入丢失），且双重保存。
   重构为"调度时把内容+元数据一起写入 `_pendingSaveMap`，flush 按 map 数据
   保存并去重"，对齐手机端 `_DebounceEntry` 模式。

5. **session_service 快照名解析正则失效**：`RegExp(r'[\/]')` 中 `\/` 只是
   转义的 `/`，Windows 反斜杠路径切不开 → 快照恢复/清理双失效。
   改为 `RegExp(r'[\\/]')`。

6. **会话恢复把已发布文章降级为草稿**（`main.dart _restoreSession`）：
   `isDraft: true` 硬编码，自动保存会把本地已发布文章降级。改为以草稿箱
   实体的 isDraft/published/时间戳为准，内容/标题仍取会话（更长的未保存态）。

7. **安卓上 WebView init 失败检测失效**：`evaluateJavascript` 对 JS 抛错
   返回 null 而非抛 PlatformException，catch 永不触发，用户停留在空编辑器。
   JS `init` 已返回 `true`，Dart 侧改为校验返回值 `ok == true`，否则走
   `_reportFatal` 自动回退源码模式。

8. **外部 setMarkdown 与 JS 400ms emit 竞态丢字**（editor.js）：用户输入的
   防抖窗口内 Dart 侧推送外部改动会覆盖未 emit 的输入。`setMarkdown` 先
   强制冲刷挂起的 emit；`init` 顺带清掉旧 emitTimer。

9. **生命周期/切模式/切文章未回收 WebView 防抖窗口输入**：新增
   `WysiwygWebViewEditorState.flushToController()`（getMarkdown 拉回写
   contentCtrl），并在 App paused、双模式切换、`_navigateTo` 离开编辑器、
   `_openReader` 切文章四类路径先拉回再冲刷/切换。

### 低

10. **markSaved 错标**：双端 `_autoSaveSnapshot` 的 await 窗口内切走文章时
    把新文章标成"已保存"。改为 await 后重校验 `currentArticle.id == aid`。
11. **KaTeX 内联转义多一个反斜杠**：`'<\\\\/style>'` → `'<\\/style>'`，
    与 editor.js 分支统一（当前资产无 `</style>` 字面量，属防御性修正）。
12. **dark 切换时 setDark 死代码**：key 含 dark 必然元素重建，didUpdateWidget
    的 setDark 分支不可达，删除。

## 有意不做

- flush 返回的 futures 仍 fire-and-forget（进程存活场景足以落盘；detached
  极端场景受平台限制）。
- 定时发布 UI 状态残留（仅显示层，到点自动清除）。
- `loadAutoSnapshot` 无恢复入口（快照机制存在，恢复 UI 属新功能）。

## 验证

- `flutter analyze`：0 error / 0 warning（679 条 info 为历史 lint 基线）。
- `flutter test`：45/45 通过。
- jsdom：公式/价格文本语义回转 18/18 PASS，稳定性 6/6，init/可编辑性 OK。
