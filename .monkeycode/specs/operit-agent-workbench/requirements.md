# Requirements Document

## Introduction

在 Hexo 博客写作与管理 App（Flutter）中，将现有 AI 会话升级为 Operit 级别的 Agent 工作台，落地四项核心能力：

1. **Agent 任务工作台与思考模式**：面向任务的代理工作台（附件、工作区上下文、工具执行过程、文件变更、多轮任务管理），并让思考模式真实生效（reasoning 透传、推理过程渲染、thinking 模型正确调用）。
2. **模型路由增强**：密钥池、按任务类型分配模型、响应模式切换、连接测试。
3. **长期记忆与角色体系**：跨会话长期记忆（图谱化记忆、向量检索、摘要压缩）、角色卡绑定独立能力、多角色对话，并彻底修复多站点记忆隔离。
4. **工作流引擎**：可视化节点编排（触发/执行/条件/逻辑/数据提取），构建可重复执行的流程任务。

用户核心痛点：当前 AI 工具箱**没有真实思考模式**（`thinkingEnabled` 是未接线预留字段，deepseek-reasoner 被当普通模型调用）、**多站点逻辑分散**（对话历史不按站点隔离、dispatcher 全局单例串场）、**只有会话级记忆**（无长期记忆、无 RAG）。

## Confirmed Decisions（2026-08-09）

1. **本地模型直接集成 llama.cpp（GGUF）**：通过 FFI 在 Android 端直接跑 GGUF 模型，写文章完全离线，不依赖 Ollama 中转。
2. **第一批优先交付 Agent 工作台 + 思考模式**：工作台（附件/工作区/工具过程/文件变更/多轮任务）与真实思考模式先行，长期记忆与工作流引擎作为后续迭代纳入同一 spec。
3. **模型配置全局共享**：`ai_models.json` 保持全局共享，仅对话历史、长期记忆、工具作用域按站点隔离。

## Glossary

- **Agent 工作台（Agent Workbench）**：面向任务的 AI 任务执行界面，支持附件、工作区上下文、工具执行过程展示、文件变更追踪与多轮任务管理。
- **思考模式（Thinking Mode）**：模型推理能力透传。开启后请求携带 `reasoning_effort`/`thinking` 参数，响应中的 `reasoning_content` 独立渲染展示。
- **任务（Task）**：工作台中一次 AI 执行单元，包含目标、上下文、工具调用记录与产出。
- **密钥池（Key Pool）**：同提供商下多组 API Key 的集合，按轮转/优先级分配。
- **任务类型（Task Group）**：`code` / `general` / `longtext` 三类模型分组，按任务性质路由到对应模型。
- **记忆空间（Memory Space）**：独立命名空间下的长期记忆集合，支持文档导入、分块、向量检索与关系编辑。
- **角色卡（Role Card）**：角色定义（系统提示词、人格、绑定模型/记忆/工具），兼容 Tavern JSON/PNG 格式。
- **多角色对话**：一个对话中多个角色参与，支持 @ 交互、角色间协作。
- **工作流（Workflow）**：可视化节点编排的可执行任务流程，含触发、执行、条件、逻辑、数据提取节点。
- **站点隔离（Site Isolation）**：对话历史、长期记忆、工具作用域按站点独立存储，切换站点不串场。
- **本地模型（Local Model）**：通过 Ollama / llama.cpp（GGUF）在设备端运行的模型，写文章无需在线模型。

## Requirements

### Requirement 1：真实思考模式

**User Story:** AS 博客作者，I want AI 在写作时开启深度思考并看到推理过程，so that 生成内容更可靠且我了解其思路。

#### Acceptance Criteria

1. WHEN 用户为模型开启「思考模式」，系统 SHALL 在请求体中携带对应提供商的推理参数（OpenAI `reasoning_effort`、Anthropic `thinking`、DeepSeek `reasoner` 协议），并 SHALL 调用思考模型（如 deepseek-reasoner）。
2. WHEN 模型返回推理内容，系统 SHALL 解析 `reasoning_content` 或 `thinking` 块，并 SHALL 在对话界面独立区块渲染推理过程，SHALL NOT 将推理文本混入正文回复。
3. WHEN 会话切换模型，思考模式开关 SHALL 随模型生效状态正确重置或继承。
4. IF 模型不支持思考模式，系统 SHALL 隐藏或禁用思考开关，SHALL 提示该模型不支持。
5. WHEN 思考模式下工具调用，系统 SHALL 在推理与工具执行之间正确衔接，工具结果 SHALL 不影响推理过程展示。

### Requirement 2：Agent 任务工作台

**User Story:** AS 博客作者，I want 一个面向任务的代理工作台，so that 我可以给 AI 一个完整任务（附件+工作区+多轮对话），并实时看到工具执行过程和文件变更。

#### Acceptance Criteria

1. WHEN 用户发起任务，系统 SHALL 允许附加文件、绑定工作区（当前站点仓库）、并记录任务目标。
2. WHILE 任务执行，系统 SHALL 以时间线形式展示每个工具调用的执行过程（工具名、入参摘要、结果、耗时、状态）。
3. WHEN 任务修改文件，系统 SHALL 追踪文件变更（新增/修改/删除），并 SHALL 在任务结束时展示变更清单与 Diff 预览。
4. WHEN 用户在多轮任务中继续追问，系统 SHALL 保留完整上下文（含工具执行记录），SHALL 支持任务续跑。
5. WHEN 任务完成，系统 SHALL 生成任务总结（产出物清单、变更统计、耗时）。
6. IF 任务执行中断，系统 SHALL 保存任务状态，用户 SHALL 可从断点恢复。
7. WHEN 对话绑定工作区，系统 SHALL 让 AI 读取项目规则（如 `.monkeycode/MEMORY.md`、AGENTS.md）、引用文件并修改代码。

### Requirement 3：多站点记忆隔离修复

**User Story:** AS 多站点博主，I want 每个站点的 AI 对话与记忆完全隔离，so that 切换站点不会串场。

#### Acceptance Criteria

1. WHEN 用户切换站点，系统 SHALL 将对话历史、长期记忆、工具作用域按站点隔离加载，SHALL NOT 混入其他站点内容。
2. WHEN AI 会话持久化，系统 SHALL 将 `ai_chat_{sessionType}.json` 扩展为按站点分区（如 `ai_chat_{siteId}_{sessionType}.json`）。
3. WHEN 全局 dispatcher 处理请求，系统 SHALL 为每个站点持有独立上下文实例，切换站点 SHALL 不污染其他站点的上下文。
4. WHEN 记忆检索，系统 SHALL 仅检索当前站点记忆空间内的内容。
5. IF 站点数据开启加密（SiteIsolationService），AI 聊天记录 SHALL 同样纳入该站点的加密存储。

### Requirement 4：密钥池与模型路由增强

**User Story:** AS 多模型用户，I want 同一提供商支持多组 API Key 并可按任务类型自动分配模型，so that 密钥轮转与任务分流自动化。

#### Acceptance Criteria

1. WHEN 用户配置密钥池，系统 SHALL 允许同一提供商录入多组 Key，并按轮转/失败剔除策略分配。
2. WHEN 请求发起，系统 SHALL 按任务类型（code/general/longtext）从对应分组的模型中路由选择。
3. WHEN 密钥池中的 Key 请求失败，系统 SHALL 自动切换池内下一组 Key，SHALL 记录失败次数。
4. WHEN 用户手动固定模型，系统 SHALL 绕过自动路由，SHALL 使用用户指定模型。
5. WHEN 用户执行连接测试，系统 SHALL 对选定模型发起探测请求，SHALL 展示连通性、延迟与协议兼容性结果。
6. WHEN 本地模型（Ollama/llama.cpp）可用，系统 SHALL 将其纳入模型列表，写文章任务 SHALL 可选择本地模型离线执行。

### Requirement 5：长期记忆与角色体系

**User Story:** AS 博客作者，I want AI 记住跨会话的偏好与知识，并可通过角色卡绑定独立能力，so that 长期写作风格一致、不同场景用不同角色。

#### Acceptance Criteria

1. WHEN 对话产生重要信息，系统 SHALL 支持从对话/附件提取信息写入记忆空间，支持文档导入与分块。
2. WHEN 记忆检索，系统 SHALL 支持按时间、语义（向量）及关系混合检索。
3. WHEN 新会话加载，系统 SHALL 将相关长期记忆注入上下文，SHALL 标注记忆来源。
4. WHEN 用户创建角色卡，系统 SHALL 支持导入/导出/备份（兼容 Tavern JSON/PNG），角色 SHALL 绑定独立模型、记忆空间、工具包、Skill 与 MCP。
5. WHEN 多角色对话开启，系统 SHALL 支持多角色群聊、@ 交互、独立对话历史与角色间协作。
6. IF 上下文超长，系统 SHALL 先触发自动摘要压缩再继续，压缩摘要 SHALL 保留关键信息并标注。

### Requirement 6：工作流引擎

**User Story:** AS 自动化爱好者，I want 可视化编排可重复执行的任务流程，so that 复杂流程一键运行。

#### Acceptance Criteria

1. WHEN 用户创建工作流，系统 SHALL 提供节点画布（触发、执行、条件、逻辑、数据提取），支持拖拽连线。
2. WHEN 工作流保存，系统 SHALL 持久化节点图定义，SHALL 支持手动/定时触发运行。
3. WHILE 工作流运行，系统 SHALL 按节点顺序执行，条件节点 SHALL 依据判断结果分流。
4. WHEN 工作流执行结束，系统 SHALL 提供执行日志、统计与结果汇总，SHALL 支持中途取消。
5. WHEN 节点包含 AI 任务，系统 SHALL 复用 Agent 工作台能力执行该节点。
6. IF 节点执行失败，系统 SHALL 支持配置失败处理（跳过/终止/回滚）。

## 全局配置项

| 配置 | 默认值 | 说明 |
|------|--------|------|
| 思考模式默认开启 | 关 | 逐模型可配置 |
| 记忆空间默认数量 | 1 | 每站点独立 |
| 密钥池失败剔除阈值 | 3 次 | 连续失败则暂时移出轮转 |
| 工作流定时触发 | 支持 | cron 表达式 |
| 本地模型推理通道 | llama.cpp GGUF | Android FFI 直连，无 Ollama 依赖 |
| 上下文压缩阈值 | 模型 contextLimit 的 80% | 超限触发摘要 |
| 本地模型最大上下文 | 2048 | GGUF 模型默认，可调 |
