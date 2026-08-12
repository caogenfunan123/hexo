# 拓墨（Hexo）项目文档

本套文档面向开发者和协作者，覆盖拓墨——AI 驱动的 Markdown 写作与博客发布工具的架构、接口、开发流程与核心概念。

**快速链接**: [架构](./ARCHITECTURE.md) | [接口](./INTERFACES.md) | [开发者指南](./DEVELOPER_GUIDE.md)

---

## 核心文档

### [架构](./ARCHITECTURE.md)
系统设计、技术栈、七大能力域与数据流。从这里开始了解系统如何运作。

### [接口](./INTERFACES.md)
Git 多平台门面、BlogRepository 统一接口、AI 会话与工具系统、主要服务的公开契约。

### [开发者指南](./DEVELOPER_GUIDE.md)
环境搭建、构建、代码质量、编码规范与常见开发任务。贡献者必读。

---

## 核心概念

理解这些领域概念有助于导航代码库：

| 概念 | 描述 |
|------|------|
| [GitProvider](./专有概念/GitProvider.md) | 平台适配层：GitHub/GitLab/Gitee/Bitbucket 统一抽象 |
| [SiteIdentity](./专有概念/SiteIdentity.md) | 站点统一身份：静态仓库与动态 CMS 的抽象 |
| [AiSession](./专有概念/AiSession.md) | AI 会话：7 类场景的 System Prompt 与上下文管理 |
| [ToolSystem](./专有概念/ToolSystem.md) | 工具系统：内置工具 / Skill / MCP 的注册与执行闭环 |

---

## 入门指南

### 项目新人？

1. **[架构](./ARCHITECTURE.md)** — 了解全局
2. **[核心概念](#核心概念)** — 学习领域术语
3. **[开发者指南](./DEVELOPER_GUIDE.md)** — 搭建环境
4. **[接口](./INTERFACES.md)** — 探索公开 API

### 想要新增功能？

1. **[开发者指南](./DEVELOPER_GUIDE.md#常见任务)** — 按既有模式扩展
2. **[编码规范](./DEVELOPER_GUIDE.md#编码规范)** — 遵循项目约定

---

## 快速参考

### 命令

```bash
flutter pub get          # 安装依赖
flutter analyze          # 静态分析（须 0 error / 0 warning）
flutter build apk --debug# Android 调试 APK
```

### 重要文件

| 文件 | 目的 |
|------|------|
| `lib/main.dart` | 全平台入口 + 核心状态 |
| `lib/desktop/desktop_main.dart` | 桌面端入口 |
| `lib/desktop/desktop_shell.dart` | 桌面主界面 |
| `lib/services/github_service.dart` | Git 多平台门面 |
| `lib/core/site_manager.dart` | 静态/动态站点工厂中枢 |
| `pubspec.yaml` | 依赖与版本 |
| `.monkeycode/docs/code-splitting-guide.md` | 既有代码拆分方法论 |
