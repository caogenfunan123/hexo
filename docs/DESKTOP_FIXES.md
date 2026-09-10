# 电脑端（Windows/桌面）问题修复记录

> 文档说明：本文件记录对电脑端桌面版（Windows 优先）的逐项问题排查与修复，按 Phase 分组。
> 手机端（Android/iOS）不在本轮改动范围。

## 排查结论汇总

| # | 问题现象 | 代码根因 | 状态 |
|---|---------|---------|------|
| P1-1 | 打字时预览整篇重解析、全界面卡顿 | 预览无防抖，每次击键触发 `Markdown()`/`SmoothMarkdown()` 全文重建 | 已修复 |
| P1-2 | 每键整壳 setState，状态栏/左面板全量重建 | `_trackStats` 每键 `setState(() {})`，无局部刷新隔离 | 已修复 |
| P1-3 | 源码模式语法高亮每键全篇正则解析 | `BridgedSyntaxController.buildTextSpan` 每键全文跑 ~12 个正则 | 已修复 |
| P1-4 | 自动保存全量草稿 JSON 序列化在 UI 线程同步执行 | `storage.saveDrafts` 全表 `withIndent` 序列化 | 已修复 |
| P2-1 | 窗口周围一圈白边框 | `desktop_main.dart` 原生窗口底色写死 `Colors.white` + 无背景兜底 | 已修复 |
| P2-2 | 预览区空白/黑屏 | 桌面禁用 webview 后预览降级不完整 | 已修复 |
| P2-3 | 整体字小、中文发虚 | UI 硬编码 10–13px、无全局字号缩放 | 已修复 |
| P3-1 | 草稿点一下开多个 | 远程文章用时间戳当 tab id 去重失效 + 无点击防抖 | 已修复 |
| P3-2 | 多标签内容互串 | 所有 tab 共享同一个 `_doc`/`contentCtrl` | 已修复 |
| P3-3 | AI 操作后预览不刷新 | 程序化写入未触发 `_onContentChanged()` | 已修复 |

## Phase 1：性能核心

### P1-1 预览防抖 + 隔离（已修复）

**问题**：桌面 `DesktopSplitEditor` 在 build 内直接 `new Markdown(data: contentController.text)`，
每次击键（父级 setState）都整篇重新解析渲染；`MarkdownPreviewSmooth`（专注模式）同理。
长文档下每键全量 parse 是"经常卡"的主因之一。

**改动**：
- 新增 `lib/widgets/debounced_markdown_preview.dart`：
  - `DebouncedMarkdownPreviewState`：ChangeNotifier，文本变化后 200ms 静默期才提交并 notify；
  - `DebouncedMarkdownPreview`：用 `AnimatedBuilder` 订阅该状态，仅在提交后重建 `Markdown`。
- `lib/desktop/widgets/desktop_split_editor.dart`：
  - State 内持有 `_previewState`，监听 `contentController` 调 `updateText`（统一触发源，
    不再依赖 TextField.onChanged，避免双触发）；
  - 预览区（纯预览 / 分栏右栏）改用 `DebouncedMarkdownPreview`；
  - `didUpdateWidget` 处理 controller 更换场景（移除旧监听、挂新监听）。
- `lib/widgets/markdown_preview_smooth.dart`：由 StatelessWidget 改为 StatefulWidget，
  内部对 `markdown` 变化做 200ms 防抖，专注模式预览同样不再每键重建。

**验证**：需真机观察打字时预览 200ms 静默期后刷新，不再逐键卡顿。

### P1-3 语法高亮解析缓存（已修复）

**问题**：`BridgedSyntaxController.buildTextSpan` 在每次绘制（含光标闪烁、滚动、重绘帧）
都调用 `_parseHighlighting(text)`，对全文跑约 12 个正则（标题/加粗/链接/代码块/表格等）
并做重叠合并。长文档下每帧全量解析，是逐键卡顿的第二主因。

**改动**（`lib/desktop/widgets/markdown_syntax_highlighter.dart`）：
- `BridgedSyntaxController` 与 `MarkdownSyntaxController` 各新增
  `_cacheText` / `_cacheSpans` 字段；
- `_parseHighlighting` 开头：`if (text == _cacheText) return _cacheSpans;` 直接复用上次结果；
- 解析完成排序合并后写入缓存再返回。buildTextSpan 对 spans 只读，无共享可变风险。
- 效果：文本未变化的帧（光标闪烁、滚动、无键状态重绘）零解析开销；仅在真实击键时解析一次。

**验证**：`dart analyze lib/desktop/widgets/markdown_syntax_highlighter.dart` 仅剩
`withOpacity` 弃用 info（既有），无新增错误。

### P1-4 自动保存全量序列化移出 UI 线程（已修复）

**问题**：`storage.saveDrafts` 对整表草稿做 `jsonEncode(withIndent)` 同步写盘，发生在 UI
线程，每键触发一次，长文档下造成周期性掉帧。

**改动**（`lib/services/storage_service.dart`）：
- `saveDrafts` 先在调用方把 `drafts.map((e) => e.toJson()).toList()` 构造成纯 JSON 数据
  （`Article.toJson` 只产出字符串/布尔/列表，可直接跨 isolate）；
- 序列化改用 `compute(_encodeDraftsJson, data)`（`package:flutter/foundation.dart` 内置）在
  后台 isolate 执行；Web 端 `compute` 自动降级为同步执行，行为不变；
- 新增顶层函数 `_encodeDraftsJson`。

**验证**：`dart analyze lib/services/storage_service.dart` 仅剩既有 `unused_import` /
`unnecessary_import` 提示，无新增错误。

## Phase 2：白边 / 预览 / 字号

### P2-1 窗口白边跟随主题（已修复）

**问题**：无边框窗口（`TitleBarStyle.hidden`）原生背景写死 `Colors.white`，
且 `DesktopShell` 顶层是裸 `Stack` 无兜底色。浅色下窗口四周出现白边框/白缝，
切深色后原生底色仍为白色，边缝刺眼。

**改动**：
- `lib/desktop/desktop_main.dart`：
  - 新增 `_nativeBgColor()`：按 `_themeMode`（system 取 `platformDispatcher.platformBrightness`）
    结合 `_designConfig.lightBgColor` / `darkBgColor` 计算原生窗口底色；
  - `_initWindow` 的 `backgroundColor` 改用 `_nativeBgColor()`；
  - `_toggleAppTheme` 切换主题时调用 `windowManager.setBackgroundColor(_nativeBgColor())` 同步。
- `lib/desktop/desktop_shell.dart`：顶层 `Column` 包一层
  `ColoredBox(color: Theme.of(context).scaffoldBackgroundColor)` 兜底，任何面板空隙
  不再暴露原生底色。

**验证**：`dart analyze` 两文件均无新增错误；需真机切主题观察窗口边缘无白边残留。

### P2-2 预览区空白/黑屏（已修复）

**问题**：桌面「网站预览」走 `PreviewScreen`，内部直接用 `InAppWebView` 且无任何失败
兜底。Windows 缺少 WebView2 运行环境时 WebView 静默失败：一直黑屏/空白，进度条常驻，
且没有「改用浏览器打开」的出口（Linux 已有回退，Windows 没有）。

**改动**（`lib/screens/preview_screen.dart`）：
- 新增 `_webviewFailed` / `_failReason` 状态与 `_buildFallback()` 兜底界面
  （图标 + 原因文案 + 「在浏览器打开」+「重试」）；
- `onReceivedError` → 标记失败并展示兜底；
- 加载 15 秒内 `onLoadStart` 未触发（WebView2 缺失典型症状）→ 超时展示兜底；
- 新增 URL 栏外的「在浏览器打开」入口可随时导出外链。

**验证**：`dart analyze` 无新增问题；Windows 无 WebView2 环境下预览不再黑屏，
会显示兜底卡片并可直接用系统浏览器打开。

### P2-3 全局字号缩放（已修复）

**问题**：`DesignConfig.fontScale` 只作用于主题 textTheme，desktop_shell 大量
硬编码 10–13px 的小字号完全不缩放，Windows 下中文小字发虚、整体偏小。

**改动**（`lib/desktop/desktop_main.dart`）：
- MaterialApp 增加 `builder`：用 `MediaQuery.textScaler: TextScaler.linear(fontScale)`
  包裹子树，使**所有** `Text`/`TextField`（含硬编码小字号）统一按 fontScale 缩放，
  `fontScale` 因此成为真正的全局字号开关；
- 桌面初始 `_designConfig` 改为 `DesignConfig(fontScale: 1.1)`，默认放大 10% 缓解
  小字号发虚；clamp 0.9–1.4 防越界。

**验证**：`dart analyze` 无新增问题；需真机观察桌面整体字号放大、设置里字号滑块
现在对硬编码小字同样生效。

## Phase 3：交互 Bug

### P3-1 草稿点击防抖 + 远程文章稳定 id（已修复）

**问题**：两个成因叠加导致「点一下文章开了多个标签」：
1. 远程文章（CMS/同步）用 `DateTime.now()` 当 tab id 生成，每次点开 id 都不同，
   去重逻辑永远失效；
2. 编辑器标签点击本身无防抖，双击/重复点击会重复走打开流程。

**改动**（`lib/desktop/desktop_shell.dart`、`lib/screens/remote_posts_screen.dart`、
`lib/screens/sync_screen.dart`）：
- `_openExistingArticle` 开头加 300ms 同 tabId 防抖守卫（`_lastOpenGuardKey` /
  `_lastOpenGuardTime`），重复点击同一标签直接忽略；
- 远程文章改为稳定 id：RemotePostsScreen `onOpenInEditor` 用
  `id: 'cms_${post.siteId ?? 'cms'}_${post.id ?? post.title.hashCode}'`；
  SyncScreen `onOpenRemotePost` 用 `id: 'sync_${post.id ?? post.title.hashCode}'`，
  `cms_`/`sync_` 前缀避免与本地草稿 id 冲突。

**验证**：`dart analyze` 无新增错误；需真机快速连点草稿只开一个标签。

### P3-2 多标签内容互串（已修复）

**问题**：所有编辑器标签共享同一个 `_doc` / `_doc.contentCtrl`，切标签时直接把
目标文章写进共享 controller，前一标签未保存的改动被覆盖丢失；`DesktopEditorArea`
又用 `IndexedStack` 常驻全部标签，切走再切回内容被共享 controller 内容串换。

**改动**（`lib/desktop/desktop_shell.dart`）：
- 新增 `_EditorTabSession` 会话类（article/content/title/tags/categories/cover/repo/
  lastSavedContent）与 `_tabSessions` map，每个标签保存自己的完整编辑态；
- `_openExistingArticle`：已打开标签只 `_switchEditorTab` 切换；新开则建会话并
  `_loadSessionIntoDoc`；
- 新增 `_saveSessionFromDoc`（切走/关标签前捕获当前编辑态）、`_loadSessionIntoDoc`
  （把目标会话写回共享 `_doc`）、`_switchEditorTab`（先存当前再载目标）；
- `_newArticle` 播种空会话；`_closeTab` 关闭前保存、关闭后载入下一激活标签；
- `DesktopEditorArea` 外包 `ListenableBuilder(listenable: _editor)`，切标签/状态变化
  局部刷新；`onTabChange` 改为 `_switchEditorTab`。

**验证**：`dart analyze` 仅剩既有 `_lastStatsHash` unused_field 与 `_buildMarkdownPreview`
unused_element 两个 warning；需真机多开标签各自编辑、互相切换内容不互串、切走后
未保存改动保留。

### P3-3 AI 操作后预览不刷新（已修复）

**问题**：`_aiAction` 的 polish/rewrite/format 等分支用 `_doc.contentCtrl.text = ...`
程序化写入，`TextEditingController.text` setter 不触发 `onChanged`，于是
`_onContentChanged()`（预览防抖/字数统计/自动保存管线）完全不执行：AI 改写后
右侧预览仍是旧内容、字数不更新，且改动不触发自动保存。

**改动**（`lib/desktop/desktop_shell.dart`）：
- `_aiAction` 中 `polish`、`rewrite`、`format` 三个写入分支后补 `_onContentChanged()`；
- 其余程序化写入统一补齐，保证预览/字数/自动保存管线一致：
  `_insertText`（AI 续写、代码块插入、工具栏插入统一入口）、`_insertCodeBlock`、
  `_wrap`、`_insertHeading`、`_insertList`、`_insertLink`、`_addTableRow`、
  `_addTableCol`、AI 选区编辑接受（`_sendSelectionToAi` onAccept）、AI diff 接受
  （`_showAiDiffPreview` 两处）、历史版本恢复、图片 URL 批量替换、批量工具箱更新、
  `_loadSessionIntoDoc`（切标签后刷新统计）；
- 焦点模式预览区（`_buildFocusEditor`）外包
  `ListenableBuilder(listenable: _doc.contentCtrl)`，contentCtrl 变化即时重建预览，
  不再依赖整壳 setState。

**验证**：`dart analyze lib/desktop/desktop_shell.dart` 无 error（仅既有 info/warning）；
需真机执行 AI 润色/重写后预览即时刷新、字数更新、改动 2 秒后自动保存。

## Phase 4：界面与安卓端对齐美化

> 目标：桌面端观感向安卓端 Material 风格靠拢。根因是桌面端「自绘控件 + 10-13px
> 小字号 + 4-8px 圆角 + 散落硬编码色」与安卓端「标准 Material 组件 + 14-18px 字号
> + 12-16px 圆角 + 统一 ColorScheme」割裂。

### P4-1 字号双重放大修复（已修复）

**问题**：P2-3 的 `MediaQuery.textScaler`（1.1）与主题 `fontScale`（1.1）叠加，
实际缩放 1.1×1.1=1.21 倍；且 textScaler 线性放大文字但固定高度容器
（标题栏 44 / 状态栏 28 / 抽屉 tab 40）不增高，存在换行/截断/重叠风险。

**改动**（`lib/desktop/desktop_main.dart`）：
- 主题生成改用 `_designConfig.copyWith(fontScale: 1.0)`；
- textScaler 保留 `_designConfig.fontScale.clamp(0.9, 1.4)`；
- 效果：全树（含硬编码小字）统一按 fontScale 线性缩放一次，无叠加；
  设置里字号滑块仍然全局生效。

### P4-2 surface 三层色统一（已修复）

**问题**：窗口原生底色（`lightBgColor=0xFFF0FDFA`）、`scaffoldBackgroundColor`
（同 DesignConfig）、面板 `AppColor.surfaceBase=0xFFF5F5F7`/`surfaceRaised=0xFFFAFAFC`
三套色值不一致，亮色下桌面壳呈灰底拼贴感，与安卓 teal 调背景脱节。

**改动**（`lib/theme/app_color.dart`）：
- `surfaceBase` 亮色 → `0xFFF0FDFA`（= DesignConfig.lightBgColor）
- `surfaceRaised` 亮色 → `0xFFFFFFFF`（= DesignConfig.lightCardColor）
- `surfaceHover` 亮色 → teal 调 `0xFFE6F6F2`；`border` 亮色 → teal 调 `0xFFD9EEE8`
- 深色值不变（已与 darkBgColor/darkCardColor 一致）

### P4-3 桌面壳字号/图标/圆角整体上调（已修复）

| 文件 | 改动 |
|------|------|
| status_bar.dart | 状态标签 10→12、模式按钮 10.5→12（icon 11→14）、状态图标 10→13，栏高 28→30 |
| title_bar.dart | 应用名 12.5→13.5、站点名 12→13、icon 17→18、窗口按钮 icon 15→16、圆角 6/7→8、角标 9→10 |
| left_panel.dart | 分组标题 10→12、导航项 12.5→13.5（icon 16→18，垂直内边距 7→9）、文章 12→13（icon 13→15，间距 6→8）、站点 12.5→13.5 / 副标题 10→12（icon 15→17）、圆角 6→8、角标 9→10 |
| right_drawer.dart | 抽屉 tab 11→12.5（icon 14→16，圆角 5→8）、大纲子项 12→13（icon 12→14）、front-matter 字段 label 11→12、圆角 4→8 |
| editor_area.dart | 编辑 tab 12→13（icon 14→15）、空态副标题 13→14、快捷按钮 12→13 / 快捷键 10→11 |
| desktop_shell.dart | `_toolChip` 11→12（icon 15→16，圆角 6→8）；源码模式预览面板 0xFF1E1E2E 旧深紫蓝/0xFFFAFAFC → AppColor.surfaceRaised；前端信息卡硬编码 teal 色 → AppColor/ColorScheme |
| desktop_split_editor.dart | 视图切换按钮圆角 4→8 |

### P4-4 硬编码色收敛（已修复）

- desktop_shell 前端信息卡：`0xFFF0FDFA/0xFF99F6E4/0xFF0D9488/0xFF134E4A` → `surfaceHover/border/cs.primary/textSecondary`
- 源码模式右侧预览：`0xFF1E1E2E（旧深紫蓝）/0xFFFAFAFC/0xFFE5E5EA` → `surfaceRaised/border`

**遗留**：`_buildMarkdownPreview` 死代码链（800 行分散、夹杂活跃方法，删除风险高，保留）；
`_lastStatsHash` 已删除；两处 unused import 已清理。

**验证**：`dart analyze` 全部改动文件无 error（仅既有 `_buildMarkdownPreview` warning）；
需真机观察桌面整体字号/间距/圆角提升、亮色下无灰底拼贴、切主题无白边。

## Phase 5：写作页元数据收敛为 front matter 折叠面板

> 方案 C：仿 Typora/VSCode 极简。桌面端左侧列原元数据区（博文/页面大 toggle +
> 模板选择器 + 3 按钮 + 框架信息条 + 标签/分类 + 封面图 + 24 个工具栏 chips）
> 约占 400px+，正文只剩半屏。收敛后顶部只留「紧凑类型切换 + 标题 + 工具栏」，
> 元数据全部收进正文上方的可折叠 YAML 风格 Front Matter 面板。

**改动**（`lib/desktop/desktop_shell.dart`）：
- 顶部元数据区块（模板选择器 Row、框架信息条、标签/分类 Row、封面图框）整体移除；
- `_editorTypeToggle` 由双行大卡片（icon + label + subtitle 目录路径）压缩为
  单行紧凑 pill（icon + label，padding 12/10→10/6，圆角 10→8）；
- 新增 `_buildFrontMatterPanel(List<TemplateItem>)`：
  - 折叠态：`Front Matter` 标签 + 等宽字体摘要
    `title: x · tags: [a, b] · categories: [c] · cover: url · template: id`（无值显示「未设置元数据」），
    展开箭头切换；
  - 展开态：类型 pill（博文/页面）+ 模板下拉 + 「设为本仓库默认模板」/「管理模板」
    按钮 + YAML 风格字段行 `tags:`/`categories:`/`cover:`（等宽字体、teal key）+ 框架信息小字；
  - 字段绑定 `_doc.tagsCtrl/categoriesCtrl/coverCtrl/selectedTemplateId/articleType`，
    保存链路不变（Article 仍从 `_doc` 控制器构建 → `toMarkdownWithFrontMatter`）；
- `DocumentController` 新增公开 `refreshUi()`（调 notifyListeners），供 front matter 字段
  输入与顶部标题 onChanged 触发折叠摘要实时刷新；
- 修复过程中产生的 3 处 warning：`postDatePrefix ?? false` 死代码、
  `_doc.notifyListeners()` 越权访问、`_setAsRepoDefault` 因按钮移除而 unused（已加回）。

**验证**：`flutter analyze lib/desktop/desktop_shell.dart lib/controllers/document_controller.dart`
无 error（仅既有 `_buildMarkdownPreview` warning）；需真机确认折叠/展开交互、
摘要实时刷新、模板默认按钮可用、保存后 front matter 正常生成。

### P5-1 编辑模式宽度放开（已修复）

**问题**：`desktop_split_editor.dart` 纯源码编辑与纯预览模式沿用 PureWriter 的
`ConstrainedBox(maxWidth: 720)` 居中约束，在宽屏下写作区只有 720px，两侧大面积留白。

**改动**（`lib/desktop/widgets/desktop_split_editor.dart`）：
- `_buildSourceEditor` 移除 `Center + ConstrainedBox(maxWidth:720)`，TextField 占满
  编辑卡可用宽度（隐藏滚动条保留）；
- 纯预览模式 `_buildPreviewOnly` 保留 720px 居中（阅读舒适宽度，全宽影响阅读）；
- split 分屏模式本就按 `_splitRatio` 分配全宽，未改动。

**验证**：`flutter analyze` 无 error；需真机确认编辑模式占满写作区、分屏比例不受影响。

### P5-2 桌面写作页壁纸/纯黑/纯白背景 + 字色自适应（已修复）

**问题**：壁纸功能（bgMode 纯白/纯黑/自定义壁纸 + 自动字色适配）仅手机端移动编辑页可用，
桌面写作界面始终纯白，设置里切换 bgMode 无效果。

**改动**：
- `lib/desktop/widgets/desktop_split_editor.dart`：新增 `editorTextColor` 可选参数，
  源码编辑/分屏模式的正文文字色与 hint 色改用该值（null 时回落主题默认色）；
- `lib/desktop/widgets/frontmatter_card.dart`：新增 `background` 可选参数，
  容器底色改用该值（null 时回落 `AppColor.surfaceBase`）；
- `lib/desktop/desktop_shell.dart`：
  - 新增 `_wallpaperBrightness` 字段与 `_refreshWallpaperBrightness()`（读壁纸文件 →
    `ui.instantiateImageCodec` 缩到 32×32 → rawRgba 加权亮度平均，供字色自适应）；
  - 派生 getter：`_deskEditorTheme`（别名 `editor_theme_model` 规避与语法高亮主题
    `editor_themes.dart` 的类名冲突）、`_deskUseWallpaper`、`_deskBgColor`
    （bgMode1→黑，否则白）、`_deskCustomBg`（bgMode!=0）、`_deskTextColor`
    （forceTextMode 1/2 优先，否则壁纸亮度>0.5 黑/白、纯色背景按背景亮度）；
  - `_buildEmbeddedEditor` 改为 Stack：底层 `bgLayer`（壁纸 `Image.file` cover，
    errorBuilder→纯色；否则纯色 ColoredBox）+ 原 SingleChildScrollView；
    FrontMatterCard 传 `background`（自定义背景时半透明白 `_deskCardBg` 0.82），
    正文 `_editorCard(padding: zero, transparent: true)` 透明露出背景，
    DesktopSplitEditor 传 `editorTextColor`；
  - `_editorCard` 加 `transparent` 参数、`_editorTypeToggle` 非激活色在自定义背景时
    改用 `_deskCardBg`；
  - `initState` 触发 `_refreshWallpaperBrightness()`；`_updateSettings` 中 editorTheme
    变化时刷新亮度并 setState；
  - 修复 `_buildEmbeddedEditor` 方法尾括号（Stack 包裹后误删闭合括号导致 syntax error）。

**验证**：`flutter analyze` 无 error（仅既有 `_buildMarkdownPreview` warning）；
需真机确认：壁纸裁剪 cover、切换 bgMode 即时生效、文字在亮/暗壁纸下自动变黑/白、
强制字色优先、分屏/纯编辑/纯预览三种模式字色一致、专注模式暂未适配壁纸。

### P6 桌面极简写作模式（改造 focus，对齐手机端清爽范式）

**问题**：桌面端写作界面信息密度高——顶部 7 个图标 + 站点下拉，标题前 FrontMatterCard/
仓库选择器/类型切换 3 层前置，19-chip 工具栏常驻，标签页栏/状态条常驻，左面板默认展开。

**方案**（.monkeycode/specs/2026-09-06-desktop-minimal-writing/）：改造 `WorkMode.focus`
为「极简写作模式」，功能只隐藏不删除。

**改动**：
- `_focusModeTitleBar` 重写：☰+「拓墨·站点名」+ 保存✓ / 预览👁 / 更多⋮ + 窗口控件
  （补齐 min/max/close，窗口可拖动）；更多⋮菜单：元数据→右抽屉 frontMatter、
  格式化工具栏开关、AI 对话、一键发布、同步、主题、切回完整编辑模式。
- `_buildFocusEditor` 重构：外层 `Container(surfaceBase)` 双层背景 → `Stack`+
  `bgLayer`（壁纸/纯色，与工作台共用 `_deskUseWallpaper/_deskBgColor`）；移除作者/
  日期/字数元信息 chips；标题+细分隔线+正文两段式，80/64 大留白、maxWidth 860 居中；
  正文文字色用 `_deskCustomBg ? _deskTextColor : (isDark?白:常规)`；
  预览面板独立 `_focusPreviewOpen`（与右抽屉互斥）；更多菜单展开时正文下方显示
  完整 `_buildToolChips()` 工具栏。
- 选区悬浮工具条：正文 TextField 用 `contextMenuBuilder` 返回
  `AdaptiveTextSelectionToolbar`，选中非空时显示粗体/斜体/链接/引用迷你按钮。
- 工具栏 chips 提取为 `_buildToolChips()`（工作台常驻 + 极简展开共用，去重复）。
- 侧边栏折叠持久化：`UiSettings` 新增 `leftPanelCollapsed` 字段（json 序列化），
  `_toggleLeftPanel` 写回、`didChangeDependencies` 首次恢复。
- 新文章默认进入极简模式（`_newArticle` 末尾 `_switchWorkMode(WorkMode.focus)`）。
- 全局快捷键 Ctrl+Shift+E：极简 ↔ 完整模式（`Focus.onKeyEvent` + HardwareKeyboard）。
- 删除未使用的 `_focusToolbarButton`/`_focusMetaChip`。

**验证**：`flutter analyze lib/desktop/desktop_shell.dart lib/models/ui_settings.dart`
无 error（仅既有 `_buildMarkdownPreview` warning）；需真机确认：新文章进极简、
更多菜单各入口、选中正文弹迷你工具条、Ctrl+Shift+E 往返、左面板折叠重启保持、
壁纸背景在极简模式下生效。

---

## P7 电脑端全面复盘修复（2026-09-06）

**背景**：对电脑端全部代码（desktop_shell.dart + widgets/ 25 个组件）做全面审查，
并行 3 路：主壳逻辑、widgets 组件、极简模式交互需求核对。修复 high/medium 级问题
共 20+ 处。

**High 级修复**：
- **模式切换 UI 不重建**：`build` 原 `context.read<LayoutController>()`，全仓仅极简
  编辑器内部一处 `watch` → workspace/source 模式下点状态栏模式按钮、Ctrl+Shift+F/W、
  Escape 均无法切换到极简模式。改为 `watch<LayoutController>()` 驱动重建。
- **Ctrl+Shift+E 双绑定冲突**：desktop_main 原绑定 `Ctrl+Shift+E→sourceMode`，被
  shell 内 `Focus.onKeyEvent`（极简↔完整）抢先后变死代码。源码模式快捷键改为
  `Ctrl+Shift+Y`；shell 处理器加 `!event.repeat` 防长按抖动。
- **仅标题变化不保存**：`_onContentChanged` 只比较正文，只改标题既不改未保存标记
  也不进自动保存，关应用丢改动。新增 `_lastSavedTitle` 状态（+ `_EditorTabSession
  .lastSavedTitle`），比较条件覆盖 title+content，`_autoSaveSnapshot` guard 同步。
- **split 编辑器断言崩溃**：sourceOnly 模式 `expands: constraints.maxHeight.isFinite`
  与 `minLines` 并存命中 Flutter `!expands||(maxLines==null&&minLines==null)` 断言。
  `expands` 为 true 时 `minLines` 传 null。
- **命令面板空结果崩溃**：无匹配项按 ↑/↓ 时 `clamp(0, -1)` 抛 ArgumentError。
  空结果直接 return。
- **右侧抽屉标签栏溢出**：5 个 tab + 关闭按钮最小宽度约 434px ≫ 抽屉 280px，
  release 下右侧被裁切。改为 Expanded 均分 + 压缩 padding/字号/图标。

**Medium 级修复**：
- **预览/抽屉互斥漏洞**：预览开着时从更多菜单点「元数据/AI」静默无效（抽屉被渲染
  条件挡住但状态已置 true，关预览后抽屉突然弹出）。两分支先关预览再开抽屉。
- **Escape 逐级退出缺预览级**：`_handleEscape` 首条加关闭 `_focusPreviewOpen`。
- **极简状态跨模式残留**：`_switchWorkMode(focus)` 重置 `_focusShowToolbar`/
  `_focusPreviewOpen`，进入极简保持干净。
- **左面板折叠被模式切换覆盖**：`_switchWorkMode(workspace/source)` 原无条件
  `expandLeftPanel()`，覆盖持久化折叠偏好。改为保留当前折叠状态。
- **白字卡片不可读**：`_deskCardBg` 恒半透明白，壁纸+强制白字时白字白底。改为随
  `_deskTextColor` 亮度取白/深反色浮层。
- **极简右键空工具条**：无选区时补「粘贴」「全选」按钮，不再弹空气泡。
- **预览不含标题**：极简预览 `markdown` 拼接 `# 标题\n\n正文`（监听 titleCtrl）。
- **常驻打字机指示条**：极简底部小胶囊移除（R1.2 隐藏状态残余）。
- **分组折叠全展开无法持久化**：`UiSettings` 新增 `collapsedLeftSectionsSet` 区分
  「未设置」与「显式空列表」，左面板 initState 按标志取值。
- **FrontMatterCard 破坏 YAML 列表**：编辑任一字段用 `toYamlBlock()` 整块重写为
  单行 `key: value`，破坏 `tags:\n- a\n- b` 列表/注释/多行。改为 `_rewriteYamlBlock`
  原位行级替换（仅动目标 key 及续行，含删除）；顺带修复前导空白丢弃、全删后空块
  处理。
- **FrontMatterCard 背景联动**：`background` 参数与字段文字色不联动（按 isDark
  硬编码）。改为按传入 background 亮度判定 `_cardIsDark`。
- **关闭最后一个标签残留**：`_tabSessions` 不清理、`_doc` 不重置。补会话/防抖/映射
  清理 + 控制器清空 + 进入空态。
- **`_saveLocal` 未同步 `_lastSavedContentMap`**：手动保存后自动保存 guard 误判产生
  重复落盘。4 处保存点补 map 写入。
- **拼写检查建议词丢弃**：面板点击建议词回调只传 result（固定取 suggestions.first）。
  `SpellCheckResult` 加 `copyWith`，面板把选中建议写入回调。
- **Markdown 格式化破坏代码块**：中英空格/表格对齐/空行压缩/标题补行均不感知围栏，
  会在 ```` ``` ```` 内改内容。重写为围栏感知分段：代码块内部原样保留。
- **split 分隔线拖拽基准**：原用窗口总宽计算比例增量，侧栏/抽屉打开时手感错位。
  改用 `LayoutBuilder` 实际分栏宽度。
- **打字机居中偏移**：光标居中计算未计入顶部标题区（约 162px），光标偏低不居中。
  加 `_focusHeaderOffset` 常量。
- **`_lastCursorLine` 切换不重置**：加载会话/新建文章时归零，避免高亮条残留在空白区。
- **壁纸 Codec 泄漏**：`_refreshWallpaperBrightness` 中 `codec.dispose()`。

**第 2 轮深度修复（High）**：
- **极简编辑器双右抽屉渲染**：`_buildFocusEditor` 内重复渲染 `_buildRightDrawer` 的
  冗余块（AI 面板被挂两次、GlobalKey 复用）已删除，仅保留主体抽屉一次。
- **仅标题保存判据跨文章污染**：`_lastSavedTitle` 单值镜像，切换会话后标题误判为
  "已保存" 或把 A 文章标题当 B 基线。新增 per-article `_lastSavedTitleMap`，与
  `_lastSavedContentMap` 一致在保存/发布/新建/切换会话/清空 5 处同步。
- **后台自动保存覆盖当前编辑**：`_autoSaveSnapshot` 后台保存其他文章时，条件收紧为
  「`aid == _doc.currentArticle.id && _doc.contentCtrl.text == c`」才落草稿，避免用
  陈旧快照覆盖用户正在编辑的激活文章。
- **关闭左侧标签下标越界**：`EditorController.closeTab` 关闭激活标签后 `_activeTabIndex`
  未左移，列表收缩后越界。补 `--`；shell `_closeTab` 仅在关闭激活标签时重新加载会话。
- **窗口可被 X 直接关闭**：`desktop_main._initWindow` 加
  `await windowManager.setPreventClose(true)`，统一走关闭确认/保存拦截。
- **快捷键修改后命令面板不生效**：`_loadEditorSettings` 加载 shortcuts 后回灌
  `widget.onShortcutsChanged?.call()`。
- **FrontMatterCard YAML 空行累积**：`_rewriteYamlBlock` rest 段去换行前缀
  `replaceFirst(RegExp(r'^\n+'), '')`，连续编辑不无限堆空行。
- **定时发布 dialog dispose 竞态**：`_schedulePublish` 的 showDialog 未 await，finally
  立即 dispose dateCtrl/timeCtrl，dialog 还在用。改 `Future<void>` + `await`。

**第 2 轮深度修复（Medium）**：
- **find/replace dialog dispose 竞态**：`_showFindReplace` showDialog 未 await 时 dispose
  被引用的 controllers。改 `Future<void>` + `await`，finally 在 dialog 关闭后执行。
- **caseSensitive 反向错误**：`_showFindReplace` 及 4 处 `build` 分支 `caseSensitive
  ? false : true` 反向，UI 勾选与行为相反。批量改回直接传 `caseSensitive`。
- **保存后脏标记未清**：`_onContentChanged` 防抖回调（当前文章）保存后 `_doc.markSaved()`。
- **格式化对四反引号围栏失效**：`MarkdownFormatter` 围栏正则 `^(`{3,}|~{3,})` 配对
  校验 fenceMarker 长度，支持 ```` ```` ````；行内代码/链接 URL 用占位符保护防被改。
- **打字机高亮条整壳重绘**：新增 `ValueNotifier<int> _focusCursorLine` 局部刷新，替代
  `_trackStats` 里整壳 setState；`_loadSessionIntoDoc`/`_newArticle` 重置 notifier。
- **AnimatedSwitcher 重建 TextField**：`desktop_split_editor` 源码/分栏切换改用直接返回
  body（切换保留滚动/焦点/选区）。
- **命令面板 FocusNode 二次 attach 崩溃**：command_palette TextField 与 KeyboardListener
  共享单 FocusNode 触发断言。拆独立 `_keyboardFocusNode`。
- **新建文章覆盖未保存草稿**：`_newArticle` 覆盖 `_doc` 前先
  `_saveSessionFromDoc('editor_${_doc.currentArticle.id}')`。
- **主题色选择器不刷新**：`_showThemeColorPicker` 修改主题色后 `if (mounted)
  setState(() {})` 让界面即时反映。
- **Escape 双重触发**：`_handleKey` 返回 void，命令面板关掉后事件继续冒泡到全局
  escape（关抽屉/切模式）。改返回 `KeyEventResult.handled` 消费事件。
- **AI 发送 300ms 固定延迟丢消息**：`_sendFullToAi`/模板插入用 `Future.delayed(300ms)`
  发送，面板动画期间关闭则静默丢失。改 `_sendToAiChatWhenReady` 轮询等待面板挂载
  （50ms×20 次上限）后发送。
- **拖入无扩展名文件静默丢弃**：`editor_drop_target` 未知/无扩展名文件不落入任何分支。
  兜底按纯文本读取插代码块，二进制读取失败跳过。

**遗留（记录，不修/待定）**：
- 「选中即弹出」悬浮工具条：`contextMenuBuilder` 在桌面端仅右键触发，鼠标拖选不自动
  弹。实现 Overlay 浮层成本高，暂以右键工具条 + 更多菜单工具栏开关替代，待用户反馈。
- 极简 ☰ 点击 = 展开左面板并切回完整模式（与「切完整模式」入口等价），保留现状。
- 元数据抽屉缺 模板/类型/仓库 字段（工作台可编辑），暂不补。
- 源码/分栏切换滚动位置归零（AnimatedSwitcher 重建 TextField），暂不迁移。
- 标题栏整行拖拽与按钮 tap 竞争：标准无边框窗口行为，保留。

## P8 第三轮深挖（2026-09-06，提交后待补 hash）

- **多标签共享 FocusNode 崩溃**：`editor_area` 用 IndexedStack 保活全部标签，多个标签
  共享同一 FocusNode/controller 触发 "A FocusNode cannot be used in multiple widgets"
  断言。改 IndexedStack 仅挂载激活标签（非激活返回 SizedBox.shrink）。
- **dialog 打开时全局快捷键误触发**：`_openProxySettings`/`_openGlobalSearch`/
  `_showSnippetManager`/`_showCustomCssEditor` 改 `Future<void>` + `await showDialog`
  串行化，防止连续打开叠加。
- **切换文章未保存会话**：`_openExistingArticle` 首次打开前先
  `_saveSessionFromDoc(currentId)`，避免切换后 AI 上下文/会话丢失。
- **发布覆盖编辑器内容**：新增 `DocumentController.updateCurrentArticleMeta`（只更新
  元数据+比较文本设 hasUnsaved，不写文本域）；3 处发布路径（git mirror / CMS /
  github.upsertArticle）检测发布期间用户编辑，有编辑则用 meta 更新保留编辑器内容。
- **异步回调 mounted 保护**：ai_chat_panel `_writeAllFiles`、`_loadHistory`、shell
  `_autoPullFromCloud` 补齐 `if (mounted)`，防关闭后 setState 崩溃。
- **AI 面板卸载副作用**：dispose 调 `widget.dispatcher.cancelCurrent()`，防止工具副作用
  继续执行与旧回执串入新会话。
- **退出丢未保存草稿**：`_flushAllPendingSaves` 增加遍历 `_pendingSaveMap` 残留落盘；
  shell 暴露公开 `flushAllPendingSaves()`；onWindowClose/托盘退出/后台生命周期都调用；
  `didChangeAppLifecycleState` 后台冲刷不再被 `draftSyncEnabled` 门控。
- **元数据变化不触发保存**：`_onContentChanged` 纳入 tags/categories/cover 变化检测；
  `_autoSaveSnapshot` 加 `force` 参数；防抖回调元数据变化时 force 保存；落草稿保留原
  isDraft/published 不降级。
- **快照按文章隔离**：`session_service.listSnapshots` 改 safeId 前缀匹配（含下划线 id）；
  `openExternalFile` 用 `filePath.hashCode` 稳定 id（重复打开复用标签）；
  `editor_drop_target` markdown/text 读取加 try/catch。
- **快捷键设置控制器泄漏**：`_showShortcutEditor` 预创建 controllers 并在 finally dispose；
  desktop_main `_addDefaultBindings` 补齐 bold/italic/strikethrough/link/h1-h3/pasteImage/
  find/replace（Ctrl+K 从命令面板改 link）；`_rebuildShortcuts` 空串=禁用默认绑定，
  新增 `_defaultActivators` 映射。
- **云同步并发写坏**：`_autoSyncing` 布尔互斥 autoSync/autoPull；ai_chat_panel
  `_saveHistory` 链式 Future 串行防并发写坏 JSON；sendMessage busy 时先 `_cancelStream()`
  再发（不再静默丢弃）。
- **AI 会话跨文章残留**：AiChatPanel 传 `historyKey: 'article_${id}'` 按文章隔离历史。
- **文章类型切换模板错配**：`_autoSelectTemplate` 按 articleType 选 post/page 解析器；
  切换类型后旧类型模板先清除，避免 Dropdown value 不在 items 触发断言崩溃。
- **缓存清理 pop 竞态**：`_openCacheCleanup` 用 `ctx.mounted`（dialog context）替代
  `mounted`（shell 恒 true）。
- **语法修复**：`_onContentChanged` 方法体缺闭合 `}`；`_showFindReplace` finally 误引用
  `ctrls`（应 dispose findCtrl/replaceCtrl）；`_showShortcutEditor` finally 引用
  `shortcut`（改 `ctrl.text`）；L1630 注释与 `if` 同行吞掉代码块破坏 try/catch。

## P9 默认工作区 MarkText 化布局（2026-09-10）

**背景**：默认工作区 `_buildEmbeddedEditor`（标签页编辑器）沿用固定高度（`height:600`）
加外层 `SingleChildScrollView`，标题、工具栏、元数据、编辑器全部堆在滚动列里，编辑器无法
占满可视高度，属性区（`FrontMatterCard` + 仓库选择器 + 类型切换 + Front Matter 面板）持续
挤占正文。

**方案**：对标 MarkText 沉浸式布局，改为「固定顶栏 + 折叠属性区 + 编辑器占满 + 状态栏」。
专注/源码模式、移动端不动。

**改动**（`lib/desktop/desktop_shell.dart`、`lib/desktop/widgets/right_drawer.dart`）：

- `_buildEmbeddedEditor` 重构为
  `Stack[背景, Column[顶栏(标题+属性开关+工具栏), 折叠属性区, Expanded(编辑器), footer]]`：
  外层 `SingleChildScrollView` 改为 `Column`（消除无界高度），删除 `SizedBox(height:600)`，
  编辑器改 `Expanded` 占满剩余高度；
- 新增 `_showEditorMeta` 状态（默认 `false`）：仓库选择器与 Front Matter 面板收进
  `if (_showEditorMeta)` 折叠区，`ConstrainedBox(maxHeight: 屏高*0.5)` 内滚，不挤占编辑器；
- **P2 数据源统一**：移除 A 卡 `FrontMatterCard` 及其 import。原因：`Article.fromMarkdown`
  加载时剥离 YAML（`content` 仅正文），A 卡却把 YAML 写回 `content` 开头，发布时
  `toMarkdownWithFrontMatter` 生成 front matter 再拼 `content`，产生**双重 front matter**。
  属性统一走 B 面板（`_doc.tagsCtrl/categoriesCtrl/coverCtrl/selectedTemplateId/articleType`，
  与发布链路一致）；`title` 走顶栏，`date`/`slug` 发布时自动生成。同时删除与 B 面板重复的
  独立类型切换 Row 及因此 unused 的 `_editorTypeToggle`；
- **P4 抽屉 date 孤儿**：`right_drawer.dart` 移除无绑定的 `dateCtrl` 构造参数与「日期」输入
  （抽屉 frontMatter 5→4 字段），消除写入无效的孤儿控件。

**T0 对标核查清单复盘（T0.1–T0.8）**：

| 项 | 核查项 | 状态 |
|---|---|---|
| T0.1 | 专注模式隔离边界（`_buildFocusEditor` 独立分支） | 达标（逻辑未动，仅 `dart format` 格式重排） |
| T0.2 | `_buildEmbeddedEditor` 结构与 600 高约束来源 | 已解决（删 600，改 `Expanded`） |
| T0.3 | 渲染链事实（防抖/ListView/SCSV 双滚动/高亮） | 外层达标；内层双滚动（`DesktopSplitEditor` SCSV + `Markdown` ListView）既有，未动 |
| T0.4 | titleCtrl 跨面板复用 / 抽屉 5 字段 / 抽屉宽 280 | 达标（titleCtrl 三处共用；抽屉 5→4 字段；宽 280 未变） |
| T0.5 | 无 `isDesktop` 运行时分支 | 达标（新增计数 0） |
| T0.6 | 不引入 `fluent_ui` | 达标 |
| T0.7 | 主题色专属桌面变量隔离 | 达标（`_desk*` 逻辑未改） |
| T0.8 | 长文 build 实测门禁 | 未完成（本环境无 Flutter 运行时） |

**验证**：`dart analyze lib/desktop/desktop_shell.dart lib/desktop/widgets/right_drawer.dart`
0 error（仅既有 `_buildMarkdownPreview` warning）；整 `lib/` 仅 5 处既存 `lib/platform/`
条件编译误报。`git diff` 仅这两个桌面文件，移动端/`main.dart` 零改动。

**遗留**：

- T0.8 长文首帧性能未实测，需 CI/真机；
- 编辑器/预览内层双滚动仍在（既有）；
- `dart format` 重排全文件，diff 混入格式变动（focus/source 区域仅格式、无逻辑变化）；
- `lib/desktop/widgets/frontmatter_card.dart` 成 dead code（按规范保留未删）。

---

## P10 复盘缺陷全量修复（批次 A–G，2026-09-10，准备随正式版发布）

针对 `docs/DESKTOP_REVIEW.md` 的 H1–H2 / M1–M8 / L1–L22 缺陷清单，
分批 A–F 完成代码修复，批次 G 全量验证 + 写本文档。全量改动未单独推送，
作为正式发布的一部分统一提交。

### 批次 A —— 数据安全

- **H1 发布覆盖未保存内容**：`_handlePublish` / `_publishToCms` / `_executePublish`
  三处发布从 `_collect(draft:false)` 改为
  `userEdited ? _collect(draft:false) : pub`，发布中不覆盖用户会话提交。
- **H2 会话元数据散失**：`_EditorTabSession` 增 `articleType` / `templateId` /
  `splitMode` / `splitRatio`，`_loadSessionIntoDoc` / `_saveSessionFromDoc` 双向存取还原。
- **M1 元数据未保存识别**：`_onContentChanged` 将 tags / categories / cover 变化计入未保存标记。
- **L5 新文章标签 id**：`_newArticle` 改用 `_doc.currentArticle.id`。
- **L6 自动保存守卫**：`_savingLocal` 标志避免保存重入。
- **L7 快照纳入元数据**：`_PendingSave` / `_autoSaveSnapshot` 纳入 tags/categories/cover。
- **L17 拆分符**：拆分符 `RegExp(r'[,，]')` 兼容中英文逗号。

### 批次 B —— 工作区 UI

- **M2 元数据面板与底栏水平留白**：`Padding(horizontal:16)`。
- **M7 元数据面板高度上限**：新增 `_metaPanelMaxHeight(context)`（`dart:math`），
  替代硬编码 `0.7*height`。
- **M4 拆分比例写回父级**：`_setSplitRatio` 回写 + 百分比按钮复用。
- **M5 分屏受控同步**：`desktop_split_editor.dart` `didUpdateWidget` 同步
  `_mode` / `_splitRatio`。
- **L15 比例控件窄屏抑制**：加 `&& !narrow`。

### 批次 C —— 共享组件

- **M3 语法高亮缓存失效**：`markdown_syntax_highlighter.dart` 两个控制器
  `updateColors` 清 `_cacheText` / `_cacheSpans`。
- **L9 注释改字素说明**。
- **L10 预览按字素截断**：`debounced_markdown_preview.dart` 用 `characters` 包。
- **L11 预览全样式等比缩放**：`MarkdownPreviewSmooth` 按 `fontSize/16` factor
  缩放 h1–h6 / code / table 等所有样式（不依赖 baseStyle，因标题用的是绝对字号）。
- **L12 大纲代码围栏**：`right_drawer.dart` `parseOutline` 加 ``` ``` 状态机。
- **L13 左栏长按定位**：`left_panel.dart` 用 `onLongPressStart(details.globalPosition)`。
- **L14 状态栏 / 标题栏溢出**：`status_bar.dart` 尾部 `Expanded>SCSV(horizontal,reverse)`、
  `title_bar.dart` 快捷按钮 `Expanded>Align>SCSV`、站点下拉 `maxWidth:220`、
  `editor_area.dart` 空态 `SCSV`。

### 批次 D —— 控制器 / 服务

- **L16 FrontMatter.copyWith 哨兵**：`static const _unset` 支持清空 cover/date/template。
- **L18 模板同步 catch**：`template_sync_service.dart` 提前 `return TemplateSyncResult`。
- **L19 站点切换回滚**：`site_controller.dart` `switchSite` catch 回滚 `_activeSiteId` + rethrow。
- **L20 站点隔离落盘**：`site_isolation_service.dart` `_saveCurrentSiteState` 落盘当前 config。
- **L21 同步态复位**：`sync_controller.dart` `setError(null)` 复位 idle、
  `startAutoSync` / `setAutoSyncInterval` 最小间隔 10s。
- **L22 加密文件备份**：`draft_encryption_service.dart` 解密成功后
  `.enc` → `.enc.bak`（可回滚，避免解密断点损坏原件）。
- **L1 firstWhere 空判**：`desktop_shell.dart` / `editor_ui_ext.dart` 改
  `where().firstOrNull` + 空判。

### 批次 E —— 死代码 / 杂项

- **L2 导出菜单定位**：`_showExportMenu` offset `(0,-200)` → `(0,-8)`。
- **L3 死代码清理**：Python 脚本删 `_getHighlightTheme` / `_buildHighlightedCode` /
  `_buildMarkdownPreview` / `_renderPlainMarkdown` / `_buildInlineLatexMarkdown` /
  `_buildCustomMarkdownStyleSheet` / `_buildMermaidPreview` / `_buildLatexPreview` /
  `_SpecialBlock` 类 + 相关 import（flutter_highlight / flutter_markdown）+ `_currentEditorTheme`；
  备份 `/tmp/opencode/desktop_shell.before_deadcode.dart`。搬迁后
  `desktop_shell.dart` ~12436 → ~12016 行，0 error / 0 warning。
- **L4 标签标题回写**：`EditorController.updateTabTitle(id,title)` +
  shell `_onTitleChanged()` 监听 `_doc.titleCtrl`（`_loadingSession` 守卫 +
  `_editor` 边界）+ initState/dispose 注册移除；`_loadSessionIntoDoc` 用
  `_loadingSession` try/finally 抑制。
- **L8 专注模式光标居中头部偏移重算**：`_focusHeaderOffset` 从旧 `64+41.6+28+1+28`
  改为按 `_buildFocusEditor` 实际布局
  `48 + (28*1.3 + 28) + 16 + 1 + 16`（含标题 contentPadding 2×14）。

### 批次 F —— 移动端缺陷（共享 mixin）

- **自动保存把已发布文章降级为草稿**：`editor_text_ext.dart` `_autoSaveSnapshot`
  `_saveDraft(_collect(draft:true))` 改为仅当前文章时
  `copyWith(isDraft: current.isDraft, published: current.published)`，后台文章回退原逻辑。
- **标题-only 改动不置未保存**：mobile `_onContentChanged` 同时比较 content+title
  （新增 `_lastSavedTitleMap`，main.dart 声明 + `_startAutoSave` 种子化 +
  `_autoSaveSnapshot` 记录）；`_autoSaveSnapshot` 早退守卫加入 title；
  initState 注册 `_doc.titleCtrl.addListener(_onContentChanged)`，dispose 移除。
- **模板下拉断言**：`editor_ui_ext.dart` 与 `desktop_shell.dart` 两处
  `DropdownButtonFormField.value` 改为「值必须属于当前类型过滤后的可选项，否则回退 null」，
  规避切换文章类型后 `_autoSelectTemplate` 提前返回留下的失效模板 id 触发断言。

### 批次 G —— 全量验证

- `dart analyze`（desktop / widgets / controllers / mixins / services）：0 error；
  仅既存 `withOpacity` / `curly_braces` info 与平台条件编译误报。
- `flutter test`：16/16 全绿。
- 附：`_focusHeaderOffset` 为基于布局的近似值；桌面英文官网链接沿用
  ghfast.top 代理（发布时由 `release.sh` 生成新 tag 下载 URL）。
