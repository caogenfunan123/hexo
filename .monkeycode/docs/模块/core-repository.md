# core/repository（博客仓库适配层）

将"静态博客仓库"与"动态 CMS"统一为 `BlogRepository` 接口，让编辑器、同步、AI 工具以一致方式读写任何博客后端。

## 结构

```
repository/
├── blog_repository.dart          # 统一抽象接口
├── static_blog_repository.dart   # 静态博客（Hexo/Hugo/Jekyll…）只读适配
├── wordpress_adapter.dart        # WordPress REST API（含 Gutenberg HTML 转换）
├── ghost_adapter.dart            # Ghost Admin API（HS256 JWT、Mobiledoc）
├── typecho_adapter.dart          # Typecho SecureApi 插件
├── typecho_restful_adapter.dart  # Typecho Restful 插件
├── typecho_fastapi_adapter.dart  # Typecho FastApi 插件（只读）
└── js_challenge_guard.dart       # slowAES JS 反爬挑战处理
```

## 关键文件

| 文件 | 目的 |
|------|------|
| `blog_repository.dart` | 统一接口与领域异常定义 |
| `wordpress_adapter.dart` | `_markdownToGutenbergHtml` Markdown → Gutenberg 块转换 |
| `ghost_adapter.dart` | Admin API Key 签发 5 分钟 JWT 自动刷新 |
| `js_challenge_guard.dart` | 解密 `__test` cookie 绕过反爬 |

## 依赖

**本模块依赖**: `services/`（Git 门面）、`models/`（BlogSiteConfig）
**依赖本模块的**: `core/site_manager.dart`（工厂）、`screens/`、`services/sync_service.dart`、`core/tools/remote_cms_tools.dart`

## 规范

- 新适配器必须 `implements BlogRepository`
- 只读接口（FastApi）写操作抛 `BlogRepositoryException`
- 写操作语义：`createPost` / `updatePost` / `deletePost` / `uploadMedia` 返回值与既有实现一致
- 防反爬可复用 `JsChallengeHttp`
