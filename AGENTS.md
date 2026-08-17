# AGENTS.md — AI 协作规则

本文件供任何 AI Agent（opencode / monkeycode / Copilot 等）在操作本仓库时读取并遵守。
涉及**发布新版本**的任务时，必须严格遵守 `docs/RELEASE_PROCESS.md` 的固定流程。

## 项目概要

- Flutter 应用「拓墨」：AI Markdown 写作 + 静态博客发布工具（Android / iOS / Web / 桌面）。
- 代码在 `lib/`，桌面入口 `lib/desktop/desktop_main.dart`，主入口 `lib/main.dart`。
- 仓库：`github.com/caogenfunan123/hexo`。

## 发布新版本的固定流程（必须遵守）

每次发布都必须走 `docs/RELEASE_PROCESS.md` 描述的统一流程，要点：

1. **版本号唯一来源是 `pubspec.yaml`**（`version: X.Y.Z+N`）。发版前必须递增版本号，
   同时更新 `lib/main.dart` 与 `lib/screens/settings_screen.dart` 中硬编码的 `_appVersion` / `_cachedVersion`。
2. **版本清单是 `release.json`**（仓库根目录）。发版时更新其中的 `version`、`notes`（更新日志）、
   `publishedAt` 及各平台 `url` / `sha256` / `size`。客户端（`lib/services/update_checker_service.dart`）
   通过 `https://raw.githubusercontent.com/caogenfunan123/hexo/main/release.json` 读取，无需 API token。
3. **发布触发入口是打 Git tag `vX.Y.Z` 并推送**，`.github/workflows/build.yml` 的 `release` job
   只在 tag push 时构建并创建 GitHub Release，普通代码 push 不会产生 release。
4. **下载产物统一放 GitHub Release assets**，命名固定：Android=`app-release.apk`，
   Windows=`hexo-windows.zip`，Linux=`hexo-linux.tar.gz`，Web 走 `hexo-web` 目录 artifact。
5. **优先执行 `tools/release.sh`** 完成整条发布链路（升版本 → 算 SHA256 → 更新 release.json →
   提交 → 打 tag → 推送）。不要手工零散改文件。

## 代码约定

- 纯 Dart 逻辑放 `lib/core/`，业务新方法写 mixins（放 `lib/mixins/`），纯组件放 `lib/widgets/`。
- 内置 AI 工具在 `lib/core/tools/builtin_tools.dart`，MCP 传输层在 `lib/core/tools/mcp_transport.dart`。
- 提交信息用 `feat|fix|chore|refactor|docs` 前缀，中文描述，单行 72 字以内。
- 禁止在代码中硬编码 token / 密钥；本仓库 Git 凭据只用于 push，不得写入代码或配置。

## 验证

- 本地仅有无 Flutter SDK 环境：用 `/tmp/opencode/dart/dart-sdk/bin/dart analyze <file>` 做纯 Dart 校验
  （`flutter_lints` 与 Flutter 包解析报错为噪音）；完整构建由 GitHub Actions CI 保证。
- 提交推送到 main 后，必须用 `gh run list` 关注 CI 状态，全绿才算完成。
