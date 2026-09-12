# 修复6：editor_area.dart IndexedStack 误用

日期：2026-09-12
范围：`lib/desktop/widgets/editor_area.dart`

## 问题描述

内容区域用 `IndexedStack` 包裹所有标签页，但对每个非激活标签都返回
`SizedBox.shrink()`。IndexedStack 的价值是"全部挂载、按索引显示"（保活状态），
而该实现既付了 IndexedStack 的结构成本，又只挂载激活页——两者取其弊：
代码意图（多标签保活）与实际行为（仅激活页存在）相互矛盾，读者会误以为
标签页状态被保留。注释也说明了真实原因：多个标签共享同一
FocusNode/controller 会触发
"A FocusNode cannot be used in multiple widgets" 崩溃，因此**必须**只挂载激活页。

## 修复方案

- 移除 `IndexedStack` + `List.generate` 包装，改为 `_buildActiveContent()`
  直接渲染激活标签（`activeIndex` 越界仍 clamp 兜底，行为不变）。
- 原注释的解释迁移到新方法文档注释，说明"不做跨标签保活"的原因，消除误导。

## 验证

- `flutter analyze`：lib/ 0 error / 0 warning。
- `flutter test`：26/26 通过（含 DesktopSplitEditor 端到端标签页渲染用例）。
- 行为零变更：激活标签渲染路径与原来完全一致。
