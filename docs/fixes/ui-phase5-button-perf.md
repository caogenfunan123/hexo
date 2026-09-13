# 界面改版·阶段5：按钮卡顿优化（第一轮）

日期：2026-09-12
范围：`lib/desktop/shell_parts/shell_workbench_ui_ext.dart`、`lib/desktop/shell_parts/shell_mode_ui_ext.dart`

## 问题

用户反馈「所有按钮都感觉卡卡的」。排查结论：键盘输入路径此前已优化
（_trackStats/_onContentChanged 均为局部通知，不整壳 setState），卡顿来自
**鼠标高频交互路径的整壳重建**与**重绘串扰**。

## 修复

### 1. 分栏拖拽整壳重建（最重根因，已修）

`DesktopSplitEditor.onSplitRatioChanged` 原实现 `_applyState(() => _splitEditorRatio = r)`
——拖拽分隔线是**连续回调**，每移动一像素触发一次 DesktopShellState 整壳重建
（标题栏 + 左栏 1021 行构建 + 编辑器 + 抽屉 + 状态栏全部重跑）。

修复：改为纯字段赋值 `_splitEditorRatio = r`（分栏编辑器自己持有本地状态并
自行刷新渲染，壳字段仅用于下次打开恢复）。拖拽期间整壳重建归零。

### 2. 重绘串扰隔离（RepaintBoundary）

工作台三区域（左栏 / 编辑区 / 右抽屉）各包一层 RepaintBoundary：
按钮水波纹、悬停效果的重绘不再扩散到相邻面板。

### 3. 保持不动的（有意决策）

- 模式切换（所见即所得/源码/分栏/预览）仍整壳刷新一次：工具栏显隐依赖壳状态，
  且单击一次可接受；
- 列表增删改（草稿重命名/删除）整壳刷新：低频操作；
- 按钮 150ms 按压动画：视觉反馈设计，非卡顿。

## 复盘与验证

- `flutter analyze` 0 error / 0 warning；`flutter test` 29/29。
- 本轮为结构性第一轮：高频路径（拖拽）重建归零 + 重绘隔离。若真机仍有
  局部卡顿，下一步用 DevTools timeline 定位具体帧（候选：左栏文章列表排序、
  WYSIWYG 大文档序列化），避免无 prof 盲改。

## 经验沉淀（已写入架构文档改码守则）

**连续回调（拖拽/滚动/动画进度）内严禁 `_applyState`/整壳 setState**；
需要跨组件可见的连续值，写字段 + 让展示方自持 Listenable 局部刷新。
