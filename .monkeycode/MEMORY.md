# User Instruction Memory

This file records user instructions, preferences, and teachings for reference in future interactions.

## Format

### User Instruction Entry
User instruction entries should follow this format:

[User Instruction Summary]
- Date: [YYYY-MM-DD]
- Context: [Mentioned scenario or time]
- Instructions:
  - [Content of user teaching or instruction, described line by line]

### Project Knowledge Entry
Entries discovered by the Agent during task execution should follow this format:

[Project Knowledge Summary]
- Date: [YYYY-MM-DD]
- Context: Discovered by Agent while performing [specific task description]
- Category: [Operations & Deployment|Build Methods|Testing Methods|Troubleshooting & Debugging|Workflow & Collaboration|Environment Configuration]
- Instructions:
  - [Specific knowledge points, described line by line]

## Deduplication Strategy
- Before adding a new entry, check for similar or identical instructions.
- If a duplicate is found, skip the new entry or merge it with the existing one.
- When merging, update the context or date information.
- This helps avoid redundant entries and keeps the memory file tidy.

## Entries

[Project Knowledge Summary]
- Date: 2026-08-11
- Context: User explicitly asks AI to always follow the repo's coding convention guide when modifying code
- Category: Workflow & Collaboration
- Instructions:
  - 修改本仓库任何 Dart 代码前，必须阅读 `.monkeycode/docs/code-splitting-guide.md`，并按第五节「新增代码时的行为准则」执行：新方法按业务域写入 `lib/mixins/editor_xxx_ext.dart`（不要堆进 main.dart 类体）；part 文件内一律用 `_applyState` 替代 `setState`；纯组件抽到 `lib/widgets/`；禁止新建 1000+ 行巨型文件
  - 用户侧提醒方式：直接说「按 code-splitting-guide.md 的规范写」即可

[Project Knowledge Summary]
- Date: 2026-08-11
- Context: Discovered by Agent while splitting _RootShellState (7425 行) into extension part files in lib/mixins/
- Category: Build Methods
- Instructions:
  - Flutter SDK 在 /tmp/opencode/flutter（stable，Dart 3.12.2），执行命令前需 `export PATH=/tmp/opencode/flutter/bin:$PATH`
  - 本仓库（hexo app）位于 /workspace，远程为 https://github.com/caogenfunan123/hexo.git，push 命令：`git -c credential.helper= -c credential.helper="store --file=/root/.netrc" push origin main`；查 CI 用 `export GH_TOKEN="$(awk '/machine github.com/{print $6}' /root/.netrc)"` + `gh run list`
  - 拆分巨型 State 类的可行方案：`mixin on` 自身类会报 recursive_interface_inheritance，mixin 无法访问宿主私有成员；**extension on _RootShellState + part of '../main.dart'** 同 library 可访问全部私有成员，唯一限制是不能直接调 State 的 protected setState —— 需在宿主类加 `void _applyState(VoidCallback fn) => setState(fn);` 包装，extension 内用 `_applyState` 替代 setState
  - 提取脚本：字符串/注释屏蔽（strip_line）+ 花括号配对得方法边界；支持多行参数声明（匹配行首返回类型关键字）；向上收集连续 `//`/`///` 注释（不跨空行）；提取后批量 `setState(` → `_applyState(`
  - 删除方法前先打印全部区间确认无重叠；已完成的 part：editor_publish/sync/settings_dialogs/ui/text/ai/repo/remote/misc/drawer_ext.dart（main.dart 1293 行，flutter analyze 0 error/warning、471+ info 全为历史 deprecated 类）
  - 本环境无 JDK/Android SDK，Android 构建验证只能靠 GitHub Actions CI；测试基线 +2 -1（test_batch_publish.dart frontmatter 单引号 vs 断言双引号，非重构引入）
  - 本环境无 PHP，无法运行 `php -l` 校验 SecureApi 插件 PHP 语法，只能人工审查

[Project Knowledge Summary]
- Date: 2026-08-16
- Context: Discovered by Agent while reviewing spec 完成度与功能现状
- Category: Troubleshooting & Debugging
- Instructions:
  - 三个功能存疑点（疑似"代码存在但未生效/未验证"，排查优先级从高到低）：
    1. 简易模式接线：`lib/desktop/feature_entries.dart`（AppMode/ModeVisibilityFilter/FeatureEntry 注册表）已实现，但 desktop_shell.dart 与 editor_ui_ext.dart 未搜到消费注册表的接线点，疑似未真正接入 left_panel 渲染与移动端 drawer 过滤
    2. 一键建站向导端到端未验证：`site_scaffold_builder.dart`(803 行)/`site_wizard_service.dart`(743 行)/`cloudflare_pages_provider.dart`/`framework_build_map.dart`/`wizard_models.dart` 代码齐全且 CI 编译通过，但 tasklist 全 `[ ]`，从未实测 GitHub 建 repo → CI Pages → Cloudflare deploy hook 全链路
    3. Agent 工作台思考模式空壳：operit spec 记录 `thinkingEnabled` 是未接线预留字段，agent_workbench_screen.dart 未搜到 reasoning/thinking 处理，疑似 deepseek-reasoner 仍被当普通模型调用，推理过程不渲染

[Project Knowledge Summary]
- Date: 2026-08-16
- Context: Discovered by Agent while studying open-source AI agent projects (MonkeyCode/Operit/Operit2) for features to reuse in hexo app's AI chat flow
- Category: Troubleshooting & Debugging
- Instructions:
  - Operit (github.com/AAswordman/Operit) 与 Operit2（Rust core + Flutter app）是 Android/跨平台 AI Agent，其上下文压缩、工具格式化、聊天 UI 设计可直接借鉴，参考源码在 /tmp/opencode/Operit、/tmp/opencode/Operit2
  - 上下文 LLM 摘要（AIMessageManager.rs / .kt）：增量摘要——只在历史中插一条 sender="summary" 消息，之后每次只总结"上次摘要之后"的消息；双触发（token 占比 >= 阈值 或 摘要后用户消息数 >= 16）；新摘要携带旧摘要融合；四段式固定格式【核心任务状态】【互动情节与设定】【对话历程与概要】【关键信息与上下文】，要求自包含可重建上下文
  - 工具结果格式化（ConversationMarkupManager）：多条结果累加超 64KB 停止追加；不同类型工具（终端/目录/文件）用专用展示格式，不给模型暴露 __type JSON 元数据
  - 工具权限（ToolExecutionManager checkToolPermission）：模型可用 deny_tool 标记声明"已授权"绕过确认，比按工具名判断更灵活
  - 工具结果/参数展示 UI：结果摘要 200 字 + 点击弹窗看全文 + 复制；大参数按字节数显示"N B"；read 类工具按名归组折叠"工具调用 (N)"；流式中自动展开、结束后折叠；thinking 默认折叠最新展开
  - MonkeyCode (github.com/chaitin/MonkeyCode) 核心 Agent 在私有 submodule OhMyAgent 拿不到，前端 task-stream-client.ts 有指数退避重连+chunk去重可参考；backend pkg/llm/client.go 是 OpenAI Chat/Responses/Anthropic 三协议适配（我们 ai_provider.dart 已对标 Provider/InterfaceType）
