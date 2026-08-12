# 拓墨 开发者指南

## 项目目的

拓墨是 AI 驱动的 Markdown 写作与博客发布工具。它在统一工作台中整合写作、AI 辅助、多平台发布与站点管理，是博客作者的全栈内容工作台。

**核心职责**:
- Markdown 写作编辑（桌面/移动双端、源码/预览/分屏三模式）
- AI 辅助写作（润色/续写/摘要/大纲/翻译/改写/审计/主题迁移）
- 多平台发布（GitHub/GitLab/Gitee/Bitbucket 静态博客 + WordPress/Ghost/Typecho 动态 CMS）
- 图床、站点管理、数据同步与数据安全

**相关系统**:
- Git 托管平台（GitHub / GitLab / Gitee / Bitbucket）— 静态博客仓库
- 动态 CMS（WordPress / Ghost / Typecho）— REST 发布目标
- AI 模型服务（12 个预置 Provider，OpenAI 兼容协议）
- WebDAV 服务器 — 云同步后端
- GitHub Actions — CI 构建

## 环境搭建

### 前置条件

- Flutter >= 3.44（SDK 约束 `>=3.10.7 <4.0.0`）
- Dart SDK（随 Flutter 附带）
- 桌面平台（Windows/macOS/Linux）需各自平台工具链

### 安装

```bash
git clone git@github.com:caogenfunan123/hexo.git
cd hexo
flutter pub get
```

### 运行

```bash
flutter run -d windows     # 桌面端
flutter run -d linux       # Linux 桌面
flutter run -d android     # Android
flutter build apk --debug  # Android APK
flutter build web          # Web
```

## 环境配置

本项目无 `.env` 文件。所有配置均通过应用内设置界面完成，持久化为 JSON 文件（全局存储目录 `~/.hexo_app`）。模型、Git Token、CMS 凭据均在应用内管理，**不提交到代码仓库**。

## 开发工作流

### 代码质量工具

| 工具 | 命令 | 目的 |
|------|------|------|
| Flutter Analyze | `flutter analyze` | 静态分析（约定：0 error / 0 warning） |

> 说明：项目存在 474 个存量 deprecated info 级提示，属于可接受项，不要求清理；但新增代码不得引入新的 error / warning。

### 提交前检查

1. 运行 `flutter analyze`，确认 0 error / 0 warning
2. 检查是否误提交密钥或本地配置
3. 提交信息遵循 Conventional Commits（如 `feat(adapter): add GitLab support`）

### 分支策略

- `main` — 生产就绪代码
- 功能/修复在本地分支开发，推送触发 GitHub Actions CI

### CI 流程

本地 push 后 GitHub Actions 自动构建 Web + Android APK（约 8 分钟）。APK 产物可通过 GitHub Actions 页面下载，或发布到 Releases。

## 常见任务

### 新增一个 Git 平台适配

**需修改的文件**:
1. `lib/models/git_provider.dart` — 枚举加新类型
2. `lib/services/git_providers.dart` — 实现 `GitProviderAdapter`
3. `lib/services/github_service.dart` — `adapterFor()` 分发新类型
4. UI 平台下拉（`editor_repo_ext.dart`、`settings_screen.dart`）

**要点**:
- 遵循 `git_http.dart` 的 `encPathSegments`/`encPathFull` 编码策略（按平台路径编码要求选择）
- 认证头按平台要求实现（Bearer / PRIVATE-TOKEN / Basic / query 双通道）
- 写操作返回 sha 的语义与 `rollbackFile` 一致

### 新增一个动态 CMS 适配器

**需修改的文件**:
1. `lib/core/repository/` — 新增 `implements BlogRepository` 的适配器
2. `lib/core/site_manager.dart` — 工厂分支
3. `lib/screens/blog_site_editor_screen.dart` — 站点配置表单

**要点**:
- 实现 `BlogRepository` 全部方法，写操作语义与既有适配器对齐
- 若接口只读，写操作抛 `BlogRepositoryException`（参考 `typecho_fastapi_adapter.dart`）
- 防反爬可复用 `JsChallengeGuard` / `JsChallengeHttp`

### 新增 AI 会话类型

**需修改的文件**:
1. `lib/core/ai/ai_session_manager.dart` — `AiSessionType` 加枚举 + System Prompt 工厂
2. `lib/screens/` — 新增会话页（参考 `ai_article_chat_screen.dart`）

**要点**:
- 复用 `AiRequestDispatcher`（流式/故障切换/工具循环）
- 复用 `AiSelfChecker`（本地检查 + AI 深度自检两级链路）
- 会话上下文经 `SiteDispatcherManager` 按站点隔离

### 新增一个内置 AI 工具

**需修改的文件**:
1. `lib/core/tools/builtin_tools.dart` — 定义 `ToolEntity` + `execute()` 分发 + 执行器
2. `lib/core/tools/tool_schema_validator.dart` — 如需危险操作检测

**要点**:
- 工具定义与实现分离，`execute()` 为统一分发入口
- 涉及站点的工具注入脱敏凭据（`TokenVault`），真实值只进服务层

### 修复 Bug

**流程**:
1. 定位根因（`flutter analyze` 先行，缩小范围）
2. 用最小改动修复
3. 全量 `flutter analyze` 确认 0 error / 0 warning
4. 检查 CI 结果

## 编码规范

### 文件组织
- 业务核心放 `lib/core/`（与 UI 解耦），页面放 `lib/screens/`，桌面组件放 `lib/desktop/widgets/`
- 模型放 `lib/models/`，服务放 `lib/services/`
- 文件操作一律经 `AppFileOperator` 抽象（`core/file_manager/file_abstract.dart`），禁止直接使用 `dart:io` File 裸操作

### 命名

| 类型 | 约定 | 示例 |
|------|------|------|
| 文件 | snake_case | `git_providers.dart` |
| 类 | PascalCase | `GitHubService` |
| 方法 | camelCase | `commitFile` |
| 常量 | SCREAMING_SNAKE | `githubApiBase` |
| 服务后缀 | Service / Adapter | `SyncService` / `WordPressAdapter` |

### 分层约束

- UI 不直接访问 Git/CMS 平台细节，经服务层门面
- 静态博客与动态 CMS 统一走 `BlogRepository` 接口
- Git 多平台统一走 `GitHubService` 门面 + `GitProviderAdapter`

### 错误处理

- 服务层抛领域异常（如 `BlogRepositoryException`）
- UI 层用 `UiStateController` 展示 toast，错误信息对用户可读
- 高风险工具操作经确认门（未注入确认回调时直接拒绝）

### 回调治理
- 避免多参回调层层传递：复用 `ShellActionBus` / `LeftPanelActionNotifier`
- 新增导航/动作回调优先考虑挂到统一总线
