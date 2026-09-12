# 修复4：统一两份大纲解析（代码围栏行为不一致）

日期：2026-09-12
范围：删除 `lib/desktop/widgets/outline_panel.dart`（151 行，整文件死代码）

## 问题描述

仓库中存在两份 Markdown 大纲（标题）解析实现，行为不一致：

| 实现 | 位置 | 代码围栏处理 |
|---|---|---|
| `parseOutline` | right_drawer.dart（活跃，被 `_buildRightDrawer` 使用） | ✅ 正确跳过 ``` / ~~~ 围栏内的 `#` |
| `OutlinePanel.parse` | outline_panel.dart | ❌ 不过滤围栏，代码块里的 `# 注释` 会被误判为标题 |

复盘中将其列为"行为不一致"问题，但深入核查发现 `OutlinePanel` 组件与
`OutlineEntry` 类**在全库（lib/ + test/）中零引用**——该文件与修复3 的
frontmatter_card.dart 一样是遗留死代码，实际大纲功能只有
right_drawer.dart 的 `parseOutline` 一条链路在跑。

## 修复方案

- 确认零引用后删除 `outline_panel.dart` 整文件。
- 围栏行为不一致随第二份实现一起消失：现存唯一解析器 `parseOutline`
  即为围栏感知的正确实现，无需改动任何活跃代码。

## 验证

- `flutter analyze`：lib/ 0 error / 0 warning。
- `flutter test`：26/26 通过。
- 备份留存：`hexo-backups/outline_panel.dart.fix4.bak`。
