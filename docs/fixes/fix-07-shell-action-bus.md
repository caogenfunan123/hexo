# 修复7：ShellActionBus 膨胀治理 + 导航接线断层修复

日期：2026-09-12
范围：`lib/desktop/shell_action_bus.dart`、`lib/desktop/nav_entries_meta.dart`、`lib/desktop/desktop_shell.dart`

## 问题描述

`ShellActionBus` 以 45 个 `required` 回调字段承载桌面端全部动作，配合
`navEntryAction(id)` 字符串映射构成"四处同步"架构：
入口注册（feature_entries）→ 展示定义（kNavEntries）→ id 映射（navEntryAction）
→ 处理器接线（shell 的 `_bus` 构造）。任何一处漏改即产生**静默失效**——
复查证实这一失效模式已经真实发生了 3 次：

| 入口 id | 断层位置 | 用户可见症状 |
|---|---|---|
| `tool_library` | navEntryAction 缺 case | 全部功能 Hub 中"工具库"卡片灰色不可点（字段与处理器都在，仅映射缺失） |
| `help` | navEntryAction 缺 case | Hub 中"帮助"卡片灰色不可点 |
| `ai_template_chat` | 连 bus 字段都没有 | 该入口为 `optIn`（用户可在自定义侧边栏手动加回），加回后是死卡片 |

## 修复方案

### 功能失效修复（三处接线补齐）

1. `navEntryAction` 补 `'tool_library' => bus.onShowToolLibrary`、
   `'help' => bus.onShowHelp` 两条映射；
2. `ShellActionBus` 补 `onShowAiTemplateChat` 字段（AI 组），`desktop_shell.dart`
   的 `_bus` 构造接上已有的 `_showAiTemplateChat` 处理器，navEntryAction 补映射。

修复后效果：全部功能 Hub 中上述三张卡片从"灰色死卡"变为可正常打开对应功能；
自定义侧边栏里用户手动加回 `ai_template_chat`（optIn）后可正常使用。

### 防再发（协议文档化）

- `ShellActionBus` 类文档新增"新增功能入口的固定清单（四处必须同步，缺一即功能失效）"，
  明确四处改动点与漏改的典型症状（Hub 卡片灰显）。
- 建立机器可校验的完整性检查（kNavEntries id ↔ navEntryAction case 差集），
  本次已将 39 个入口 id 全部对齐，差集清零。

### 不做什么（明确记录决策）

- **不**把 45 个字段拆成域子对象（bus.nav.xxx / bus.article.xxx）：
  会强制改动 left_panel/title_bar 等全部消费方，纯结构翻新换不来行为收益；
  且紧随其后的界面改版将重新设计导航，届时再随设计一并重构才是正确时机。
- **不**给回调加 no-op 默认值、去掉 `required`：编译期"必须接线"是防止
  静默失效的现行保障（本次三个断层正是"缺了没有编译错误"导致漏接），
  弱化它会放大同类问题。

## 验证

- `flutter analyze`：lib/ 0 error / 0 warning。
- `flutter test`：26/26 通过。
- 映射完整性脚本复查：39 个入口 id ↔ navEntryAction 差集为空。
