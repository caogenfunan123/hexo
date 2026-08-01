# Hexo 博客写作与管理 App

Flutter 跨平台 Hexo 博客编辑器，支持 Markdown 写作、GitHub 发布、AI 辅助、自动保存、WebDAV 同步。

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
