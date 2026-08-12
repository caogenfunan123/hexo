# 拓墨 接口文档

拓墨是 Flutter 客户端应用，其"接口"体现为内部服务层与仓库适配层的公开契约。本文档面向集成与扩展开发者，描述核心抽象接口与主要服务签名。

## Git 多平台层

### `GitProviderType` 枚举（`lib/models/git_provider.dart`）

```dart
enum GitProviderType { github, gitlab, gitee, bitbucket }
```

扩展 `GitProviderTypeX` 提供 `label`（中文名）、`key`（字符串键）、`fromKey`（反查）。`GitAccount` 承载 `token` / `username`。

### `GitProviderAdapter`（`lib/services/git_provider_adapter.dart`）

统一抽象接口，四平台实现 `GitHubProvider` / `GitLabProvider` / `GiteeProvider` / `BitbucketProvider`：

| 方法 | 语义 |
|------|------|
| `type` | 平台类型 |
| `apiBase` | 平台 API 根地址 |
| `getUser(token)` | 校验 token 并返回账号信息 |
| `request(...)` | 统一 JSON 请求 |
| `listContents(repo, path)` | 列出目录/文件 |
| `readFile(repo, path, ref)` | 读取文件 |
| `readFileAtRef(...)` | 指定提交/分支读取 |
| `writeFile(repo, path, content, message, sha)` | 写入/更新文件 |
| `deleteFile(repo, path, message, sha)` | 删除文件 |
| `listCommits(repo, path, page)` | 提交历史 |
| `latestCommitDate(repo, path)` | 最近提交时间 |
| `rawUrl(repo, path, ref)` | 原始内容 URL |

### `GitHubService`（门面，`lib/services/github_service.dart`）

保留类名与全部历史方法签名；`static adapterFor(GitProviderType)` 按 `repo.provider` 分发。新增平台无关方法：
- `uploadBinary({required repo, required path, required bytes, required message, GitProviderType? provider, ...})`
- `getUser({required token, GitProviderType? provider, ...})`
- `verifyToken({required token, GitProviderType? provider, ...})`

## 博客仓库层

### `BlogRepository`（`lib/core/repository/blog_repository.dart`）

静态博客（Git 仓库）与动态 CMS（WordPress/Ghost/Typecho）统一接口：

```dart
abstract class BlogRepository {
  Future<ConnectionResult> testConnection();
  Future<List<BlogPost>> getPosts({paging, filters});
  Future<BlogPost?> getPostById(id);
  Future<BlogPost> createPost(blogPost);
  Future<BlogPost> updatePost(blogPost);
  Future<bool> deletePost(id);
  Future<MediaUploadResult> uploadMedia(...);
  Future<String> getPostContent(...);
  void dispose();
  bool get isStatic;
}
```

**实现**：`StaticBlogRepository`、`WordPressAdapter`、`GhostAdapter`、`TypechoAdapter`、`TypechoRestfulAdapter`、`TypechoFastApiAdapter`（只读，写操作抛异常）。

**工厂**：`SiteManager.getAdapter()` / `currentAdapter`，按 `BlogSiteConfig` 类型创建。

## AI 层

### `AiService`（`lib/services/ai_service.dart`）

统一 AI 入口，主要方法：`complete`、`completeWithToolsStreaming`、`listModels`、`polish`、`continueWrite`、`summarize`、`generateOutline`、`generateTitle`、`translate`、`audit`、`chat`。

### `AiSessionType` 枚举（`lib/core/ai/ai_session_manager.dart`）

7 类会话：`article` / `page` / `theme` / `themeMigration` / `audit` / `appDesign` / `template`。`AiSessionManager.getSystemPrompt(type)` 组装"全局内核 Prompt + 场景 Prompt + 动态上下文"。

### `AiRequestDispatcher`（`lib/core/ai/ai_request_dispatcher.dart`）

- `dispatchStream()` / `dispatch()` / `dispatchWithTools()` / `singleRequest()`
- 失败自动切换备选模型；非流式工具调用循环最多 12 轮；火山方舟 400 降级
- 回调：`onModelSwitched` / `onToolsExecuted` / `onToolConfirm`

## 工具系统

### `ToolEntity`（`lib/core/tools/tool_entity.dart`）

统一工具模型：`ToolType`（builtin/skill/mcp）、`ToolScope`（global/site）、`ToolSource`（user/ai）、风险等级。`toOpenAiFunction()` 生成函数签名。

### `ToolExecutor`（`lib/core/tools/tool_executor.dart`）

`execute()` / `executeAll()`：builtin → `BuiltinTools`、skill → 激活提示词、mcp → JSON-RPC `tools/call`。高风险操作前确认门。`formatToolResultsForAi()` 将结果格式化为 `role:tool` 消息。

### 工具清单

- **内置 21 个**（`BuiltinTools.all`）：`webSearch`（Bing/DuckDuckGo/Baidu/Startpage）、`webFetch`、`fileRead`/`fileWrite`/`fileDelete`、`listDir`、`gitSnapshot`/`gitRollback`/`gitClone`、`readAppConfig`/`updateAppConfig`、`createSkill`/`updateSkill`/`deleteSkill`/`listSkills`、`listTemplates`/`readTemplate`/`updateTemplate`、`listPosts`、`createDir`
- **CMS 16 个**（`RemoteCmsTools.all`）：`wp_*` / `ghost_*` / `typecho_*` 的增改删查、连接测试、媒体上传

### MCP

`McpServerManager`（`lib/core/tools/mcp_server.dart`）：`addServer` / `updateServer` / `removeServer` / `syncAllTools`（JSON-RPC `tools/list` 拉取并注册）。

## 数据同步

### `SyncBackend`（`lib/services/cloud_sync_service.dart`）

- `GitHubSyncBackend` — GitHub 私有仓库同步
- `WebDavSyncBackend` — WebDAV 网盘同步
- 公共：`pushAll` / `pullAll` / `listRemote`

### `SyncService`（`lib/services/sync_service.dart`）

本地/远程文件映射状态机：`localOnly` / `remoteOnly` / `localNewer` / `remoteNewer` / `conflict` / `inSync`。方法：`sync` / `push` / `pull` / `resolveConflict`。

### P2P（`lib/services/p2p_sync_service.dart`）

mDNS 局域网设备发现 + 增量同步 + 配对握手：`startServer` / `discoverPeers` / `sendEntries`。

## 内容处理

### `FrontMatterService`（`lib/services/frontmatter_service.dart`）

`parse` / `update` / `validate`（YAML/TOML 读写与校验）。

### `MarkdownDiff`（`lib/core/diff/markdown_diff.dart`）

`diffText(old, new)` → `LineDiffResult`（`addedCount` / `removedCount` / `hasChanges`）。

### `FullTextSearchService`（`lib/services/full_text_search_service.dart`）

Ripgrep 引擎 + Isolate 隔离执行全文搜索。

### `WordCountUtil`（`lib/core/utils/word_count_util.dart`）

`countWords(text)` → `WordCountResult`（`totalChars` / `pureChars`）。

## 文件抽象

### `AppFileOperator`（`lib/core/file_manager/file_abstract.dart`）

跨平台文件操作接口（Android 分区存储 / 桌面直读）：`readFile` / `writeFile` / `writeBinaryFile` / `deleteFile` / `exists` / `listDirectory` / `createDirectory` / `getAbsolutePath` / `getRootPath` / `exportToUserDirectory` / `readBinaryFile` / `copyFile` / `moveFile` / `getSdkVersion` / `isScopedStorageRequired` / `getInternalStoragePath` / `getExportDirectory`。

**实现**：`AndroidFileOperator`（`lib/platform/android/`）、`DesktopFileOperator`（`lib/platform/desktop/`）。入口：`PlatformResolver.fileOperator`。

## 存储

### `StorageService`（`lib/services/storage_service.dart`）

全局存储目录 `~/.hexo_app`（分类子目录：`MD文章` / `文章长图` / `同步缓存` / `Git博文` / `临时分享文件`）。主要方法：`loadSettings`/`saveSettings`、`loadRepos`/`saveRepos`、`listDrafts`/`saveDraft`/`deleteDraft`、`listSnippets`、`saveSession`/`loadSession`。
