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
- Date: 2026-08-10
- Context: Discovered by Agent while installing Flutter SDK to verify hexo app Dart code compiles
- Category: Environment Configuration
- Instructions:
  - Flutter SDK 安装在 /opt/flutter（stable 分支，Dart 3.12.2，2026-08-10 已重新完整安装并通过 `flutter --version`），执行命令前需 `export PATH=/opt/flutter/bin:$PATH`
  - 编译/analyze 命令必须在后台终端执行：`cd /workspace/hexo && export PATH=/opt/flutter/bin:$PATH && flutter pub get && flutter analyze`
  - `flutter analyze` 当前基线：约 600 个 issues，几乎全部是历史遗留的 `withOpacity`/`value`/`onChanged` deprecated info 与 `test/`、`example/`、`unified_remote_posts_screen.dart` 的既有 error；AI 本地模型相关改动文件（local_llama_provider / ai_service / ai_request_dispatcher / ai_model_manager_screen / settings_screen / main / desktop_shell）为 0 error
  - 本环境无 PHP，无法运行 `php -l` 校验 SecureApi 插件 PHP 语法，只能人工审查
