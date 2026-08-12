# Requirements Document

Feature: simple-user-mode
Date: 2026-08-12

## Introduction

拓墨当前是面向开发者与博主的一体化工作台，侧边栏同时呈现写作、建站、开发运维、批量工具与系统诊断等全部入口。对仅使用「写作 + AI 辅助 + 同步发布」的普通用户，大量专业入口造成干扰。

本需求引入 **简易普通用户模式** 与 **标准专业模式** 双模式。简易模式保留全部同步功能与完整 AI 对话/模型配置，仅隐藏普通用户用不到的专业建站、开发与运维入口，呈现极简侧边栏；标准模式保持现状全量展示。两种模式共享同一份配置与数据，切换实时生效且不重置任何用户数据。简易模式同时覆盖桌面端（left_panel）与移动端（MobilePage）导航，**新用户首次启动默认进入简易模式**，可在设置中随时切换到标准模式。

核心约束（不可违反）：
1. 全部同步功能完整保留且可见：Git 推送（Gitee/GitHub）、WebDAV、局域网 P2P、双向冲突同步、版本快照、仓库回滚。
2. 完整 AI 对话与模型配置保留：对话窗口、全部模型服务商、API 密钥管理、模型切换、基础润色/扩写/翻译等。
3. 仅隐藏普通用户用不到的专业入口，隐藏通过「不渲染入口」实现，不删除底层功能与数据。

## Glossary

- **简易普通用户模式（简易模式）**：面向只使用写作、AI 与同步的用户的界面模式，隐藏专业入口；新用户首次启动默认启用。
- **标准专业模式（标准模式）**：当前完整功能界面，全部入口可见。
- **卷宗**：文章的分组容器（如 卷1 / 卷2）。作为新增概念，文章通过卷宗字段归类，首页文章列表按卷宗分组展示。
- **系统诊断日志**：应用自动生成的非用户稿件（文件名以 `llama_diag_log` 等系统前缀开头），在简易模式首页文章列表中自动过滤。
- **专业入口**：Agent 工作台、主题开发/迁移、站点巡检、MCP、Skill 编辑器、批量运维、CI/部署 Hook、诊断日志导出等。
- **可配置入口**：简易模式下默认隐藏、但允许用户在设置中手动加回显示的入口（如 网站预览、RSS 订阅、回收站、片段素材库 等）。

## Requirements

### R1 双模式切换

**User Story:** AS 普通用户, I want 在简易模式与标准模式间一键切换, so that 界面复杂度由我掌控。

#### Acceptance Criteria

1. WHEN 新用户首次启动应用（无设置文件），the system SHALL 默认进入简易普通用户模式。
2. WHEN 存量用户首次升级后进入应用（存在设置文件但无模式记录），the system SHALL 弹出模式选择引导弹窗，由用户选择简易或标准模式并持久化。
3. WHEN 用户打开设置中的模式选项，the system SHALL 提供「简易普通用户模式」与「标准专业模式」两个选项。
4. WHEN 用户切换模式，the system SHALL 实时重载侧边栏入口与可见页面组件，无需重启应用，桌面端与移动端同步生效。
5. WHILE 简易模式处于激活状态，the system SHALL 持久化该模式选择，下次启动沿用。
6. IF 当前页面在简易模式下不可见，the system SHALL 自动导航到简易模式可见的首页。
7. WHEN 用户切换模式，the system SHALL 保留全部既有配置（模型密钥、同步仓库、Token 档案、存储目录），切换不得重置任何数据。

### R2 简易模式侧边栏入口

**User Story:** AS 普通用户, I want 极简的侧边栏, so that 只看到写作与同步相关入口。

#### Acceptance Criteria

1. WHILE 简易模式处于激活状态，the system SHALL 在侧边栏仅展示以下分组入口：
   - 首页：当前卷宗文章列表，卷1/卷2 分类完整保留，自动过滤系统诊断日志文件
   - 编辑器：新建文章 / 随笔 / 博客文稿
   - AI 写作对话：完整对话窗口，全部模型配置入口可见
   - 同步与站点：全部同步功能内置（Git 推送、WebDAV、P2P、版本快照、冲突合并），仅保留单站点基础管理
   - 图床：基础上传、CDN 链接复制
   - 草稿箱：本地与云端同步草稿统一查看
   - 设置：完整保留 AI 模型配置、多密钥档案、代理、同步定时、存储目录迁移
2. WHILE 简易模式处于激活状态，the system SHALL 隐藏多站点批量聚合、批量删除、递归文件夹批量上传等批量运维入口。
3. WHILE 简易模式处于激活状态，the system SHALL 在设置界面提供「简易普通用户模式」开关（开启/关闭），关闭即切换为标准专业模式。
4. WHILE 简易模式处于激活状态，the system SHALL 精简设置界面，仅保留以下分区：基本信息、模式开关、Git Token 档案、同步定时、存储目录、AI 模型配置、AI 密钥管理、代理、图床。
5. WHILE 简易模式处于激活状态，the system SHALL 在设置界面隐藏以下开发配置分区：AES 加密高级管理、风险操作黑名单、CI 流水线、Cloudflare 部署 Hook、诊断日志导出、底层文件系统调试。

### R3 简易模式隐藏入口清单

**User Story:** AS 普通用户, I want 专业入口不渲染, so that 侧边栏清爽无干扰。

#### Acceptance Criteria

1. WHILE 简易模式处于激活状态，the system SHALL 隐藏以下 AI 专业入口：Agent 任务工作台、主题开发会话、主题迁移、站点巡检、模板/框架诊断会话、MCP 服务器接入、Skill 编辑器、全局工具库、Token 深度仪表盘、模型连通性批量检测、火山方舟错误调试面板。
2. WHILE 简易模式处于激活状态，the system SHALL 隐藏以下批量运维入口：多站点聚合批量管理、批量发布、批量删除、文件夹递归批量上传、全局 FrontMatter 批量修改、CI/Actions 构建日志、Cloudflare 部署钩子、自定义流水线配置。
3. WHILE 简易模式处于激活状态，the system SHALL 隐藏以下诊断入口：模型诊断日志生成、日志导出、底层文件系统调试、仓库底层快照回滚专业调试界面。
4. WHILE 简易模式处于激活状态，the system SHALL 默认隐藏以下边界模糊入口：网站预览、RSS 订阅、回收站、片段素材库、AI 页面创作、AI 提示词模板，且允许用户按 R9 手动加回。

### R4 同步功能完整保留

**User Story:** AS 普通用户, I want 同步能力一个不少, so that 写作数据可跨端安全同步。

#### Acceptance Criteria

1. WHILE 简易模式处于激活状态，the system SHALL 提供 Git 全功能：Gitee/GitHub 仓库绑定、一键推送、提交历史、文件回滚、多 Git 令牌档案。
2. WHILE 简易模式处于激活状态，the system SHALL 提供 WebDAV 完整同步：自定义网盘目录、定时同步间隔、双向同步、冲突弹窗对比。
3. WHILE 简易模式处于激活状态，the system SHALL 提供局域网 P2P 同步：mDNS 设备发现、增量文件传输、设备配对。
4. WHILE 简易模式处于激活状态，the system SHALL 提供快照与版本：文稿时间线快照、手动快照标记、快照恢复、冲突 diff 分栏合并。

### R5 AI 模块完整保留

**User Story:** AS 普通用户, I want 完整 AI 写作能力, so that 润色翻译摘要等全部可用。

#### Acceptance Criteria

1. WHILE 简易模式处于激活状态，the system SHALL 提供完整 AI 对话：全文润色、扩写、缩写、翻译、摘要、选区 diff 对比接受。
2. WHILE 简易模式处于激活状态，the system SHALL 展示全部 12 类模型服务商（DeepSeek/通义/GLM/Kimi/Gemini 等），支持 API 密钥新增/编辑/删除、多 Key 轮换池、模型切换。
3. WHILE 简易模式处于激活状态，the system SHALL 隐藏开发向 AI 会话：Agent 工具调用循环、网页检索工具、文件读写工具、主题开发会话。

### R6 首页文章列表过滤

**User Story:** AS 普通用户, I want 首页只显示我写的文章, so that 不被系统日志干扰。

#### Acceptance Criteria

1. WHILE 简易模式处于激活状态，the system SHALL 在首页文章列表自动过滤系统生成日志文件（如 `llama_diag_log` 类），仅展示用户手动创建的 Markdown 文章。
2. WHEN 系统生成诊断日志文件，the system SHALL 不将其展示在简易模式首页列表中。

### R7 顶部工具栏精简

**User Story:** AS 普通用户, I want 精简的顶部工具栏, so that 只有基础操作。

#### Acceptance Criteria

1. WHILE 简易模式处于激活状态，the system SHALL 隐藏以下按钮：导出诊断日志、批量站点检测、模型连通性批量测试。
2. WHILE 简易模式处于激活状态，the system SHALL 保留以下按钮：搜索、排序、新建文稿。

### R8 新手引导适配

**User Story:** AS 普通用户, I want 引导只讲基础操作, so that 不接触专业术语。

#### Acceptance Criteria

1. WHILE 简易模式处于激活状态，the system SHALL 展示「卷宗分类写作 → AI 润色对话 → 同步云端/Git 发布」引导内容。
2. WHILE 简易模式处于激活状态，the system SHALL 不在引导中提及主题开发、CI、批量运维等专业术语。

### R9 简易模式入口可配置

**User Story:** AS 用户, I want 在简易模式下手动加回个别入口, so that 不被固定隐藏清单限制。

#### Acceptance Criteria

1. WHEN 用户在设置中管理「简易模式额外入口」，the system SHALL 允许对边界模糊入口（网站预览、RSS 订阅、回收站、片段素材库、AI 页面创作、AI 提示词模板）进行勾选显示或取消隐藏。
2. WHEN 用户将某边界入口勾选为显示，the system SHALL 在简易模式侧边栏对应分组中渲染该入口。
3. WHILE 简易模式处于激活状态，the system SHALL 保持该用户自定义可见入口集合持久化。
4. WHILE 标准模式处于激活状态，the system SHALL 忽略该自定义集合，全部入口可见。
5. WHEN 用户切换回简易模式，the system SHALL 依据自定义集合恢复侧边栏渲染。

## 需求确认记录

- 「卷宗 / 卷1 / 卷2」为新增概念，通过 `Article.volume` 字段归类，首页列表按卷宗分组，旧文章归「未分类」。
- `llama_diag_log` 为系统诊断日志命名前缀，简易模式首页列表过滤该前缀文件。
- 简易模式覆盖桌面端与移动端导航；新用户首次启动默认简易模式；存量用户首次升级进入时弹窗自选模式。
- 边界模糊入口（网站预览/RSS/回收站/片段素材库/AI 页面创作/AI 提示词模板）默认隐藏，可在设置中手动加回（R9）。
