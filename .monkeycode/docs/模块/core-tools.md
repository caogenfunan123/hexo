# core/tools（工具系统）

AI 的工具能力层：内置工具、Skill、MCP 三类工具的注册、执行、校验与运行时。共 13 个文件。

## 结构

```
tools/
├── tool_entity.dart           # ToolEntity 统一模型 + 三协议请求解析
├── builtin_tools.dart         # 21 个内置工具定义与实现
├── remote_cms_tools.dart      # 16 个 WordPress/Ghost/Typecho 工具
├── tool_executor.dart         # 执行器（builtin/skill/mcp 分发）
├── tool_registry.dart         # 注册表（单例）
├── skill_manager.dart         # Skill/MCP 工具 CRUD 与持久化
├── mcp_runtime.dart           # AI 指令运行时（NEW_MCP/SKILL_RUN/MCP_CALL…）
├── mcp_server.dart            # 外部 MCP 服务器接入
├── instruction_parser.dart    # 9 种指令标记正则解析
├── tool_schema_validator.dart # JSON Schema 校验 + 危险操作黑名单
├── toolbox_repository.dart    # 工具库仓储（作用域/来源/风险）
└── tool_format_adapter.dart   # 厂商格式适配（Gemini/OpenAI，预留）
```

## 关键文件

| 文件 | 目的 |
|------|------|
| `builtin_tools.dart` | Web 搜索四引擎、文件/目录、Git 快照回滚克隆、Skill/模板/文章工具 |
| `mcp_runtime.dart` | AI 输出指令执行 + Skill 流水线（变量占位/失败回滚） |
| `tool_schema_validator.dart` | 危险操作黑名单（rm -rf、drop database 等） |
| `tool_executor.dart` | 统一执行入口 + 结果格式化为 role:tool |

## 依赖

**本模块依赖**: `core/ai/`（TokenVault 脱敏、AiToolManager）、`core/repository/`（CMS 工具）
**依赖本模块的**: `widgets/ai_chat_panel.dart`、`core/ai/ai_request_dispatcher.dart`、`screens/`

## 规范

- 新内置工具：定义 `ToolEntity` + `execute()` 分发 + 私有执行器三件套
- 高风险操作必须经确认门
- AI 创建的工具定义必须先过 `ToolSchemaValidator` 再持久化
