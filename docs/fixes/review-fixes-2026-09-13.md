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
