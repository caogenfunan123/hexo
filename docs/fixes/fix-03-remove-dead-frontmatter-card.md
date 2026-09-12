# 修复3：删除 frontmatter_card.dart 死代码

日期：2026-09-12
范围：删除 `lib/desktop/widgets/frontmatter_card.dart`（561 行，整文件死代码）

## 问题描述

该文件头自注（原文）：

> TODO(待清理): 自 P2 起属性编辑已统一走工作区 B 面板
> （desktop_shell.dart 的 `_buildFrontMatterPanel`），本组件已无引用。
> 本轮迭代保留不删，待 MarkText 改造全部验证通过后再移除。

即 FrontMatter 结构化编辑已由工作区面板（现位于
`lib/desktop/shell_parts/shell_workbench_ui_ext.dart` 的 `_buildFrontMatterPanel`）
与 `lib/controllers/frontmatter_controller.dart`（含独立 `FrontMatterData`、
`fromYaml`/`parseMarkdown`）全面接管，旧卡片组件成为死代码，且与
`frontmatter_controller.dart` 存在同名类 `FrontMatterData`（两套定义），易造成误导。

## 修复方案

- 全库检索确认零引用（lib/ 与 test/ 均无 import，无 `FrontMatterCard` 使用）。
- 删除整文件；活跃实现的 YAML 解析/回写能力不受影响。
- 同名类混淆随之消除。

## 验证

- `flutter analyze`：lib/ 0 error / 0 warning。
- `flutter test`：26/26 通过。
- 备份留存：`hexo-backups/frontmatter_card.dart.fix3.bak`（如需找回其中的
  `_rewriteYamlBlock` 原位改写思路可参考，但活跃实现未使用该逻辑）。
