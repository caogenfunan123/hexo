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
  - 三个功能存疑点（2026-08-16 已排查，结论如下）：
    1. 简易模式接线【已解决】：feature_entries 注册表实际已在 left_panel._nav / 移动端 drawer(navVisible) / main._navigateTo 三处消费；站点分组"添加站点/运维与监控"原先绕过 _nav，已改用 _nav 并补注册 'site_operations'(hidden)
    2. 一键建站向导端到端【静态审查通过，待真实环境实测】：site_wizard_service(→GitHubProvider/GitLabProvider/CloudflarePagesProvider/SiteScaffoldBuilder/RollbackManager) → create_site 工具(builtin_tools，由 AiChatPanel 注入 siteWizardService) → 向导 UI(site_wizard_screen fallback) 链路完整无代码断点；真实"GitHub 建 repo→CI Pages→CF deploy hook"需用户用真实 token 在应用内验证
    3. Agent 工作台思考模式【已解决】：thinkingEnabled 链路（AiModelEntity→_profileFromModel→ai_service body）完整，此前仅缺 UI 开关；已在 ai_model_manager_screen 添加模型对话框加"深度思考"开关+推理强度下拉，deepseek-reasoner 预设默认 thinking=true；ai_service 三处 OpenAI 路径 thinkingEnabled 时移除 temperature（reasoner/o 系列不接受非 1 temperature）；reasoning 提取→dispatcher→chat_panel 渲染已闭环
  - 模型推理兼容：OpenAI Chat/Responses 的 thinkingEnabled 需同时满足——发送 reasoning_effort/reasoning 参数、移除 temperature（reasoner/o 系列要求 temperature=1，发非 1 值会 400）；Anthropic 走 body.thinking 不受 temperature 限制

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

[Project Knowledge Summary]
- Date: 2026-09-07
- Context: User asked to hook the Archify architecture diagram into the regular development workflow
- Category: Workflow & Collaboration
- Instructions:
  - 存有拓墨主应用架构图：`/workspace/hexo/tuomo.architecture.html`（Archify 生成的单文件交互图，11 节点 + 区域边界「拓墨客户端（Flutter）」+ 3 个 view：写作主路径 / AI 辅助 / 一键发布；每个组件都带真实源码 sources）
  - 修改拓墨功能前先参考这张架构图：用图上节点定位「要改的层」，再按图上的 sources 找到对应源码文件；避免改错层或漏掉依赖（如控制器层→AI 引擎→LLM、发布编排→GitHub/CMS、本地存储→云同步）
  - 示意图是上下文辅助，本身不生成也不修改实现；真正的改动仍走正常开发，并按 code-splitting-guide.md 规范落地
  - 图产出的源 JSON 在 `/tmp/opencode/tuomo.architecture.json`，需要按新架构更新时可改动后重新 `node ~/.agents/skills/archify/bin/archify.mjs deliver architecture <json> /workspace/hexo/tuomo.architecture.html --quality showcase --repo-root /workspace/hexo`
