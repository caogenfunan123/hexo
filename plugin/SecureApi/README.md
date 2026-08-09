# SecureApi - Typecho 小程序 API 插件（增强版）

> 适用于 **Typecho 1.2.1 / 1.3.0**，兼容 **PHP 8.0+**。
>
> 本版本在官方 SecureApi 只读接口的基础上，新增**文章发布 / 更新 / 删除 / 媒体上传**写接口，
> 供 **Hexo 博客写作与管理 App** 直接向 Typecho 站点发布文章。

## 与官方版差异

| 能力 | 官方 SecureApi | 本增强版 |
|------|---------------|---------|
| 读取接口（getPosts/getWebInfo 等） | ✅ | ✅ |
| 文章发布 createPost | ❌ | ✅ |
| 文章更新 updatePost | ❌ | ✅ |
| 文章删除 deletePost | ❌ | ✅ |
| 媒体上传 uploadMedia | ❌ | ✅ |
| 请求方法 | GET | GET + POST |

> 官方版只有读取接口，因此 App 能「连接成功」却「无法发布文章」。
> 安装本增强版后即可正常发布。

## 下载地址

- 仓库：https://gitee.com/nice_ch/typecho-plugin （官方版，只读）
- 增强版：随 Hexo App 仓库提供，目录为 `plugin/SecureApi/`

## 安装

1. 下载本插件，将 `SecureApi` 文件夹放入 Typecho 的 `usr/plugins/` 目录下：

   ```text
   usr/plugins/SecureApi/
   ├── Plugin.php   # 插件主文件
   ├── Action.php   # 接口处理类
   └── README.md    # 本说明文档
   ```

2. 登录 Typecho 后台，进入 **控制台 → 插件管理**
3. 找到 **SecureApi** 插件，点击 **激活**
4. 进入 **插件设置** 页：
   - 将 **API开关** 设置为 **开启**
   - 复制或修改 **API 密钥**（32 位随机密钥，作为调用令牌）
5. 保存设置，即可通过 API 访问

## 基础信息

- **基础 URL**（未开启地址重写时）：
  ```
  https://你的域名/index.php/api
  ```
  开启地址重写（伪静态）后为：
  ```
  https://你的域名/api
  ```
- **认证方式**：GET 参数 `token` 或请求头 `X-API-Key`
- **统一响应**：
  ```json
  { "success": true, "data": { ... } }
  { "success": false, "error": { "message": "错误描述", "code": 403 } }
  ```

## 读取接口（GET）

| 动作 | 说明 | 关键参数 |
|------|------|---------|
| getPosts | 文章列表 | page, limit, status(publish/draft/all) |
| getCategories | 分类树 | 无 |
| getPages | 独立页面 | 无 |
| getWebInfo | 站点信息 | 无 |
| getCategoryPosts | 分类下文章 | category, page, pageSize |
| search | 搜索 | keyword, page, pageSize |
| getArticleContent | 文章详情 | cid |
| getAllTags | 全部标签 | 无 |
| articleAgree | 点赞/取消 | cid, type(agree/cancel) |

请求示例：

```text
GET https://你的域名/index.php/api?action=getWebInfo&token=你的密钥
GET https://你的域名/index.php/api?action=getPosts&page=1&limit=10&token=你的密钥
```

## 写接口（POST，表单参数）

> 参数可通过 `application/x-www-form-urlencoded` 表单体或 GET 查询串传递；
> `token` 与 `action` 建议放在查询串中。

### 1. 创建 / 发布文章 createPost

| 参数 | 类型 | 必填 | 说明 |
|------|------|:----:|------|
| title | string | ✅ | 文章标题 |
| text | string | ✅ | 正文（Markdown 或 HTML） |
| slug | string | - | 缩略名，默认由标题生成 |
| status | string | - | publish/draft/hidden/private/waiting，默认 publish |
| tags | string | - | 标签，多个用英文逗号分隔 |
| category | string | - | 分类，多个用英文逗号分隔 |
| created | string | - | 创建时间（时间戳或 Y-m-d H:i:s） |

```bash
curl -X POST "https://你的域名/index.php/api?action=createPost&token=你的密钥" \
  -d "title=Hello" \
  -d "text=# 标题\n\n正文内容" \
  -d "status=publish" \
  -d "tags=生活,随笔"
```

返回：

```json
{ "success": true, "data": { "id": 12, "cid": 12, "title": "Hello", "slug": "hello", "status": "publish", "permalink": "https://你的域名/archives/12.html", "created": "2026-08-08 12:00:00", "modified": "2026-08-08 12:00:00" } }
```

### 2. 更新文章 updatePost

| 参数 | 类型 | 必填 | 说明 |
|------|------|:----:|------|
| cid | int | ✅ | 文章 ID |
| title / text / slug / status | string | - | 提供即修改 |
| tags / category | string | - | 提供即全量替换 |

```bash
curl -X POST "https://你的域名/index.php/api?action=updatePost&token=你的密钥" \
  -d "cid=12" -d "title=新标题" -d "status=draft"
```

### 3. 删除文章 deletePost

| 参数 | 类型 | 必填 | 说明 |
|------|------|:----:|------|
| cid | int | ✅ | 文章 ID |

```bash
curl -X POST "https://你的域名/index.php/api?action=deletePost&token=你的密钥" -d "cid=12"
```

### 4. 上传媒体 uploadMedia

| 参数 | 类型 | 必填 | 说明 |
|------|------|:----:|------|
| file | file | ✅ | multipart 文件字段，保存到 usr/uploads/ |

```bash
curl -X POST "https://你的域名/index.php/api?action=uploadMedia&token=你的密钥" \
  -F "file=@/path/to/image.jpg"
```

返回：

```json
{ "success": true, "data": { "id": 0, "url": "https://你的域名/usr/uploads/2026/08/xxx.jpg", "name": "image.jpg", "size": 12345 } }
```

## 在 Hexo 博客管理 App 中配置

1. 站点类型选择 **Typecho**
2. **站点 URL** 填写博客根地址，如 `https://你的域名`
3. **API 端点**：留空自动探测（优先 `/index.php/api`，兼容 `/api`）；
   也可手动填写 `/index.php/api`
4. **Token** 粘贴插件设置页的 **API 密钥**
5. 点击「测试连接」，成功后可发布 / 更新 / 删除文章

## 安全机制

请求依次经过：API 开关检查 → 密钥有效性检查 → 密钥验证 → 放行。
写入接口同样受密钥保护，请勿泄露密钥。

## 许可证

Apache License 2.0

## 作者

笨小猪 - Gitee：https://gitee.com/nice_ch/typecho-plugin
