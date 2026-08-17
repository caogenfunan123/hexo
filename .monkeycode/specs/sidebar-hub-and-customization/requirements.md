# Requirements Document

## Introduction

当前桌面端侧边栏有 7 个分组、约 40 个导航入口平铺，存在入口重复（站点/同步语义重叠、dashboard 残留）、低频运维工具占用导航空间的问题。本功能通过三个层次解决：

1. **去重瘦身**：合并语义重复的入口，清除自相矛盾的残留入口。
2. **全部功能 Hub 页**：侧边栏收敛为高频导航 + 一个"全部功能"入口，低频/专业功能统一收纳进仪表盘式网格页。
3. **可视化自定义**：将现有 `optIn` 隐藏机制升级为可视化开关，任何模式下用户都能自行决定侧边栏显示哪些入口，并支持"固定到顶部"。

本功能只涉及 UI 导航层，不改变任何功能实现、数据模型与既有服务。

## Glossary

- **拓墨 / 系统**：本产品，AI Markdown 写作与静态博客发布工具。
- **侧边栏**：桌面端左侧导航面板（`DesktopLeftPanel`）。
- **入口（Entry）**：侧边栏中的一个可导航项，由稳定 `id` 标识。
- **枢纽页（Hub）**：收纳低频/专业入口的网格化功能页，即"全部功能"页。
- **固定项（Pinned）**：用户主动置顶到侧边栏顶部的常用入口。
- **可见性档位（Visibility）**：`shown`（默认可见）/ `optIn`（默认隐藏可加回）/ `hidden`（专业隐藏）。

## Requirements

### Requirement 1: 入口去重与语义合并

**User Story:** AS 用户, I want 侧边栏消除重复入口, so that 导航清晰不困惑。

#### Acceptance Criteria

1. WHEN 用户打开侧边栏"站点"分组，THEN 系统 SHALL 只展示单一的"站点管理"入口替代原"添加站点"/"站点管理"/"动态博客登录"三个重复入口。
2. WHEN 用户打开侧边栏，THEN 系统 SHALL 将"远程文章""同步状态""提交历史""云同步"合并为单入口"同步中心"，原功能 SHALL 可通过同步中心页内分页访问。
3. WHEN 用户打开侧边栏"管理"分组，THEN 系统 SHALL 移除仪表盘残留入口（`dashboard`），依据注册表 `hidden` 定义与"首页替代仪表盘"既有设计。
4. WHEN 系统合并入口，THEN 隐藏的入口对应功能 SHALL 仍然可访问（进入合并后的页面内），不得删除任何功能。

### Requirement 2: 侧边栏收敛为高频导航 + 全部功能 Hub

**User Story:** AS 用户, I want 侧边栏只保留常用功能, 低频工具收进统一页, so that 面板不再拥挤。

#### Acceptance Criteria

1. WHEN 侧边栏渲染，THEN 系统 SHALL 在顶部固定展示高频导航：首页、新建文章、草稿箱、站点列表，不参与分组折叠。
2. WHEN 用户浏览分组，THEN 系统 SHALL 保留现有分组折叠机制，但"工具""系统"等低频分组默认折叠，折叠状态持久化。
3. WHEN 用户在侧边栏底部点击"全部功能"入口，THEN 系统 SHALL 打开枢纽页，以网格卡片展示所有入口（含 `optIn` 项与 `hidden` 专业项）。
4. WHEN 枢纽页渲染，THEN 系统 SHALL 按分组分区展示入口网格，每格显示图标、名称，点击即导航或打开对应面板。
5. WHEN 枢纽页存在入口，THEN 系统 SHALL 在每格提供"显示/隐藏于侧边栏"开关，全部入口（含 `shown` 高频项）均可切换。
6. WHEN 侧边栏处于简易模式，THEN 系统 SHALL 在枢纽页同样过滤 `hidden` 专业项，除非用户明确在设置中启用专业项。

### Requirement 3: 可视化自定义侧边栏

**User Story:** AS 用户, I want 直接决定侧边栏显示哪些入口, so that 面板完全符合个人习惯。

#### Acceptance Criteria

1. WHEN 用户在侧边栏或枢纽页触发"自定义侧边栏"，THEN 系统 SHALL 打开对话框，列出全部入口并按分组分区，每个入口带开关。
2. WHEN 用户切换某入口开关，THEN 系统 SHALL 保存该入口的显隐偏好到持久化配置，并在侧边栏实时生效。
3. WHEN 用户设置某入口为显示，THEN 系统 SHALL 在侧边栏对应分组中渲染该入口（不受 `optIn` 默认隐藏影响）。
4. WHEN 用户设置某入口为隐藏，THEN 系统 SHALL 从侧边栏移除该渲染项，但保留该入口在枢纽页中可访问。
5. WHEN 用户点击入口"固定到顶部"，THEN 系统 SHALL 将该入口加入"固定项"区域（位于高频导航下），并持久化其顺序。
6. WHEN 系统加载不存在的入口 id（配置损坏或版本回退），THEN 系统 SHALL 忽略该项且不报错。
7. WHEN 用户自定义配置存在，THEN 系统 SHALL 以该配置为准渲染桌面端侧边栏与移动端导航，双端共享同一份持久化数据。

### Requirement 4: 模式兼容与默认值

**User Story:** AS 用户, I want 自定义配置与现有简易/标准模式共存, so that 高级用户与普通用户各得其所。

#### Acceptance Criteria

1. WHEN 用户未做过任何自定义，THEN 系统 SHALL 按是否存在 `appMode==standard` 决定默认显示：标准模式全量显示，简易模式显示 `shown` 项。
2. WHEN 用户自定义了某入口显隐，且该入口属于当前模式默认可见/隐藏，THEN 系统 SHALL 以用户显隐偏好为准。
3. WHEN 用户在标准模式隐藏某入口，THEN 系统 SHALL 不将该入口从枢纽页移除（枢纽页始终全量可访问）。
4. WHEN 用户切换简易/标准模式，THEN 系统 SHALL 保留全部自定义显隐与固定配置，不重置。
5. WHEN 侧边栏为空（用户勾掉全部入口），THEN 系统 SHALL 展示兜底提示与"恢复默认"按钮。

### Requirement 5: 双端导航共享自定义配置

**User Story:** AS 用户, I want 桌面与移动端导航一致, so that 换设备使用时习惯不丢失。

#### Acceptance Criteria

1. WHEN 用户在桌面端自定义侧边栏，THEN 系统 SHALL 将配置写入 `UiSettings` 并持久化到同一份设置文件。
2. WHEN 移动端导航渲染，THEN 系统 SHALL 消费同一份自定义配置，与桌面端显示一致的入口集合。
3. WHEN 自定义配置将某入口隐藏，THEN 系统 SHALL 在双端导航中均不显示该入口。