# 修复11：第二轮复盘——注入失败误杀编辑器、保护窗丢字、行内公式样式与分屏拖拽性能

日期：2026-09-15
范围：`lib/widgets/wysiwyg_web_editor.dart`、`lib/widgets/split_preview_pane.dart`、
`lib/desktop/widgets/desktop_split_editor.dart`、`lib/widgets/safe_math_builders.dart`、
`lib/mixins/editor_remote_ext.dart`、`tools/wysiwyg-builder/editor.js`（+产物）、
`pubspec.lock`

复盘方法：双 agent 交叉审查 445c7cf/f6504e7 公式渲染链路 diff + flutter analyze
全仓（0 error/0 warning，679 info 基线）+ flutter test 全量 + jsdom 三套用例。

## 编辑端（真所见即所得）

### 高：KaTeX 兜底注入失败会误杀整个编辑器

`wysiwyg_web_editor.dart`：445c7cf 的注入块落在外层 try/catch 内，rootBundle
读取或 IPC 注入抛异常（PlatformException / 个别机型 Binder 紧张）会直接走
`_reportFatal()` 让编辑器退回源码模式——而兜底路径本身就是为「虚拟域已坏」
的高危环境准备的，且 JS 侧有 latex 原文降级（math-raw）。改为注入块独立
try/catch，失败仅 debugPrint 并继续 init。

### 中：旧 onLoadStop 异步续体误报 fatal

dark 切换会因 ValueKey 重建 WebView；旧实例的 async 续体在 await 之后
继续操作已销毁的 controller（MissingPluginException 或 ok=null）→ 误报
fatal，把刚重建的新 WebView 一并判死。修复：每个 await 后检查
`mounted && _webCtrl == ctrl`，失效续体直接作废；`_reportFatal` 对
onFatalError 回调加 mounted 守卫（组件已移除时宿主不再感知）。

### 中：applyingRemote 定时保护窗吞 emit 可致永久丢字

`editor.js`：init 后 300ms / setMarkdown 后 60ms 的定时窗内，
`scheduleEmit` 因 applyingRemote 直接 return——连 timer 都不挂；窗口内
用户击键的回传被整体吞掉，下一条 setMarkdown 的「先冲刷防覆盖」无 timer
可冲，setContent 直接覆盖丢字。而 `setContent(md, false)` 第二参
emitUpdate=false 本就不触发 onUpdate，定时窗是多余的。改为同步块守卫
（try/finally 包住 setContent / Editor 构造，出块即解除），用户输入永远
落在守卫之外。

## 预览端

### 中：行内公式被按 display 样式排版

flutter_math_fork 的 MathOptions 工厂默认 `style: MathStyle.display` 且
覆盖 mathStyle 参数——`$...$` 行内公式的 `\sum` 上下限、分数尺寸全错。
safe_math_builders 显式声明 inline=text / block=display，并删掉 options
非空时被忽略的死参 textStyle。

### 中：PNG 长图导出暗色主题白底白字

`editor_remote_ext.dart` 导出长图强制白底，但 SmoothMarkdown 用
fromTheme 样式表——暗色主题返回白色文字，导出图几乎不可见。固定传
`MarkdownStyleSheet.light()`。

### 低：导出长图 OverlayEntry 异步泄漏

截图/写盘任一步抛异常，离屏 entry 永久留在 overlay。改 try/finally 中
`if (entry.mounted) entry.remove()`。

## 性能：分屏拖拽每帧全文重解析（双端）

拖拽中缝每帧 setState / ValueListenableBuilder 重建整棵子树，
MarkdownPreviewSmooth/DebouncedMarkdownPreview 实例随之重建 →
SmoothMarkdown 全文 parse（MermaidPlugin 使全局 parse 缓存旁路）+ 每个公式
Math.tex 重排版，长文档拖动明显掉帧。

- `split_preview_pane.dart`：预览子树经 ValueListenableBuilder 的 child
  参数透传，拖拽帧只重建 flex 布局；widget identical 时 Element 跳过重建。
- `desktop_split_editor.dart`：`_splitRatio`/`_sepDragActive` 改为
  ValueNotifier，拖拽与悬停不再 setState 整体重建；分栏比例走
  ValueListenableBuilder（预览 child 透传），工具栏百分比局部监听。

## 核查后排除的项

- pubspec.lock 与 pubspec.yaml 的依赖分类漂移（flutter_math_fork
  transitive→direct main）：lock 长期带 SDK 重解析 churn（16 包版本漂移），
  CI 无 --enforce-lockfile 会静默重解析，维持「不提交 churn」的既有约定。
- SmoothMarkdown 无超长文档截断（DebouncedMarkdownPreview 有 60k 截断）：
  阅读页截断会静默隐藏内容，行为改变需单独评估，本轮不动。
- 兜底 Text 顶层化以获得行内折行：只覆盖 parse 期错误（CrNode 是 build 期），
  收益部分且行为变动，维持与包默认一致。

## 验证

- jsdom：test13（守卫同步释放/冲刷）5/5 + test11 语义回转 18 组 +
  test12 渲染路径 9/9 全过。
- editor.min.js 重新构建（410.1kb）。
- flutter analyze：改档无新增 lint 类别（全部为既有 info 基线模式）。
- flutter test：全量通过。
