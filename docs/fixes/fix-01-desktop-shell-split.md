# 修复1：desktop_shell.dart 巨型 State 类拆分

日期：2026-09-12
范围：`lib/desktop/desktop_shell.dart`（12,272 行 → 2,424 行）+ 新增 `lib/desktop/shell_parts/`（16 个 part 文件，10,034 行）

## 问题描述

`DesktopShellState` 是 12,272 行的上帝对象：服务单例、全部业务状态、约 236 个业务方法
（发布/同步/导出/AI/弹窗/文本操作/模式 UI……）全部堆在一个类里，定位困难、改动牵一发动全身。
拆分方法论遵循 `.monkeycode/docs/code-splitting-guide.md`（Extension + Part 方案，移动端
main.dart 已用同一方案拆过）。

## 修复方案

采用 **extension + part** 拆分（与 main.dart 拆分方案一致）：

- `DesktopShellState` 保留：字段/getter、生命周期（initState/dispose/build/didChange*）、
  引导流程（_bootstrap 系列）、动作分发器 `handleGlobalAction`、公开 API
  （flushAllPendingSaves/openExternalFile）、`_applyState` setState 包装。
- 9,724 行方法体按业务域移入 16 个 part 文件，扩展与主类同 library，私有成员直接可见，**行为零变更**。
- part 文件内 `setState(` 全部替换为 `_applyState(`（StatefulBuilder 的
  setDialogState/setDlgState 参数名不受影响，已逐处核实）。
- extension 内访问宿主静态成员的 4 处引用加了 `DesktopShellState.` 前缀（Dart 规则要求）：
  `_focusHeaderOffset`、`_maxRecentFiles`×2、`_defaultShortcuts`、`_actionLabels`。

### part 文件清单

| 文件 | 业务域 | 行数 |
|---|---|---|
| shell_publish_ext.dart | 发布/保存/定时发布 | 1058 |
| shell_sync_ext.dart | 云同步/WebDAV/冲突解决 | 499 |
| shell_autosave_ext.dart | 自动保存/内容变更跟踪 | 240 |
| shell_drafts_ext.dart | 文章/草稿/标签页/会话 | 473 |
| shell_remote_ext.dart | 远程内容/回滚 | 259 |
| shell_ai_ext.dart | AI 功能 | 800 |
| shell_import_export_ext.dart | 导入/导出 | 567 |
| shell_dialogs_ext.dart | 设置/站点/管理弹窗 | 639 |
| shell_style_ext.dart | 外观定制/帮助 | 978 |
| shell_search_ext.dart | 查找替换/全局搜索 | 514 |
| shell_tools_ext.dart | 运维工具/批量操作 | 791 |
| shell_text_ext.dart | 文本编辑/插入 | 620 |
| shell_nav_ext.dart | 导航/文件打开/布局开关 | 397 |
| shell_workbench_ui_ext.dart | 工作台编辑区 UI | 929 |
| shell_mode_ui_ext.dart | 三种工作模式布局 UI | 1002 |
| shell_misc_ext.dart | 杂项/命令面板 | 268 |

## 工具化

提取/校验脚本化并入库，可重复执行（幂等）：

- `tools/split_helper.py` — 方法边界提取：文档级字符串/注释屏蔽（支持三引号模板）、
  圆括号感知的花括号配对（避免 `{bool x = true}` 参数、`() {}` tearoff 干扰）。
- `tools/split_execute.py` — 执行拆分：业务域映射、区间无重叠校验、逐块花括号配平断言、
  生成 part 文件、主文件删区+注册 part+插入 `_applyState`、静态成员限定名后处理。

开发过程中抓出并修复的脚本级 bug（对后续复用有参考价值）：
1. 参数默认值中的 `{}` 被当成方法体花括号 → 引入括号深度跟踪；
2. 行级字符串屏蔽无法处理 `'''...'''` 多行模板（内含大量 CSS `{}`）→ 重写为文档级屏蔽器；
3. 0 基/1 基行号混用导致每个提取块多吞上一行（`_focusHeaderOffset` 的值行被挪走，
   主文件留下悬空 `=` 引发连锁解析错误）→ 统一 0 基闭区间切片。

## 顺手修复的存量错误（与拆分无关，验证时发现）

1. `lib/platform/android/file_operator_android.dart`：调用了 path_provider 2.x 已移除的
   `getExternalStoragePublicDirectory`/`ExternalStorageDirectoryType` API（lock 已固定
   path_provider_android 2.3.1），会导致 Android 构建失败。改为直接使用公共下载目录
   `/storage/emulated/0/Download`（即原代码失败回退的同一路径），行为等价。
2. `lib/platform/desktop/file_operator_desktop.dart:105`：`getDownloadsDirectory()` 可空
   返回值被无条件访问 `.path` → 加空值守卫（原来会抛异常进 catch 返回 null，行为等价）。

## 验证

- `flutter analyze`：lib/ 0 error / 0 warning（`_archive/` 存量错误为历史归档死文件，另行处理）。
- `flutter test`：26/26 通过（基线不变）。
- 方法完整性：原 244 个方法声明全部保留，仅新增 `_applyState`；无方法丢失/重复。
- setState 替换安全：part 文件内无残留宿主 `setState(` 调用；StatefulBuilder 局部
  `setDialogState`/`setDlgState`（44 处）未被误替换。
- 文本级等价复核：214 个迁移方法与原文件逐一比对，211 个逐字符一致（空白归一后）；
  其余 3 个（_centerCursorInFocusMode/_showShortcutEditor/_addRecentFile）差异仅为
  必需的静态成员限定名前缀，还原前缀后完全一致。
