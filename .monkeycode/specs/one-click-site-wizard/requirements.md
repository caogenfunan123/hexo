# 一键建站向导（Git 建仓 + 博客骨架 + 平台发布）

## Introduction

用户在拓墨 App 中仅凭 Git 令牌（可选 Cloudflare API 令牌），从零搭建一个可访问的静态博客站点。
当前软件已具备「向已存在仓库发布文章 + 触发 Deploy Hook」能力（`GitHubProvider.writeBatch`、`triggerCloudflareDeploy`），
但缺少「创建仓库」「初始化博客骨架」「创建站点项目」三个前置环节，
导致用户必须离开 App 手动完成建站。

本功能补齐建站全流程：一个多步向导，在 App 内完成
Git 仓库创建 → 博客骨架文件写入 → 站点项目创建与关联 → 首篇文章发布，
最终返回可访问的站点 URL。

建站成功的产物自动接入现有发布链路：Git 令牌自动注册到登录令牌管理，
新站点自动注册到静态站点管理，写文章界面无需额外配置即可一键发布。

向导提供两种建站模式：

- **模式一（零人工，纯令牌）**：Git 平台内置静态托管引擎。GitHub Pages（GitHub Actions 构建）
  或 GitLab Pages（GitLab CI 构建），仅凭对应平台的令牌即可全程自动化，无需任何网页操作。
- **模式二（半自动，Cloudflare Pages）**：GitHub 建仓推骨架后，需用户在其 Cloudflare 控制台
  网页完成一次「连接 Git 源」操作，App 自动检测项目并衔接后续发布。

建站能力同时作为 AI 工具（`create_site`）提供给 AI 会话，依托已配置的 AI 令牌与工具库调用，
用户可直接对 AI 说"帮我建一个博客站"完成建站。

## Glossary

- **System**：拓墨 App 的一键建站向导子系统。
- **Git 令牌**：Git 平台个人访问令牌。GitHub PAT（`repo` + `workflow` scope）、GitLab PAT（`api` scope）。
- **Cloudflare API 令牌**：Cloudflare API Token（`Account:Pages:Edit` + `Account:Pages:Read` 权限），用于创建 Pages 项目。
- **博客骨架**：静态博客框架运行所需的工程文件（`_config.yml`、`package.json`、`scaffolds/`、主题目录、`.gitignore` 等），
  模式一额外包含 CI 流水线文件（`.github/workflows/deploy.yml` 或 `.gitlab-ci.yml`）。
- **构建机**：各平台提供的远端构建环境（GitHub Actions / GitLab CI / Cloudflare Pages），执行 `npm run build` 或框架原生构建命令。
- **站点项目**：托管平台上的一个站点实体（GitHub Pages 站点、GitLab Pages 站点或 Cloudflare Pages 项目），绑定 Git 源仓库与构建命令。

## Requirements

### Requirement 1：向导入口与步骤导航

**User Story:** AS 博客新手，I want 从设置或新建流程进入建站向导，so that 无需任何命令行知识即可建站。

#### Acceptance Criteria

1. WHEN 用户在移动端或桌面端触发「一键建站」，System SHALL 展示多步向导，步骤为「账号连接 → 站点信息 → 选择模板 → 确认建站 → 完成」。
2. WHEN 移动端与桌面端使用同一建站服务层，System SHALL 共享相同的建站流程与持久化数据。
3. WHEN 用户在任何步骤点击返回，System SHALL 保留该步骤之前已填写且校验通过的数据。
4. IF 向导当前步骤存在未通过校验的必填项，System SHALL 阻止进入下一步并在对应字段旁展示错误提示。

### Requirement 2：账号连接

**User Story:** AS 用户，I want 在向导内输入并验证 Git 令牌与 Cloudflare API 令牌，so that 建站过程完全在 App 内完成。

#### Acceptance Criteria

1. WHEN 用户输入 Git 令牌，System SHALL 通过 GitHub `/user` 接口校验令牌有效性并展示令牌属主账号。
2. WHEN 用户输入 GitHub 令牌，System SHALL 同时校验其 scope 是否包含建站所需权限（`repo` + `workflow`）；IF 缺失任一 scope，System SHALL 明确列出缺失项并引导用户重新生成令牌。
3. WHEN 用户输入 GitLab 令牌，System SHALL 同时校验其 scope 是否包含建站所需权限（`api`）；IF 缺失，System SHALL 提示用户补充。
4. WHEN 用户输入 Cloudflare API 令牌，System SHALL 通过 Cloudflare `GET /user/tokens/verify` 接口校验令牌有效性。
5. IF 任一令牌校验失败，System SHALL 展示失败原因并允许用户重新输入。
6. WHILE 向导进行中，System SHALL 仅将令牌保存在本机安全存储中，并禁止将令牌明文回显到任何日志或网络请求体以外。

### Requirement 3：创建 Git 仓库

**User Story:** AS 用户，I want 向导以指定名称在所选 Git 平台创建公开或私有仓库，so that 博客文件拥有独立托管空间。

#### Acceptance Criteria

1. WHEN 用户选择模式一且平台为 GitHub，System SHALL 调用 GitHub `POST /user/repos` 创建仓库。
2. WHEN 用户选择模式一且平台为 GitLab，System SHALL 调用 GitLab `POST /api/v4/projects` 创建项目。
3. WHEN 用户选择模式二，System SHALL 调用 GitHub `POST /user/repos` 创建仓库。
4. WHEN 用户未修改可见性，System SHALL 将仓库创建为 `private`；WHEN 用户选择公开，System SHALL 将仓库创建为 `public`。
5. IF 向导为模式一且平台为 GitHub，System SHALL 在站点信息步骤提示「GitHub 免费账号的私有仓库无法启用 Pages，若账号为免费版需选择公开仓库」；IF 用户仍选择私有，System SHALL 允许继续建仓，但在启用 Pages 失败时归因到仓库可见性并引导用户改公开。
6. IF 仓库名称已存在或名称非法，System SHALL 展示冲突原因并允许用户改名重试。
7. WHEN 仓库创建成功，System SHALL 记录仓库 `owner/name` 并进入下一步。

### Requirement 4：写入博客骨架

**User Story:** AS 用户，I want 向导将所选框架的完整博客骨架写入新仓库，so that 构建机无需手工准备即可构建出站点。

#### Acceptance Criteria

1. WHEN 新仓库创建成功，System SHALL 通过 Git API 批量写入所选框架的博客骨架文件（`writeBatch`）。
2. WHEN 用户选择 Hexo，System SHALL 至少写入 `_config.yml`、`package.json`（含 `hexo` 与 `hexo-cli` 依赖与 `hexo generate` 构建脚本）、`scaffolds/`、`.gitignore` 与默认主题配置。
3. WHEN 用户选择其他预设框架，System SHALL 写入该框架对应的最小可构建骨架（对应 `BlogFramework.presets`）。
4. WHEN 向导为模式一，System SHALL 额外写入对应平台的 CI 流水线文件（GitHub：`.github/workflows/deploy.yml`；GitLab：`.gitlab-ci.yml`），流水线执行框架构建并部署到平台静态托管。
5. IF 骨架写入过程中任一文件写入失败，System SHALL 回滚本次写入的已提交文件并提示用户重试。

### Requirement 5：创建站点项目（平台分发）

**User Story:** AS 用户，I want 向导自动创建所选托管平台的站点项目并绑定新仓库，so that 每次发布自动构建上线。

#### Acceptance Criteria

1. WHEN 向导为模式一且平台为 GitHub，System SHALL 调用 GitHub `POST /repos/{owner}/{repo}/pages` 启用 GitHub Pages，并配置构建来源为 GitHub Actions。
2. WHEN 向导为模式一且平台为 GitLab，System SHALL 调用 GitLab `PUT /api/v4/projects/{id}/pages` 启用 GitLab Pages，并确认 CI 流水线已声明 `pages` 任务。
3. WHEN 向导为模式二，System SHALL 引导用户在其 Cloudflare 控制台网页完成「连接 Git 源 → 创建 Pages 项目」，随后 System 通过 API 检测项目存在并自动拉取 Deploy Hook。
4. WHEN 创建项目，System SHALL 传递 Git 源仓库连接、目标分支与所选框架的构建命令和输出目录。
5. IF Cloudflare API 令牌缺少 Pages 权限，System SHALL 展示缺失的权限名并引导用户补权。
6. WHEN 站点项目创建成功，System SHALL 记录项目名与默认访问域名。

### Requirement 6：首篇文章发布与站点验证

**User Story:** AS 用户，I want 向导发布一篇欢迎文章并验证站点可访问，so that 建站结果立即可见。

#### Acceptance Criteria

1. WHEN 站点项目创建成功，System SHALL 生成一篇「欢迎使用」示例文章写入 `source/_posts`。
2. WHEN 示例文章提交成功，System SHALL 等待所选平台首次构建完成并轮询获取最新构建状态（GitHub Actions run / GitLab Pipeline / Cloudflare deployment）。
3. IF 首次构建轮询时长超过上限（默认 10 分钟），System SHALL 停止轮询并提示用户「构建仍在进行，可稍后在站点管理查看状态」，同时保留后续自动回填 `siteUrl` 的机制。
4. IF 首次构建失败，System SHALL 展示构建日志摘要并提示用户修复。
5. WHEN 首次构建成功，System SHALL 在完成页展示可访问的站点 URL 并允许用户复制或打开。

### Requirement 7：建站结果自动接入（令牌 + 多仓库 + 一键发布）

**User Story:** AS 用户，I want 建站完成后站点与令牌自动接入现有管理，so that 写文章界面无需额外配置即可一键发布。

#### Acceptance Criteria

1. WHEN 建站流程成功完成，System SHALL 创建对应 `RepoConfig`（含框架、`postsPath`、token、`siteProjectName`、`siteUrl`）并加入静态站点管理。
2. WHEN 建站流程成功完成，System SHALL 将建站使用的 Git 令牌自动注册到登录令牌管理（已存在则跳过），模式二同时保存 Cloudflare API 令牌与账号 ID。
3. WHEN 建站流程成功完成，System SHALL 为新站 `RepoConfig` 绑定框架内置文章模板（`defaultPostTemplateId`），使其进入发布模板解析链。
4. WHEN 后续文章发布到该站点，System SHALL 复用既有发布链路（`publishArticleWithMirrors`）并应用发布模板解析结果。
5. WHEN 用户写文章时选择「一键发布到所有静态博客站点」，System SHALL 将新站纳入批量发布候选集。
6. WHEN 发布完成后，System SHALL 触发所选平台重新构建（模式一由 CI 推送自动触发，模式二触发 Deploy Hook）。
7. WHEN 用户在站点管理中切换新站仓库可见性，System SHALL 调用 GitHub `PATCH /repos/{owner}/{repo}` 同步；IF 为免费账号且从公开切到私有，System SHALL 提示「该变更可能导致 GitHub Pages 停用」。

### Requirement 8：错误处理与幂等

**User Story:** AS 用户，I want 建站中途失败后不产生半成品资源，so that 可以安全地重试。

#### Acceptance Criteria

1. IF 建站任一步骤失败，System SHALL 自动回滚清理本次流程已创建的资源（Git 仓库与站点项目），不留半成品资源。
2. WHEN 自动回滚执行中，System SHALL 按「站点项目 → Git 仓库」的逆序删除资源，并记录每一步结果。
3. IF 自动回滚中删除某资源失败，System SHALL 在结果页明确列出未删除成功的资源及对应删除入口，供用户手动处理。
4. WHEN 用户重试建站，System SHALL 以新的唯一仓库名执行，避免与已存在资源冲突。
5. IF 网络超时或令牌失效，System SHALL 明确区分「令牌问题」「网络问题」「资源冲突」三类错误并分别提示。
6. WHEN 向导为模式二且用户已投入网页操作后失败，System SHALL 保留已创建的仓库并在完成页提供「手动继续」入口，不执行仓库回滚。
7. IF 用户在建站完成前主动取消或关闭向导，且本次已创建资源但未投入网页操作（模式一任意阶段 / 模式二建仓后尚未连接 Git 源），System SHALL 执行与失败相同的自动回滚清理。
8. IF 用户主动取消时模式二已投入网页操作，System SHALL 保留已创建的仓库并在结果页提示「可稍后从站点管理手动继续」，不执行仓库回滚。

### Requirement 9：AI 工具联动

**User Story:** AS 用户，I want 通过 AI 对话直接建站与发布，so that 依托已配置的 AI 令牌与工具库即可完成全流程。

#### Acceptance Criteria

1. WHEN 用户在 AI 会话中请求建站，System SHALL 通过内置工具 `create_site` 调用 `SiteWizardService` 执行建站。
2. WHEN 建站工具执行中，System SHALL 复用用户已配置的 AI 令牌（`activeAiProfile`）与既有工具调用机制（`AiToolManager` / `ToolExecutor`）。
3. WHEN 用户在 AI 会话中请求建站，IF 当前未配置可用 AI 模型（`effectiveAiApiKey` 为空或无有效 `activeAiProfile`），System SHALL 暂停执行并明确提示"请先在 AI 设置中配置模型"，提供跳转 AI 设置入口；用户完成配置后重试。
4. WHEN 建站工具完成，System SHALL 将结果（仓库地址、站点 URL、下一步建议）回传为 AI 可读报告。
5. IF 建站涉及建仓或删除回滚等高风险操作，System SHALL 默认请求用户确认，对齐 `aiConfirmHighRiskTools` 策略。
6. IF AI 建站中途失败或用户取消，System SHALL 复用同一 `RollbackManager` 执行回滚，并将回滚结果（成功/残留资源）作为工具结果回传给 AI。
7. WHEN 建站成功，System SHALL 允许 AI 后续直接触发文章发布到新站。

### Requirement 10：自定义域名绑定引导

**User Story:** AS 用户，I want 建站后获得绑定自定义域名的分步引导，so that 可以替换默认二级域名。

#### Acceptance Criteria

1. WHEN 建站成功，System SHALL 在完成页提供「绑定自定义域名」入口，展示绑定流程概览（域名购买/解析配置/平台绑定三步）。
2. WHEN 用户选择绑定域名，System SHALL 按平台提供分步引导：
   - 模式一 GitHub：引导用户在域名 DNS 服务商添加 CNAME 记录指向 `<user>.github.io`，随后 System 调用 `PUT /repos/{owner}/{repo}/pages` 设置 `cname` 字段并提示等待 HTTPS 生效。
   - 模式一 GitLab：引导用户在 DNS 服务商添加记录，随后在 GitLab Pages 设置中填写域名，System 提示验证 DNS 生效。
   - 模式二 Cloudflare：引导用户在 Cloudflare 控制台 Pages 项目「自定义域」中添加域名并走其自有 DNS 绑定流程。
3. WHEN 引导执行中，System SHALL 对每一步展示「现在你应该看到什么 / 下一步做什么」的对照文案，并标注该步骤需要用户前往哪个控制台。
4. IF 用户尚未购买域名或 DNS 记录指向错误，System SHALL 提示先完成域名解析配置，并给出 CNAME 记录的具体值与目标值。
5. WHEN 域名绑定完成，System SHALL 更新该站点的 `siteUrl` 为自定义域名。

## Out of Scope

- 域名注册购买与付费流程（用户自行完成）。
- 除平台内置绑定之外的自动 DNS 配置（DNS 记录由用户在其域名服务商处配置）。
- 除 Cloudflare Pages 之外的平台（Vercel / Netlify）的托管项目自动创建。
- 主题选择器在线预览。
