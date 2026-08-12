# core/ai（AI 会话与调度）

AI 能力中枢：会话 Prompt 工厂、请求调度、模型管理、自检与主题迁移。共 11 个文件。

## 结构

```
ai/
├── ai_session_manager.dart      # 7 类会话 System Prompt 工厂
├── ai_request_dispatcher.dart   # 流式/非流式分发、故障切换、工具循环（≤12 轮）
├── ai_model_manager.dart        # 模型 CRUD、密钥池轮转、连通性检测
├── ai_model_entity.dart         # 模型实体与统计
├── ai_model_probe_service.dart  # 并发延迟探测 + 动态优先级队列
├── ai_self_checker.dart         # 本地快速检查 + AI 深度自检两级链路
├── ai_tool_manager.dart         # AI 创建工具链路（脱敏凭据 → 校验 → 持久化）
├── ai_provider.dart             # 12 个 Provider / 3 种接口协议常量
├── site_dispatcher_manager.dart # 按站点隔离调度器
├── theme_migration_service.dart # 跨框架主题迁移
└── token_vault.dart             # 凭据脱敏（掩码进 AI 上下文）
```

## 关键文件

| 文件 | 目的 |
|------|------|
| `ai_session_manager.dart` | 会话 Prompt 组装（全局内核 + 场景 + 动态上下文） |
| `ai_request_dispatcher.dart` | 请求生命周期与故障自愈 |
| `ai_self_checker.dart` | AI 输出质量护栏 |
| `site_dispatcher_manager.dart` | 多站点上下文隔离 |

## 依赖

**本模块依赖**: `core/tools/`（工具执行）、`services/`（Git/CMS）
**依赖本模块的**: 6 个 AI 会话 Screen、`agent_workbench_screen.dart`、`widgets/ai_chat_panel.dart`、`desktop/desktop_shell.dart`

## 规范

- 新会话类型：在 `AiSessionType` 加枚举 + Prompt 工厂注册
- 模型请求一律经 `AiRequestDispatcher`（获得切换/工具循环能力）
- 涉及站点的 AI 凭据经 `TokenVault` 脱敏，真实值只进服务层
