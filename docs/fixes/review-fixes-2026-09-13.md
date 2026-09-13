# 复盘修复 + 手机端实验性所见即所得（路线B）

日期：2026-09-13
范围：CI/发布脚本、保存链路、死代码清理、门面收口、健壮性、移动端编辑器
前置文档：`docs/fixes/codebase-review-2026-09-13.md`（一轮全量复盘发现清单）

## 一轮复盘问题修复（对 Review 清单逐项落实）

1. **CI 门禁收紧**：analyze job 删除伪装成检查的 `dart format || true`（230/262 文件
   本就未格式化，不设假门禁）与 `flutter analyze || true`，改为
   `flutter analyze --no-fatal-infos` 硬门禁 + 新增 `flutter test` 硬门禁；
   `test_batch_publish.dart`/`test_localizations.dart` 改名 `*_test.dart`
   （旧命名会被 flutter test 静默跳过）；release job 删除 `continue-on-error`
   （job 级 + download 步骤级），Verify artifacts 缺产物从 warning 改为 exit 1。
2. **保存链路收敛**：EditorController 空转保存队列（SaveTask/enqueue/flush/
   onBeforeClose，从未入队=关窗强制落盘是 no-op）整体删除，desktop_main 关窗/托盘
   退出只走真实的 flushAllPendingSaves；桌面 `_autoSaveSnapshot` 与手机端自动保存
   失败从仅 debugPrint 改为用户可见提示（编辑器状态行 + toast）。
   复盘误报更正：桌面「失败图片重试」链路实际已接线（shell_text_ext 多处
   setFailedImageBytes），未改动。
3. **死代码大清理**（全部经引用计数验证后删除）：AppFileOperator 抽象层
   （core/file_manager + platform/ 三实现 + platform_resolver，全仓零调用）、
   FrontMatterController（Provider 注册后零消费，双 main 注册一并删除）、
   editor_screen.dart + .bak（被 git 跟踪的旧版编辑器）、5 个零引用页面
   （log_panel/mobile_diff/mobile_snapshot/skill_editor/unified_remote_posts）、
   WebView 预览备选方案全套（markdown_preview_webview + preview_debug_store +
   local_asset_server + assets/preview 共 ~4MB 死资源）、git_service 等 7 个死服务、
   editor_animations/editor_menu_widgets/focus_mode_overlay/code_highlight/
   markdown_syntax_highlighter 孤儿组件、tool_format_adapter；
   pubspec 移除 flutter_highlight/highlight（零引用）与 assets/preview 注册。
   控制器瘦身：SyncController 精简为纯日志（状态机/自动同步定时器全仓零调用，
   顺带消除 in-flight dispose 崩溃风险）、SiteController/LayoutController/
   UiStateController/EditorController 删除零调用方法与字段。
4. **门面收口**：site_health_monitor.triggerBuild 不再自建 HttpClient 硬编码
   api.github.com，改走 GitHubProvider.request；site_management_screen 四处
   `GitHubProvider().xxx` 收敛为 GitHubService 门面新方法
   （repoIsPrivate/setRepoVisibility/repoActionsRun/setRepoCustomDomain）。
5. **健壮性**：storage_service 临时目录静默降级改为醒目日志（数据会丢必须可见）、
   配置文件损坏先改名留存 `.corrupt-<ts>` 再返回空（防覆盖丢失）；cms_draft_service
   预置 onUpgrade 迁移骨架；shell_publish_ext 三处发布 await 后补 mounted 防护
   （其中 _publishToCms 按「先本地持久化、后 UI 刷新」重排，卸载不再丢 CMS 映射）。
6. **移动端缺口**：阅读页 article_reader_screen 从 flutter_markdown 切
   MarkdownPreviewSmooth（表格/公式/mermaid 与双端一致）；定时发布补齐移动端
   （原生日期/时间选择器 + Timer 到点 _publish，发布菜单新增入口）。
7. **release.sh**：显式 `--version 1.2.0`（无 +build）自动补构建号（原来直接
   int("1.2.0") 崩溃）；推送从写死 main 改为当前分支。

## 手机端实验性所见即所得（路线B）

- 入口：编辑页顶栏「眼睛（预览）」左侧新增 auto_stories 开关，会话级生效，
  开启时高亮并 toast 提示。
- 实现：`lib/widgets/wysiwyg_smooth_editor.dart`（新增）桥接
  flutter_smooth_markdown 的 `SmoothMarkdownEditor(formatted)` 模式——未聚焦块
  渲染成品、点入块编辑（Notion/实时预览式混合所见即所得）；块编辑底层是普通
  TextField，中文输入法走 Flutter 标准通道（避开 super_editor 移动端 IME 风险）。
- 数据流双向桥接：组件内编辑 → onChanged → contentCtrl.text（沿用既有链路）→
  onAfterWriteBack → `_onContentChanged`（未保存标记 + 自动保存防抖不断链）；
  外部程序化改动（AI/图床插入/切文章）→ 监听 contentCtrl → editor.text。
  组件背景透明化，手机端壁纸/纸面底色可透出。
- 桌面所见即所得（super_editor 路线）不受影响；实验开关随时可切回源码编辑，
  内容实时同步不丢字。
- 已知边界（待真机验证）：块焦点/键盘弹出滚动跟随/长文性能；打字机滚动在该
  模式暂不可用。

## 二轮复盘修复（实施后复审）

- main.dart 未用 flutter_markdown import 删除（新 analyze 门禁下会红）；
- 实验所见即所得保存链路补齐（onAfterWriteBack，见上）；
- _publishToCms mounted 早退重排（本地映射先行）；
- 帮助文案去除 flutter_highlight 引用、注释错位修正、面板未用参数删除。

## 验证

- `dart analyze lib test`：0 error / 0 warning（704 个存量 withOpacity 等 info
  为历史风格噪音，不设门禁）。
- `flutter test` 与四端构建由 CI 执行（见 push 后 `gh run list`）。

## 补充：安卓真机反馈修复（2026-09-13 第二批）

用户安卓真机实测反馈两个问题：

1. **自动保存失败 `path = '/tmp' (Read-only file system)`**——根因是
   `SessionService._baseDir()` 依赖 `Platform.environment['HOME']`，安卓应用
   拿不到环境变量，落到硬编码 `/tmp`（只读）。该 bug 是历史存量（此前静默
   失败），本轮「自动保存失败可见化」将其暴露。修复：移动端改走 path_provider
   `getApplicationDocumentsDirectory()/.hexo_app`，桌面保持 HOME/USERPROFILE
   存量路径。同批修复移动可达路径上全部 5 处 `Directory.systemTemp` /
   `/tmp`（session/github 批量 CLI/remote_cms 上传/theme_store 解压/
   theme_migration 克隆），统一换 `getTemporaryDirectory()`。

2. **安卓「所见即所得」不可用**——CI widget test 复现：flutter_smooth_markdown
   的 `SmoothMarkdownEditor` formatted 模式整树空渲染（无异常、无文本）。
   按用户指 引改用安卓开源生态验证过的主流形态（Markor/SoloMD）：**分屏
   实时预览**。新增 `lib/widgets/split_preview_pane.dart`（公开组件，4 个
   widget test 全过）：上半屏原源码编辑（自动保存/打字机链路原样），
   下半屏 MarkdownPreviewSmooth 实时渲染，中缝可拖拽（ValueNotifier 局部
   刷新）。弃用并删除 `WysiwygSmoothEditor`；flutter_smooth_markdown 仅
   保留渲染器用途。桌面 super_editor 所见即所得不受影响。

架构文档已同步（ARCHITECTURE.md 移动端章节 + 坑清单 #16/#17）。

## 补充：路线一真·所见即所得 + 分屏消卡顿（2026-09-13 第三批）

用户拍板：真·所见即所得走路线一（WebView + 成熟编辑引擎），同时解决分屏卡顿。

1. **分屏预览消卡顿**：`SplitPreviewPane` 改为 StatefulWidget，预览侧
   「停手 600ms 才渲染」空闲防抖（打字期间整篇重解析重建是卡顿主因），
   下半屏加 RepaintBoundary。测试拆成两个用例：注入 50ms 短防抖验证
   编辑→预览链路、显式 600ms 验证打字期间预览静止。
2. **路线一落地（WebView/TipTap/ProseMirror）**：
   - `tools/wysiwyg-builder/`：npm + esbuild 把 TipTap v2（StarterKit +
     Link/Image/Table/TaskList/Placeholder）+ marked + turndown(GFM) 打包为
     单文件 IIFE（416KB）提交入库；各 @tiptap 包版本统一 ^2.x 浮动
     （core 与 extension 版本错位曾报 No matching export）。
   - `assets/wysiwyg/web/editor.template.html`：透明背景纸感主题 + 暗色切换。
   - `lib/widgets/wysiwyg_web_editor.dart`：markdown 拆 frontmatter → marked
     转 HTML 灌 TipTap；编辑防抖 400ms → turndown 回 markdown → 写回
     contentCtrl（回环由 _lastKnownBody/applyRemote 双侧挡住）；安卓走
     WebViewAssetLoader 虚拟域（Binder 1MB 限制，沿用手势验证过的旧预览方案），
     其余平台内联；加载失败 onFatalError 自动退回源码模式并 toast。
   - 编辑面 v1 边界：数学/mermaid 为代码文本态（渲染由分屏预览负责），
     无选中格式工具栏（markdown 输入 rules 内建，打 **加粗** 即变粗体）。
3. **验证**：CI 全绿（analyze + test + 四端构建）。WebView 编辑器无法在
   widget test 中运行（平台视图限制），真机编辑体验（中文输入/气泡菜单/
   长文流畅度）待用户实测。

## 补充：第四批（自动保存静默 + 所见即所得公式/表格）

1. **自动保存成功改静默**：双端移除「草稿已自动保存」成功 toast
   （保存状态由状态栏/保存指示灯反馈），失败提示保留。
2. **WebView 编辑失败排查强化**：编辑器 bundle 全平台内联进 initialData
   （418KB，远低于安卓 Binder 1MB），不再依赖虚拟域加载主脚本；失败时
   原因（JS console 错误/init 异常/主框架加载错误）直接显示在失败 UI 与
   toast 中；favicon 等子资源错误不再误判为致命。
3. **真所见即所得公式渲染**：editor.js 移植 MarkdownPreviewBuilder 的
   数学占位保护（先摘 $$..$$/$..$ 再过 marked，避免公式内 _ * 被当语法，
   无 lookbehind 以兼容 Safari 14），新增 MathInline/MathDisplay TipTap
   原子节点（KaTeX nodeview，KaTeX 缺失/渲染失败优雅回落原文），turndown
   增加公式回转规则（data-latex → $..$/$$..$$）；KaTeX css/js/字体重新
   入库（安卓经虚拟域、iOS 内联）。占位提取/还原逻辑经 node 脚本验证。
4. **表格**：markdown 表格经 marked(GFM) → TipTap Table 渲染为可编辑表格
   （链路本就通）；注意在所见即所得面内直接敲 | 语法不会自动建表
   （建表走源码/分屏模式插入后切换）。

## 补充：第五批（双端全面复盘修复，2026-09-13）

审计代理对双端全面复盘，以下问题全部修复：

- **高1** 移动端生命周期冲刷被 `draftSyncEnabled`（默认 false）挡掉，后台
  2s 防抖窗口内输入直接丢失——本地冲刷改为不依赖云同步开关（对齐桌面）。
- **高2** 移动端防抖保存跨文章污染：元数据改为触发时捕获进 _DebounceEntry
  （对齐桌面），定时器到点非当前文章直接跳过；`_autoSaveSnapshot` 非当前
  文章绝不 `_saveDraft(_collect())`（曾把已发布文章降级为本地草稿）。
- **中3** WebView 编辑器装载期（0.5~2s）外部改动只跳过推送不更新基线，
  曾致 init 用陈旧内容装载、一打字覆盖外部新内容——基线始终更新。
- **中4** 移动端发布完成无条件 `setCurrentArticle(pub)` 回滚用户编辑
  （分屏/所见即所得模式发布期间可输入）——移植桌面 userEdited 检测
  （静态 Git 发布与 CMS 发布两处）。
- **中5** 多站点发布预览选「取消」后 `_editorBusy` 永不复位卡死——补复位。
- **中6** `session_service.listSnapshots` 用 `/` 分割路径，Windows 反斜杠
  路径永不命中 → 快照清理失效无限累积——改双分隔符正则。
- **中7** 分屏预览未传 darkTheme，深色壁纸下预览不可读——按文字亮度自适应。
- **低8** 模式开关互斥不对称（分屏不清 WebView 标志）——补对称。
- **低9** 桌面所见即所得 dispose 无条件写回，零编辑进出也产生 round-trip
  diff 噪音——加 _dirty 标记，未编辑不写回。
- **低10** 定时发布 Timer 到点执行「当时的当前文章」，期间切文发错文——
  双端绑定 articleId，切换即作废并提示。
- 接受边界（不修）：frontmatter 正则对 4 连字符开头文档的错切（无数据
  损失）；分屏↔源码切换瞬态 ScrollController 双 attach（理论风险）。
