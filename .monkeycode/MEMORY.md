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
  - Flutter SDK 安装在 /tmp/opencode/flutter（stable 3.44.9，Dart 3.12.2，2026-08-10 在当前会话环境新装），执行命令前需 `export PATH=/tmp/opencode/flutter/bin:$PATH`；执行前先 `git config --global --add safe.directory /tmp/opencode/flutter`（避免 dubious ownership 报错）
  - hexo 仓库克隆在 /tmp/opencode/hexo（远程 origin 已内嵌 GitHub token，main 分支直接提交并 push）
  - 编译/analyze 命令必须在后台终端执行：`cd /tmp/opencode/hexo && export PATH=/tmp/opencode/flutter/bin:$PATH && flutter pub get && flutter analyze`
  - `flutter analyze` 基线约 600+ issues，几乎全部是历史遗留的 `withOpacity` deprecated info、`test/`（test_batch_publish/test_localizations 引用不存在的 package:hexo_app 与 flutter_test）与各屏既有问题；本功能改动文件（markdown_diff / static_blog_batch_publish_service / static_blog_posts_screen / ai_service / ai_request_dispatcher）不新增任何 issue
  - 本环境无 PHP，无法运行 `php -l` 校验 SecureApi 插件 PHP 语法，只能人工审查
