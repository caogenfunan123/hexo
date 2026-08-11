# 巨型 State 类拆分方法（Extension + Part 方案）

> 本文档面向后续接手的 AI/开发者，说明本仓库如何把巨型 Flutter State 类按业务域拆分成多个文件，以及新增/修改代码时如何遵守这一模式。

## 一、背景与目标

本仓库的 `lib/main.dart` 中，核心状态类 `_RootShellState` 曾达到 **7425 行**（一个文件里包含发布、同步、设置弹窗、AI 对话、UI 构建、文本操作等所有功能），极难阅读与维护。现已通过 **Extension + Part 方案** 将其拆分为 10 个业务域文件，`main.dart` 缩减到约 1290 行（State 类本体 + 少量辅助 widget + 生命周期/会话/导航方法）。

拆分原则：**行为零变更**。每次抽取后必须 `dart analyze` 验证 0 error/warning，并用现有测试确认基线不变。

## 二、方案原理（为什么用 Extension + Part）

Dart 拆分类的几种方案对比：

| 方案 | 能否访问宿主私有成员 | 能否调用 `setState` | 结论 |
|---|---|---|---|
| `mixin on _RootShellState` | 否（报 `recursive_interface_inheritance`） | 否 | 不可用 |
| `mixin on State<...>` | 否（mixin 不知道宿主私有字段） | 是 | 不可用 |
| **`extension on _RootShellState` + `part of '../main.dart'`** | **是（同 library 天然可见私有成员）** | 否（`invalid_use_of_protected_member`） | **采用，需配合 `_applyState` 包装** |

核心机制：

1. `part of '../main.dart';` 声明 part 文件属于 main.dart 所在 library。Dart 的私有成员（`_` 前缀）在**同一 library 内全局可见**，所以 part 文件中的 extension 可以裸调用 `_doc`、`_editorRepo`、`_publish()` 等任何私有字段/方法，无需抽象声明。
2. `extension EditorXxxExt on _RootShellState { ... }` 把一组方法"挂"到宿主类上，调用方式与类内方法完全一致（`_publish()` 直接裸调用）。
3. `setState` 是 `State` 的 protected 成员，extension 不是 State 子类无法直接调用。解决：在宿主类 `_RootShellState` 内加一个包装方法：

```dart
/// 供 extension 内部调用的 setState 包装（避开 protected 限制）
void _applyState(VoidCallback fn) => setState(fn);
```

part 文件里的所有 `setState(...)` 一律替换为 `_applyState(...)`。

## 三、如何识别"需要拆分"的时机

当你在 `lib/main.dart` 的 `_RootShellState`（或任何 State 类）中发现以下信号时，应启动本方案：

1. **文件行数过多**：单文件超过 1000~1500 行，且主体是同一个 State 类。
2. **职责混杂**：同一个类里既有发布、又有同步、又有 UI 构建、又有设置弹窗，方法之间缺乏内聚。
3. **新功能无处安放**：新增一个功能时要翻半天才能找到"该放哪"，或被迫在已很大的类里继续堆。
4. **CI/analyze 定位困难**：error/warning 定位时整个文件无法快速定位到具体方法。

## 四、拆分执行步骤（操作手册）

### Step 1：按业务域规划分组

把 `_RootShellState` 的方法按业务域分组。参考本仓库已有分组（见第六节），常见分组：

- 发布/上传/保存
- 同步/云端
- 设置/管理弹窗
- 编辑页 UI 构建
- 文本操作/自动保存
- AI 功能/对话
- 仓库/Token 管理
- 远程内容/分享
- 杂项工具
- 抽屉组件

**必须留在宿主 State 的方法**：`build()`、`initState()`、`dispose()`、`didChangeAppLifecycleState()` 等 `@override` 生命周期方法，以及被它们直接调用的初始化/导航/会话方法（可留可抽，视内聚度）。

### Step 2：精确提取方法区间

用脚本（字符串/注释屏蔽 + 花括号配对）定位每个方法的精确行范围，避免误删。脚本逻辑要点：

- `strip_line()`：逐字符屏蔽字符串字面量、`//` 行注释、`///` 文档注释，避免注释里的 `{}` 干扰配对。
- 方法声明匹配：行首恰好 2 空格缩进 + 返回类型关键字（`Future<...>`/`void`/`Widget`/`bool` 等）+ 方法名 + `(`；排除调用行（以 `;` 结尾、或以 `await `、`this.`、`if `、`return `、`final `、`var ` 开头）。
- **支持多行参数声明**（如 `_upsertGithubToken(\n  GithubTokenProfile profile, {\n  bool makeActive = false,\n})`）：匹配声明时只要行首是返回类型关键字即可，不需要方法名在本行。
- 计算方法体：从声明行起做花括号深度配对，深度归零的那个 `}` 是方法结束。
- 向上收集紧邻的连续 `//`/`///` 注释（**不跨空行**，防止把上一方法的注释/结尾吞进来）。
- **删除前先打印全部区间并检查两两不重叠**。

### Step 3：生成 part 文件

每个业务域生成一个文件，模板：

```dart
// 编辑器 <业务域> 扩展（由 main.dart part 引入，与原类同 library，可访问私有成员）
part of '../main.dart';

extension EditorXxxExt on _RootShellState {
  // <方法1> ...
  // <方法2> ...
}
```

**必须做的替换**：把抽取块中的 `setState(` 全部替换为 `_applyState(`（注意不要误伤 `StatefulBuilder` 的 `setModal`、`setState` 参数变量名等非宿主调用）。

### Step 4：从 main.dart 删除原方法

按提取出的区间从大到小删除（避免行号偏移）。删除前再次确认区间无重叠、无越界。

### Step 5：注册 part 声明

在 `lib/main.dart` 的 import 区之后、任何类之前添加：

```dart
part 'mixins/editor_publish_ext.dart';
part 'mixins/editor_sync_ext.dart';
part 'mixins/settings_dialogs_ext.dart';
// ...（每个 part 一行）
```

注意：`part` 声明必须位于所有 `import` 之后（`import_directive_after_part_directive`）。

### Step 6：验证（每步必须）

```bash
export PATH=/tmp/opencode/flutter/bin:$PATH
dart analyze lib/main.dart              # 必须 0 error/warning
flutter analyze                         # 全局 0 error/warning（允许历史 deprecated info）
flutter test test/test_batch_publish.dart  # 基线应为 +2 -1（-1 是历史 frontmatter 引号问题）
```

**每拆一个域就验证一次**，不要攒到全部拆完再验证。出错时用 `git checkout HEAD -- lib/main.dart` 回滚单个文件，再重新提取。

## 五、新增代码时的行为准则

当你要在 `_RootShellState` 中添加新方法时，遵守以下规则：

1. **先判断归属**：新方法属于哪个业务域，就写进哪个 `lib/mixins/editor_xxx_ext.dart` 的对应 extension 里，**不要**直接堆进 `lib/main.dart` 的类体。
2. **新业务域**：如果没有匹配的现有 extension，按第四节流程新建一个 `editor_yyy_ext.dart` 并在 main.dart 注册 `part`。
3. **setState 一律用 `_applyState`**：写在 part 文件里的方法，凡是原来会写 `setState(...)` 的地方统一写 `_applyState(...)`。
4. **禁止新建巨型单文件**：新增逻辑如果会让某个文件再次膨胀到 1000+ 行，应继续拆分子域。
5. **纯展示组件**：与 State 无关、只依赖传入参数的无状态 widget，抽取到 `lib/widgets/`（公开类，如 `WordCountBadge`、`EditorMenuGroupTitle`）。
6. **纯逻辑/常量**：与 State 无关的纯函数/常量，放到 `lib/core/`、`lib/utils/` 等公开模块。

## 六、已完成拆分清单（2026-08-11）

`lib/main.dart` 现有 10 个 part 声明（98-107 行），对应文件与内容：

| part 文件 | 业务域 | 方法 | 行数 |
|---|---|---|---|
| `mixins/editor_publish_ext.dart` | 发布/上传/保存 | `_collect`, `_saveLocal`, `_publish`, `_publishToCms`, `_publishToAllCmsSites`, `_generateSlug`, `_publishToAllStaticSites`, `_showStaticPublishPreviewDialog`, `_showStaticPublishResult`, `_insertImage`, `_batchInsertImages`, `_retryUploadImage`, `_saveDraft`, `_deleteDraft`, `_saveMdBackup` | 904 |
| `mixins/editor_sync_ext.dart` | 同步/云端 | `_initCloudSync`, `_startAutoSync`, `_stopAutoSync`, `_openP2PSync`, `_autoSyncToCloud`, `_autoPullFromCloud`, `_flushAllPendingSaves`, `_syncWebDavToLocal`, `_syncDraftsToWebDav`, `_pushAllToCloud`, `_pullAllFromCloud` | 385 |
| `mixins/settings_dialogs_ext.dart` | 设置/管理弹窗 | `_showExitDialog`, `_updateSettings`, `_showWebDavDialog`, `_showSiteEditor`, `_showBlogSiteManager`, `_showAiManager`, `_showGithubTokenManager`, `_showRepoManager`, `_showTemplateManager`, `_showSnippetManager`, `_showSnippetDialog`, `_showConfigEditor`, `_showAiModelManager`, `_showSiteConfigEditor` | 1052 |
| `mixins/editor_ui_ext.dart` | 编辑页 UI 构建 | `_buildFocusMode`, `_appBarAction`, `_buildEditorAppBarTitle`, `_showEditorToolbox`, `_toolboxSectionTitle`, `_toolboxSectionBody`, `_toolboxTypeChip`, `_showEditorMoreMenu`, `_menuGroupTitle`, `_menuRow`, `_showAiFullMenu`, `_aiMenuChip`, `_buildDrawer`, `_buildPage`, `_setEditorTheme`, `_buildEditorPage`, `_buildMdToolbar` | 1712 |
| `mixins/editor_text_ext.dart` | 文本操作/自动保存 | `_newBlankArticle`, `_autoSelectTemplate`, `_startAutoSave`, `_stopAutoSave`, `_onContentChanged`, `_autoSaveSnapshot`, `_openReader`, `_enterEditorFromReader`, `_insertText`, `_wrap`, `_insertHeading`, `_insertList`, `_insertCodeBlock` | 224 |
| `mixins/editor_ai_ext.dart` | AI 功能/对话 | `_aiAction`, `_showAiSelectionEdit`, `_editAiProfile`, `_showAgentWorkbench`, `_showAiArticleChat`, `_showAiPageChat`, `_showAiThemeChat`, `_showAiAudit`, `_showAiTemplateChat` | 531 |
| `mixins/editor_repo_ext.dart` | 仓库/Token 管理 | `_handleBlogSiteSaved`, `_activateGithubToken`, `_upsertGithubToken`, `_editGithubToken`, `_editRepo`, `_showCommitActions`, `_rollbackFile`, `_doRollback`, `_openRemotePostInEditor`, `_deleteRemoteCmsPost`, `_deleteRemotePost`, `_batchDeleteRemote` | 799 |
| `mixins/editor_remote_ext.dart` | 远程内容/分享 | `_openArticlePreview`, `_shareArticle`, `_shareMdFile`, `_openStorageFolder`, `_exportPngLongImage`, `_showStaticBlogPosts`, `_showAllStaticBlogs`, `_findStaticFileItem`, `_openStaticBlogPostInEditor`, `_openStaticBlogPostAsync`, `_deleteStaticBlogPost` | 306 |
| `mixins/editor_misc_ext.dart` | 杂项工具 | `_showThemeColorPicker`, `_showPwaGuide`, `_showMigrationTool`, `_showToolLibrary` | 126 |
| `mixins/editor_drawer_ext.dart` | 抽屉组件 | `_drawerSection`, `_drawerItem`, `_drawerAction`, `_toolChip` | 151 |

**保留在 `lib/main.dart` 的 `_RootShellState`（约 1290 行）**：
- 字段定义与 getter（`storage`, `github`, `aiService`, `settings` 等）
- 生命周期：`initState`, `didChangeAppLifecycleState`, `build`
- 初始化/会话/导航：`_bootstrap`, `_initNewServices`, `_ensureGithubTokensFromLegacy`, `_navigateTo`, `_openDrawer`, `_restoreSession`, `_saveSession`, `_clearSession`, `_onCloseEditor`, `_onCloseReader`, `_resetEditor`, `_updateSiteManager`
- 刷新/工具：`_refreshRemote`, `_refreshRss`, `_refreshCommits`, `_updateRepos`, `_persistSettings`, `_persistRepos`, `_showToast`, `_confirm`, `_fmt`, `_openExistingArticle`, `_updateSystemBarStyle`, `_onSiteChanged`, `_openSiteManagement`, `_setAsRepoDefault`
- 辅助方法：`_applyState`（setState 包装，**不可删除**）

**此前已完成的第一阶段抽取**（独立公开文件，非 part）：
- `lib/widgets/word_count_badge.dart`：`WordCountBadge`（公开 widget，从 main.dart 私有 `_WordCountBadge` 迁移并统一引用）
- `lib/theme/editor_theme_controller.dart`：`EditorThemeController`（静态类，封装 `editorBgColor`/`globalTextColor`/`wallpaperTextColor`/`useDarkSystemIcons`/`systemBarStyle`）
- `lib/widgets/editor_menu_widgets.dart`：`EditorMenuGroupTitle`/`EditorMenuRow`/`EditorDrawerSection`/`EditorDrawerItem`/`EditorDrawerAction`/`EditorToolChip`

## 七、常见坑与规避

| 坑 | 规避方法 |
|---|---|
| 注释收集越界（把上一方法结尾 `}` 收进提取块） | 向上收集注释**不跨空行**；提取后先看块首行确认 |
| 误匹配调用处（`_publish()` 出现在 `case 'publish': await _publish();`） | 匹配声明时要求行首缩进恰好 2 空格 + 返回类型关键字 + 非 `await/if/return` 开头 |
| 方法误删导致 `non_abstract_class_inherits_abstract_member`（build 没了） | 删除前打印区间核对；出错用 `git checkout HEAD -- lib/main.dart` 回滚 |
| `setState` 被误替换成 `_applyState` 破坏非宿主调用 | 替换时只针对宿主 `setState(`；用 grep 复查残留 `setState(` 是否为合法场景 |
| 私有 `_WordCountBadge` 与公开 `WordCountBadge` 重复 | 删除私有类、统一引用公开类；出现 `undefined_method WordCountBadge` 时检查 import |
| `unused_import`（方法抽走后原 import 没用） | 抽取后跑 analyze，按提示清理 import |
| 忘记注册 `part 'mixins/xxx.dart'` | 新 part 文件必须加到 main.dart 98 行区域，否则方法全部 `undefined` |
| `import_directive_after_part_directive` | `part` 声明必须放在所有 `import` 之后 |

## 八、验证命令速查

```bash
export PATH=/tmp/opencode/flutter/bin:$PATH
dart analyze lib/main.dart            # 0 error/warning
flutter analyze                       # 0 error/warning（info 为历史 deprecated，允许）
flutter test test/test_batch_publish.dart   # 基线 +2 -1
git -c credential.helper= -c credential.helper="store --file=/root/.netrc" push origin main
export GH_TOKEN="$(awk '/machine github.com/{print $6}' /root/.netrc)" && gh run list
```

本环境无 JDK/Android SDK，Android 构建验证依赖 GitHub Actions CI。
