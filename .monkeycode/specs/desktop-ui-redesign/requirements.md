# Requirements Document — 桌面端界面收敛与视觉对齐

## Introduction

用户反馈桌面端「功能太乱、界面难看、与手机版不像同一个软件」。本规格定义桌面端
信息架构收敛与视觉统一的需求。范围仅限桌面（Windows/Linux）；移动端行为保持不变。

## Glossary

- **侧边栏**: 桌面主窗口左侧导航面板（left_panel.dart）。
- **Hub**: 「全部功能」页（AllFeaturesScreen，双端共用），承载全部功能入口。
- **简易模式 / 标准模式**: AppMode（ui_settings.dart:10），simple 默认。
- **入口注册表**: feature_entries.dart NavEntries.registry，双端共用的入口可见性定义。
- **高频入口**: 首页、新建文章、草稿、同步中心、站点管理、AI 工作台、图床、设置、全部功能。

## Requirements

### R1 侧边栏收敛（简易模式）

**User Story:** 作为普通写作用户，我希望侧边栏只出现高频功能，以便主界面整洁、上手快。

#### Acceptance Criteria

1. WHEN 简易模式下打开桌面主界面，THE 侧边栏 SHALL 仅显示高频入口（至多 9 个）。
2. WHEN 用户需要在简易模式下使用专业功能，THE 用户 SHALL 能通过「全部功能」Hub
   或「自定义侧边栏」访问全部入口。
3. WHEN 简易模式下侧边栏展示入口集合，THE 入口集合 SHALL 与手机端自定义侧边栏
   的默认集合语义一致（共用入口注册表）。

### R2 编辑器工具栏对齐手机

**User Story:** 作为写作用户，我希望编辑器顶部只出现常用格式化按钮，以便写作时聚焦内容。

#### Acceptance Criteria

1. WHEN 打开桌面编辑器，THE 工具栏 SHALL 显示与手机端一致的常用格式化按钮集合
   （加粗/斜体/标题/列表/引用/代码/表格/链接/图片）。
2. WHEN 用户点击工具栏「更多」，THE 系统 SHALL 显示菜单收录导出/导入/批量/修复
   等专业工具。
3. WHEN 用户使用命令面板（Ctrl+K），THE 命令面板 SHALL 仍能检索到全部专业工具动作。

### R3 视觉语言统一

**User Story:** 作为双端用户，我希望桌面与手机呈现一致的设计语言，以便两者像同一个软件。

#### Acceptance Criteria

1. THE 桌面 UI SHALL 复用与移动端一致的设计令牌（主色、圆角、间距、字号阶梯）。
2. THE 桌面侧边栏、编辑器工具栏、对话框、设置页 SHALL 采用卡片化容器样式（圆角、
   描边、留白与移动端一致）。
3. WHEN 用户切换深色/浅色主题，THE 桌面与移动端的对应主题 SHALL 呈现一致的色彩映射。

### R4 功能零丢失（回归约束）

#### Acceptance Criteria

1. THE 重构 SHALL 保证现有全部功能入口仍可从「Hub、命令面板、更多菜单」三者之一到达。
2. WHEN 运行既有测试 nav_custom_test（双端一致入口集合），THE 测试 SHALL 保持通过。
