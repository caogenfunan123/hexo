# 全量代码复盘（2026-09-13）

> 范围：lib/ 全部 263 个 Dart 文件 + test/ + CI + 发布链路 + 资源。
> 方法：三路并行审计（桌面端 / 服务与核心层 / 移动端+测试+CI），引用计数验证后定性，
> 「疑似」标注表示 grep 零引用但未逐行动态验证。本文档只记录事实与建议，未做代码变更。

## 总体结论

| 域 | 结论 |
|---|---|
| 桌面端 shell | 健康。本轮改动（阶段6）集成一致、无残留引用；Escape/模式切换/总线接线自洽 |
| 服务与核心层 | 功能基本健康，**架构约定未兑现**：AppFileOperator 抽象层整个是死代码；GitHubService 门面被多处绕过 |
| 移动端 | 基本健康，带 5 个死页面 + 1 个被 git 跟踪的 .bak；阅读页渲染引擎掉队 |
| 测试 | **不健康**：CI 完全不跑测试；2 个测试文件命名不符约定被静默跳过；五大核心链路零测试 |
| CI 与发布 | 一致性良好（产物命名/release.json/版本三处同步全对齐），**门禁形同虚设**（analyze 永不失败、release 容错） |
| 安全 | 硬编码 token/密钥：零。站点加密实现合规（PBKDF2 100k + AES-256-GCM 随机 salt/iv） |

---

## 一、桌面端（lib/desktop/）

### 集成核查（阶段6 改动验证，全部通过）

- 无残留：`previewStyle` / DesktopSplitEditor 的 `styleSheet` 传参 / `_sourceSyntaxCtrl` /
  `MarkdownSyntaxColors` / `BridgedSyntaxController` 全库零引用。
- `markdown_syntax_highlighter.dart` 因本轮改动孤儿化，已整文件删除（repo 有死代码清理先例）。
- Escape 链（shell_nav_ext.dart `_handleEscape`）覆盖画布模式 → workspace ✓；
  `WorkMode.source` 枚举值不动、UI 全部改名「写作画布」✓。
- ShellActionBus 47 个回调字段与 desktop_shell `_bus` 构造点一一对应，新增 `onSaveLocal` 已接线。
- 桌面壳 build 的 `Material(transparency)` 根修复未受影响（desktop_shell.dart:1703）。

### 存量问题（非本轮引入）

1. **编辑器保存队列是空转装饰** —— 高（误导性设计，见服务层 B-2）
   `EditorController` 的 enqueue/flush/onBeforeClose 从未入队，桌面关窗「强制落盘」实为 no-op，
   真实落盘靠 shell_autosave_ext 自动保存；自动保存失败仅 debugPrint 无用户感知
   （shell_autosave_ext.dart:71-73）。
2. **桌面「失败图片重试」UI 永不触发** —— 中
   `EditorController.setFailedImageBytes` 无任何调用方 → `_editor.failedImageBytes` 恒 null
   （shell_workbench_ui_ext 的重试按钮分支永假）。移动端写的是 `_RootShellState` 同名私有字段，
   双端状态双写漂移（main.dart:316-319 vs editor_controller.dart）。
3. 定时发布桌面有（shell_publish_ext.dart:837）、移动端活跃链路没有——反向功能缺口。中
4. 存量硬编码色值仍散布（如 focus 编辑区 `0xFF1F2937`、红绿灯 `0xFFFF5F57` 系列属合理保留），
   本轮新代码 hex 为零 ✓。

## 二、服务与核心层（lib/services/ lib/core/ lib/controllers/ lib/platform/）

### A. 架构铁律未生效 —— 高（需产品决策）

- `AppFileOperator`/`PlatformResolver` 抽象层全仓零业务调用，整个是死代码；
  `platform_resolver.dart:24-26` 把 iOS 也分给 AndroidFileOperator，iOS 实现（IosFileOperator）未接线。
  21 个 services、9 个 screens、4 个 core 文件直接 dart:io 操作文件。
  **建议：要么接线要么整体删除（连同 platform/ 死实现），消除文档与现实的鸿沟。**
- GitHubService 门面被绕过：site_management_screen.dart:360（UI 层直调 GitHub API）、
  site_health_monitor.dart:129-191（自建 HttpClient 实现 Git Data API 四连调用）；
  直接实例化 GitHubProvider 绕过门面的还有 rollback_manager / site_wizard_service /
  theme_store_service / editor_publish_ext 等 5 处 —— 中。

### B. 死代码（引用计数验证）

文件级（零 import）：`git_service.dart`（CLI 回退已由 github_service 内置）、
`local_asset_server.dart`、`p2p_incremental_sync.dart`、`p2p_mdns_service.dart`、
`taxonomy_cache_service.dart`、`template_service.dart`、`core/constant/app_constants.dart`、
`core/utils/path_util.dart`、`core/tool_format_adapter.dart` —— 中/低。

方法级重点：

- editor_controller.dart 保存队列（:311/:118/:320/:347）零入队恒空转 —— 高（见一-1）。
- editor_controller.dart:121-123 图片回调零接线 → 桌面重试 UI 失效 —— 中。
- document_controller.dart:129 `updateContentControllers` 零调用，且实现会 dispose
  可能仍挂接 Widget 的旧 controller —— 中。
- site_controller.dart:72-152、sync_controller.dart 大部分方法、ui_state_controller/
  frontmatter_controller 的 update* 系列零调用 —— 中/低。

### C. 健壮性

- storage_service.dart:206 Android `getFilesDir` 失败静默降级 systemTemp（数据可能写进
  重启即清的临时目录且无提示）—— 中~高。
- storage_service.dart:394-407 配置文件损坏仅 debugPrint 后返回空 Map（配置静默清零）—— 中。
- cms_draft_service.dart `_dbVersion=1` 有 onCreate 无 onUpgrade：未来加列会炸 CMS 草稿 —— 中。
- 正面：备份档有 version 前向拦截；`_write` 用 tmp+rename 原子写。

### D. 控制器

94 处 notifyListeners 全部无 dispose 防护。风险集中在异步回调晚于 dispose：

- sync_controller.dart:198-209 `Timer.periodic` 的 in-flight `_runAutoSync` 完成后 setStatus
  会在 dispose 后触发（最现实风险点）—— 中。
- ui_state_controller.dart:44-50 showToast 的 3 秒延迟回调 `hasListeners` 防护无效 —— 低概率中。
- shell_publish_ext.dart:347/:425/:1007 发布 await 后未查 mounted —— 低。
- 双轨通知无竞态；无连续回调内整壳 setState 违规（架构坑 #9 守住了）。

### E. TODO 清单

lib/ 仅 2 处：main.dart:387（全局静态注入临时方案）、examples/ 死文件内 7 处。FIXME/HACK 为零。

## 三、移动端（lib/main.dart lib/mixins/ lib/screens/ lib/widgets/）

### 双端能力差异（移动有 → 桌面无）

PNG 长图导出、系统分享文本/MD 文件、速记悬浮窗三入口、自动检查更新（main.dart:724-807，
桌面仅设置页手动检查 —— 中）、横竖屏保持、贴键盘 MD 工具条。
反向缺口：定时发布移动端缺位（在死文件 editor_screen.dart 里）—— 中。

### 渲染引擎现状（本轮后）

- 编辑预览双端统一 flutter_smooth_markdown（表格/公式/mermaid）✓。
- **阅读页掉队**：article_reader_screen.dart:69 仍用 flutter_markdown `Markdown(`，
  无 mermaid/KaTeX —— 中（建议切 MarkdownPreviewSmooth）。
- 壁纸范围：移动端铺满整页，桌面铺编辑画布/专注区（设计取舍）；字色亮度自适应双端逻辑已对齐。

### 死页面与死重 —— 高（合计可减包 ~4MB）

- `screens/editor_screen.dart`（1518 行旧版编辑器）+ `editor_screen.dart.bak`（79KB **被 git 跟踪**）。
- 零引用页面：log_panel_screen / mobile_diff_screen / mobile_snapshot_screen /
  skill_editor_screen（疑似功能断链：快照服务在初始化但无 UI 入口）。
- `widgets/markdown_preview_webview.dart` 零实例化 + `assets/preview/web/` 9 个文件约 4.1MB
  （mermaid.min.js 3.3MB）唯一加载方是该死组件——纯死重，直接撑大 APK。
- `widgets/editor_animations.dart` / `editor_menu_widgets.dart` / `focus_mode_overlay.dart`、
  `desktop/widgets/code_highlight.dart` 的 buildHighlightedBuilders（flutter_markdown 构建器，
  与新引擎不兼容）—— 零引用。

## 四、测试（test/）

| 文件 | 内容 | 状态 |
|---|---|---|
| preview_render_test.dart | 平滑预览 3 + 分屏预览 3 + 端到端 6 | 健康（本轮已适配新 API+补表格用例） |
| wysiwyg_poc_test.dart | super_editor 往返/表格/frontmatter | 健康（本轮+2 用例） |
| nav_custom_test.dart | 导航自定义序列化/过滤/指纹 | 健康 |
| widget_test.dart | 名不副实，实为 WritingStats 单测 | 低 |
| **test_batch_publish.dart** | 批量发布服务（Mock 注入齐全） | **命名不符 `*_test.dart` 约定，flutter test 静默跳过** |
| **test_localizations.dart** | l10n 5 用例 | **同上** |

**核心链路零测试（高）**：发布主链路 github_service upsertArticle/deleteArticle、
DraftEncryptionService、SyncService/CloudSyncService/P2PSyncService、
tool_executor + ai_session_manager + mcp_runtime、CMS 三适配器。
CI 不跑测试，以上无自动保障（高）。

## 五、CI 与发布（.github/workflows/build.yml tools/release.sh）

- 结构正确：analyze → 四端构建 → release（仅 tag v*）；产物命名与 release.json 四平台 URL 完全一致；
  pubspec 1.0.14+15 == release.json == main.dart == settings_screen.dart 硬编码串 ✓。
- **build.yml:41,46 `|| true`**：dart format 与 flutter analyze 永不失败，唯一能挂的检查是一个
  grep —— 高。
- **release job `continue-on-error: true`（:355）+ 缺产物仅 warning** —— 中。
- tools/release.sh:55,140 显式 `--version 1.2.0`（不带 +build）时 int() 崩溃；:190 写死
  `git push origin main` —— 中/低。
- Web 版 base-href 指 Pages 但无部署 job（自洽，无 release.json web 平台）—— 低。

## 六、修复优先级建议（供排期，本文档不含变更）

1. **高** CI 加 `flutter test` 步骤；`test_*.dart` → `*_test.dart` 改名；去掉 analyze/release 的
   `|| true` / `continue-on-error`。
2. **高** 保存链路收敛：接通或删除 EditorController 保存队列；自动保存失败加用户可见重试
   （与桌面 failedImageBytes 接线同一问题域）。
3. **高** 决策 AppFileOperator 层去留（接线或整体删除，含 iOS 死实现），同步修订架构文档措辞。
4. **中** 清死重：editor_screen.dart(+.bak)、markdown_preview_webview + assets/preview/web/
   （~4.1MB）、local_asset_server、git_service 等 9 个死文件、5 个死页面（快照/技能编辑先补入口再删）。
5. **中** GitHubService 门面纪律：site_health_monitor/site_management_screen 收敛回门面。
6. **中** 阅读页切 MarkdownPreviewSmooth；移动端补定时发布入口。
7. **中** cms_draft_service 预置 onUpgrade；SyncController/showToast 加 dispose 防护；
   storage_service 的 systemTemp 降级与配置损坏改为用户可见警告。
