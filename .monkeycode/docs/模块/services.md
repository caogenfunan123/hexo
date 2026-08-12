# services（服务层）

服务层封装跨 UI 与核心层的横切能力：Git 门面、AI 服务、CMS/同步、存储、安全、内容处理。共 42 个文件。

## 结构

```
services/
├── github_service.dart          # Git 多平台门面（全方法按 provider 分发）
├── git_providers.dart           # GitHub/GitLab/Gitee/Bitbucket 适配器实现
├── git_provider_adapter.dart    # 适配器抽象接口
├── git_http.dart                # JSON/form 双模式 HTTP + 路径编码
├── git_service.dart             # 旧版 Contents API 兼容
├── git_models.dart              # GitHubFileItem / GitCommitItem
├── ai_service.dart              # AI 统一入口（complete/polish/audit…）
├── volcengine_adapter.dart      # 火山方舟协议适配
├── usage_tracker.dart           # AI 用量统计
├── cloud_sync_service.dart      # GitHub/WebDAV 云同步后端
├── webdav_service.dart          # WebDAV 协议操作
├── sync_service.dart            # CMS 双向同步状态机
├── p2p_sync_service.dart        # 局域网 P2P 同步
├── p2p_mdns_service.dart        # mDNS 设备发现
├── p2p_incremental_sync.dart    # 增量同步
├── cms_draft_service.dart       # CMS 草稿（SQLite）
├── storage_service.dart         # 全局存储目录 + JSON 持久化
├── session_service.dart         # 会话快照
├── image_service.dart           # 图片压缩/上传/图床路由
├── site_encryption_service.dart # AES-256-GCM 加密
├── site_isolation_service.dart  # 站点隔离
├── version_snapshot_service.dart# 版本快照
├── recycle_bin_service.dart     # 回收站
├── conflict_diff_service.dart   # 冲突 diff
├── frontmatter_service.dart     # FrontMatter 读写/校验
├── html_to_markdown.dart        # HTML → Markdown
├── full_text_search_service.dart# Ripgrep 全文搜索
├── template_service.dart        # 模板管理
├── template_sync_service.dart   # 模板云同步
├── spell_check_service.dart     # 拼写检查
├── rss_service.dart             # RSS 解析
├── taxonomy_cache_service.dart  # 标签/分类缓存
├── log_service.dart             # 操作日志
└── static_blog_batch_publish_service.dart # 静态博客批量发布
```

## 关键文件

| 文件 | 目的 |
|------|------|
| `github_service.dart` | 全部 Git 能力的唯一门面，向后兼容 |
| `git_providers.dart` | 平台差异（认证/编码/结构）核心实现 |
| `storage_service.dart` | 本地数据持久化根 |
| `cloud_sync_service.dart` | 多端数据互通 |

## 依赖

**本模块依赖**: `models/`（配置与实体）、`core/file_manager/`（文件抽象）
**依赖本模块的**: `screens/`、`desktop/`、`core/tools/`、`core/repository/`

## 规范

- 服务类名后缀 `Service`（`SyncService`）或 `Adapter`（`WordPressAdapter`）
- Git 相关服务不得绕过 `GitHubService` 门面直接访问平台细节
- 新服务如跨平台使用文件，一律经 `AppFileOperator`
