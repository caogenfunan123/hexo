# Requirements Document

## Introduction

桌面端（Windows）编辑器复刻手机端「清爽写作范式」：默认进入极简写作模式，
主界面只保留「标题输入 + 正文编辑区」，大留白、无中框感；全部高级能力
（格式化工具栏、Front-matter、AI 工具、多文档标签、侧边栏）默认隐藏，
需要时通过右上角「更多」菜单、选区悬浮工具条或模式切换呼出。功能只隐藏、不删除。

## Glossary

- **极简写作模式**：改造现有 `WorkMode.focus` 后的默认写作界面，仅含极简标题栏、
  标题输入框、正文编辑区与背景层。
- **完整编辑模式**：现有 `WorkMode.workspace`（工作台），保留全部既有控件与能力。
- **更多菜单**：极简模式右上角「更多⋮」弹出的能力收纳菜单。
- **选区悬浮工具条**：用户在正文中选中文本时出现在选区附近的迷你格式条。
- **右侧元数据抽屉**：现有 `DesktopRightDrawer`，已绑定 tags/categories/cover 字段。

## Requirements

### Requirement 1: 极简写作模式界面

**User Story:** 作为桌面端用户，我想要打开文章时只看到标题和正文，
以便像手机端一样沉浸写作、不被工具栏和元数据干扰。

#### Acceptance Criteria

1. WHEN 用户打开新文章，系统 SHALL 默认进入极简写作模式，展示标题输入框与正文编辑区。
2. WHILE 用户处于极简写作模式，系统 SHALL 不渲染 FrontMatterCard、仓库选择器、
   博文/页面类型切换、格式化工具栏、Front-matter 面板、多标签页栏与底部状态条。
3. WHEN 用户处于极简写作模式，系统 SHALL 在背景层之上按「标题 → 正文」单一纵列
   排布内容，并保持较大的上下留白。
4. WHILE 用户处于极简写作模式，系统 SHALL 保持现有壁纸/纯色背景与字色自适应能力。

### Requirement 2: 极简标题栏

**User Story:** 作为桌面端用户，我想要极简模式顶栏只保留必要操作，以便视觉干净。

#### Acceptance Criteria

1. WHILE 用户处于极简写作模式，系统 SHALL 在标题栏左侧显示菜单按钮与项目名称。
2. WHILE 用户处于极简写作模式，系统 SHALL 在标题栏右侧提供保存、预览、更多三个操作按钮。
3. WHEN 用户点击标题栏保存按钮，系统 SHALL 保存当前文章。
4. WHEN 用户点击标题栏预览按钮，系统 SHALL 切换或打开预览视图。
5. WHEN 用户点击标题栏更多按钮，系统 SHALL 弹出更多菜单。

### Requirement 3: 更多菜单

**User Story:** 作为桌面端用户，我想要从极简模式呼出被隐藏的高级能力，以便不丢失功能。

#### Acceptance Criteria

1. WHEN 用户在更多菜单选择「元数据」，系统 SHALL 打开右侧抽屉展示标签/分类/封面/模板/类型/仓库字段。
2. WHEN 用户在更多菜单选择「格式化工具栏」，系统 SHALL 在编辑区展开完整工具栏。
3. WHEN 用户在更多菜单选择 AI 相关入口，系统 SHALL 打开对应 AI 对话/工作台界面。
4. WHEN 用户在更多菜单选择「切换到完整编辑模式」，系统 SHALL 切换到工作台模式并保留全部编辑上下文。

### Requirement 4: 选区悬浮工具条

**User Story:** 作为桌面端用户，我想要选中正文文本时在选区附近出现迷你格式条，
以便无需常驻工具栏即可格式化。

#### Acceptance Criteria

1. WHEN 用户在极简模式正文编辑区选中一段文本，系统 SHALL 在选区上方附近显示悬浮迷你工具条。
2. WHILE 悬浮工具条可见，系统 SHALL 提供粗体、斜体、链接、引用等核心格式操作。
3. WHEN 用户取消选区或点击工具条外部，系统 SHALL 隐藏悬浮工具条。

### Requirement 5: 侧边栏折叠

**User Story:** 作为桌面端用户，我想要侧边栏在极简模式下默认收起并可随时呼出，
以便获得全屏沉浸式写作空间。

#### Acceptance Criteria

1. WHEN 用户进入极简写作模式，系统 SHALL 自动收起左侧面板。
2. WHEN 用户点击极简标题栏菜单按钮，系统 SHALL 展开左侧面板。
3. WHEN 用户折叠/展开左侧面板，系统 SHALL 持久化该状态，重启后保持。

### Requirement 6: 模式切换与快捷键

**User Story:** 作为桌面端用户，我想要一键在极简与完整模式间切换，以便按需调整界面密度。

#### Acceptance Criteria

1. WHEN 用户按下 `Ctrl+Shift+E`，系统 SHALL 在极简写作模式与完整编辑模式之间切换。
2. WHEN 用户在极简模式按 `Escape`，系统 SHALL 返回完整编辑模式（保留现有 Escape 语义）。
3. WHEN 用户从极简模式切换到完整编辑模式，系统 SHALL 保留当前文章与未保存内容。
