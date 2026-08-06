# Requirements Document

## Introduction

在 Hexo 博客写作与管理 App（Flutter）中，AI 会话模块需要落地两项核心能力：

1. **AI 会话安全读取仓库令牌、动态创建 MCP/Skill 工具并持久化到全局工具箱**：所有 AI 会话（文章创作、页面编辑、主题开发迁移、站点巡检）统一生效，AI 可自主编写工具定义，经格式与安全双重校验后入库复用，同时保证令牌不落入对话明文。
2. **全局 AI 模型调度器**：所有 AI 会话共用同一调度入口，后台探测各模型延迟、超时自动降级切换、完整继承上下文，保证任务不因模型故障而中断。

## Glossary

- **AI 会话（Session）**：`AiChatPanel` 驱动的一轮人机对话，包含文章创作、页面编辑、主题迁移、站点巡检等类型。
- **工具（Tool）**：AI 可调用的能力单元，类型包括内置工具（builtin）、技能（skill）、MCP 工具（mcp）。
- **MCP 定义**：AI 输出的 JSON 格式工具定义，含 `meta`（name/display_name/description/risk_level）与 `params` 参数列表。
- **Skill 定义**：AI 输出的 JSON 格式技能定义，含 `meta` 与 `steps` 步骤列表。
- **工具箱（Toolbox）**：`SkillManager` + `ToolRegistry` 管理的全部工具集合，持久化在 `skills.json` 与 `mcp_tools.json`。
- **仓库令牌（Token）**：当前选中站点的鉴权凭据，包括 Git Token（`RepoConfig.token`）、WordPress 应用密码、Ghost Admin API Key、Typecho Token。
- **站点私有工具**：仅当前仓库/站点会话可见的工具，标识符含站点 ID 作用域。
- **全局公用工具**：所有站点、所有 AI 对话均可见的工具。
- **AiRequestDispatcher**：全局请求调度入口，负责超时检测、自动择优、故障切换、上下文透传。
- **AiModelManager**：AI 模型实体 CRUD 与响应耗时统计管理。
- **AiModelProbeService**：后台探测模型响应速度的服务，维护动态优先级队列。
- **模型优先级队列**：按响应耗时、成功率排序的可用模型列表。

## Requirements

### Requirement 1：AI 会话读取仓库令牌（脱敏注入）

**User Story:** AS 博客作者，I want AI 会话在撰写、迁移、巡检时直接使用当前站点的鉴权凭据调用仓库能力，so that 我不需要手动把令牌粘贴进对话。

#### Acceptance Criteria

1. WHEN AI 会话发起且存在当前活跃站点，系统 SHALL 从站点配置中读取对应类型的令牌（Git Token / WordPress 应用密码 / Ghost Admin API Key / Typecho Token）。
2. WHEN 令牌注入 AI 工具调用环境，系统 SHALL 对令牌做掩码脱敏，AI 对话记录与日志中 SHALL NOT 出现令牌明文。
3. WHEN 令牌用于工具调用，系统 SHALL 仅在内层服务层注入真实值，AI 上下文仅持有调用能力与脱敏表示。
4. IF 当前站点未配置令牌，系统 SHALL 返回明确的缺凭据错误提示，并 SHALL 引导用户到站点设置页面补充配置。

### Requirement 2：AI 动态创建并保存 MCP/Skill 工具

**User Story:** AS 博客作者，I want AI 根据任务自行编写 MCP/Skill 工具并自动入库，so that 后续对话和其他站点可以复用这套能力。

#### Acceptance Criteria

1. WHEN AI 输出 NEW_MCP 或 NEW_SKILL 指令，系统 SHALL 解析出标准 JSON 工具定义并提交到校验管线。
2. WHEN 工具定义进入校验管线，系统 SHALL 先执行 JSON Schema 格式校验，再执行危险操作黑名单检测。
3. WHEN 格式校验失败，系统 SHALL 返回结构化错误给 AI，AI SHALL 修改定义后重新提交。
4. WHEN 定义命中危险操作黑名单（如删除全部文件、清空仓库、覆盖配置），系统 SHALL 拒绝保存并返回拦截原因。
5. WHEN 校验通过，系统 SHALL 将工具持久化到工具箱数据库，并 SHALL 在当前会话立即加载使用。
6. WHEN 工具保存完成，系统 SHALL 返回工具 ID 与风险等级给 AI，用于后续调用与展示。
7. IF 会话结束，已保存的工具 SHALL 仍然保留，新建对话 SHALL 可以复用已保存的工具集。

### Requirement 3：工具权限隔离（站点私有 / 全局公用）

**User Story:** AS 博客作者，I want 自动生成的工具可以标记作用域，so that 站点密钥不会跨仓库泄露。

#### Acceptance Criteria

1. WHEN AI 生成工具定义，系统 SHALL 允许工具标记为「站点私有」或「全局公用」。
2. WHILE 工具标记为站点私有，该工具 SHALL 仅对当前仓库会话可见，其他站点 SHALL 不可见。
3. WHILE 工具标记为全局公用，该工具 SHALL 对所有站点与所有对话可见。
4. WHEN 站点私有工具被调用，系统 SHALL 仅注入该站点对应的令牌。
5. IF 站点私有工具被其他站点会话引用，系统 SHALL 返回不可见/无权限错误。

### Requirement 4：工具箱的人工最终控制权

**User Story:** AS 博客作者，I want 在工具箱界面查看、禁用、编辑、删除 AI 自动生成的工具，so that 我对自动工具保有最终控制。

#### Acceptance Criteria

1. WHEN 用户打开工具箱页面，系统 SHALL 展示全部工具，并 SHALL 用来源标记区分「用户手动创建」与「AI 会话自动生成」。
2. WHEN 用户在工具箱禁用某工具，系统 SHALL 停止将该工具注入 AI 会话。
3. WHEN 用户在工具箱编辑或删除 AI 生成工具，系统 SHALL 持久化变更并 SHALL 在后续会话生效。
4. IF AI 生成工具的自动保存开关在设置页被关闭，系统 SHALL 拒绝自动入库，仅返回定义供用户手动审查。

### Requirement 5：模型速度探测与自动择优

**User Story:** AS 博客作者，I want 系统自动选择当前响应最快的模型，so that AI 回复更流畅。

#### Acceptance Criteria

1. WHEN 系统后台执行模型探测，系统 SHALL 对各已启用模型发起轻量 ping 请求，统计响应耗时（RT）。
2. WHEN 探测完成，系统 SHALL 维护按延迟排序的模型优先级列表，优先调用当前延迟最低的可用模型。
3. WHEN 用户开启「自动择优模式」，调度器 SHALL 依据优先级列表选择模型。
4. WHEN 用户关闭「自动择优模式」，调度器 SHALL 使用用户手动固定的模型。
5. WHEN 每次实际请求结束，系统 SHALL 将响应耗时与成败回写统计模块，SHALL 更新模型优先级。

### Requirement 6：超时降级切换与上下文对齐

**User Story:** AS 博客作者，I want 当前模型超时或报错时系统自动换下一个模型继续回复，so that 我不需要重发消息。

#### Acceptance Criteria

1. WHEN 当前模型请求超时、报错或限流，调度器 SHALL 保留完整 message 上下文数组（system prompt + 用户历史 + 工具调用记录），并 SHALL 携带全部历史继续请求下一个备选模型。
2. WHEN 模型发生切换，系统 SHALL 在对话日志写入切换事件，UI SHALL 展示「模型 xx 响应超时，已自动切换至 xx 继续处理」。
3. WHEN 模型切换，系统 SHALL 完整复制上下文，SHALL NOT 截断对话或丢失工具结果。
4. IF 切换次数达到最大重试次数（可配置，默认 3），系统 SHALL 终止请求，提示用户检查 API 配置。
5. IF 全部模型不可用，系统 SHALL 终止请求并弹窗提示检查 API 密钥与网络。
6. IF 上下文超长，系统 SHALL 先触发自动摘要压缩再切换模型，避免超出模型 token 上限。
7. IF 模型之间工具调用格式不同，调度层 SHALL 做工具格式适配转换，保证切换后工具调用仍有效。

### Requirement 7：会话 UI 状态回写

**User Story:** AS 博客作者，I want 对话界面实时显示实际使用的模型与切换记录，so that 我知道当前回复由哪个模型产出。

#### Acceptance Criteria

1. WHEN 每个 AI 对话界面打开，右上角 SHALL 显示当前使用模型。
2. WHEN 自动择优模式开启，界面 SHALL 标注「自动择优」。
3. WHEN 模型发生切换，对话框头部 SHALL 记录模型变更记录，界面 SHALL 显示当前实际模型。
4. WHEN 模型请求完成，系统 SHALL 统计各模型成功率与响应耗时，SHALL 反馈给模型探测模块更新优先级。

## 调用链路（约束）

```text
AI 会话发起 → AiToolManager 读取当前站点配置（令牌脱敏环境注入）
→ AI 输出新 MCP/Skill 定义 → 格式 & 安全校验
→ 通过：存入本地工具箱数据库；拒绝：返回错误给 AI，提示修改工具定义
→ 当前会话立刻加载新生成工具，直接使用
```

## 全局配置项

| 配置 | 默认值 | 说明 |
|------|--------|------|
| 请求超时阈值 | 25s | 超过即触发降级切换 |
| 最大自动切换次数 | 3 | 超过则终止请求 |
| 自动择优模式 | 开启 | 关闭时手动固定模型 |
| 允许 AI 自动保存工具 | 开启 | 关闭时仅返回定义不自动入库 |
