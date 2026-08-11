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
