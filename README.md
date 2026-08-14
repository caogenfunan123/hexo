# Hexo 博客写作与管理 App

Flutter 跨平台 Hexo 博客编辑器，支持 Markdown 写作、GitHub 发布、AI 辅助、自动保存、WebDAV 同步。

## 项目结构

```
lib/
├── main.dart                  # 入口 + _RootShellState 核心状态类（生命周期/会话/导航）
├── mixins/                    # 按业务域拆分的 State 扩展（Extension + Part 方案）
│   ├── editor_publish_ext.dart    # 发布/上传/保存
│   ├── editor_sync_ext.dart       # 同步/云端
│   ├── settings_dialogs_ext.dart  # 设置/管理弹窗
│   ├── editor_ui_ext.dart         # 编辑页 UI 构建
│   ├── editor_text_ext.dart       # 文本操作/自动保存
│   ├── editor_ai_ext.dart         # AI 功能/对话
│   ├── editor_repo_ext.dart       # 仓库/Token 管理
│   ├── editor_remote_ext.dart     # 远程内容/分享
│   ├── editor_misc_ext.dart       # 杂项工具
│   └── editor_drawer_ext.dart     # 抽屉组件
├── widgets/                   # 独立公开组件（WordCountBadge、EditorMenuGroupTitle 等）
├── theme/                     # 主题控制器（EditorThemeController）
└── ...                        # services / screens / core 等
```

`_RootShellState` 曾为 7425 行巨型类，现已按业务域拆分为 10 个 extension part 文件，`main.dart` 缩减至约 1290 行。完整拆分方法论与新增代码准则见 [代码拆分说明](.monkeycode/docs/code-splitting-guide.md)。

## 下载

[![Build APK](https://github.com/caogenfunan123/hexo/actions/workflows/build.yml/badge.svg)](https://github.com/caogenfunan123/hexo/actions/workflows/build.yml)

最新 APK → [Releases 页面](https://github.com/caogenfunan123/hexo/releases)

## 功能

- Markdown 编辑器（工具栏、图床、AI 润色/续写/摘要/代码/改写）
- 阅读/编辑页面分离，退出弹窗确认
- 自动定时保存草稿快照，APP 重启恢复会话
- GitHub 远程文章管理（发布、删除、回滚）
- 仪表盘统计、RSS 订阅、批量上传
- 主题色、WebDAV 同步、PWA 预览

## 构建

```sh
flutter pub get
flutter build apk --debug
```

APK 输出在 `build/app/outputs/flutter-apk/app-debug.apk`。

## 鸣谢

本项目的架构设计与功能实现深度参考了以下开源项目，在此向各位原作者致敬：

### 本项目直接复刻/深度参考

| 项目 | 说明 | 地址 |
|------|------|------|
| QuickDaily | 悬浮速记窗、任务小部件、阅读小部件、时间戳能力 | [github.com/agarcabin/QuickDaily](https://github.com/agarcabin/QuickDaily) |
| MonkeyCode | AI 工具/模型编排、MCP 服务器管理、健康检查 | [github.com/chaitin/MonkeyCode](https://github.com/chaitin/MonkeyCode) |
| MarkText | 沉浸式写作布局、专注模式、33 主题体系、打字机滚动 | [github.com/marktext/marktext](https://github.com/marktext/marktext) |
| VS Code | MVVM 架构分层、命令面板（Ctrl+Shift+P）、Markdown 语法着色、diff view | [github.com/microsoft/vscode](https://github.com/microsoft/vscode) |
| super_editor | Document / Composer 编辑器架构（数据与交互状态分离） | [github.com/superlistapp/super_editor](https://github.com/superlistapp/super_editor) |
| Zettlr | FrontMatter 解析、FSAL 全文搜索架构 | [github.com/Zettlr/Zettlr](https://github.com/Zettlr/Zettlr) |

### 布局与交互参考

| 项目 | 说明 | 地址 |
|------|------|------|
| PureWriter | 左栏源码编辑 + 右栏实时预览 | [github.com/PureWriter/PureWriter](https://github.com/PureWriter/PureWriter) |
| Notion | 左栏文章平铺内嵌、可折叠列表 | [notion.so](https://www.notion.so/) |
| Obsidian | Vault 工作区隔离思想 | [github.com/obsidianmd/obsidian-releases](https://github.com/obsidianmd/obsidian-releases) |
| Cursor | AI inline edit + 编辑器 diff 交互 | [github.com/getcursor/cursor](https://github.com/getcursor/cursor) |

### 能力依赖参考

| 项目 | 说明 | 地址 |
|------|------|------|
| hexo-mobile | FrontMatter 处理思路（源自 Hexo 生态移动编辑器，仓库已归档，约定见 Hexo） | [github.com/hexojs/hexo](https://github.com/hexojs/hexo) |
| flutter_udp_broadcast | P2P 局域网同步广播（UDP 广播思路参考） | [pub.dev](https://pub.dev/packages?q=udp+broadcast) |
| ripgrep | 全文检索二进制预编译方案 | [github.com/BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep) |
| GitHub REST API | 批量上传支持 Contents API 与 Git Data API（blobs/trees/commits/refs 一次提交），失败自动回退 git CLI | [docs.github.com](https://docs.github.com/en/rest/repos/contents) |

QuickDaily 作者：小子，感谢原作者的开源分享，欢迎前往支持：[作者主页](https://www.coolapk.com/u/400522)

技术交流群：97126959 —— [点击加入群聊](https://qm.qq.com/q/D8qN5eUDh6)
