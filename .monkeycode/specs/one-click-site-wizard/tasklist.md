# 一键建站向导 实施计划

对应设计：`design.md`（Components 1-8 / Data Models / Correctness Properties 1-17）

- [ ] 1. 数据模型扩展（Data Models）
  - [ ] 1.1 扩展 `RepoConfig`（lib/models/repo_config.dart）：新增 `siteProjectName`、`siteUrl`、`deployHooks` 字段，含 copyWith / toJson / fromJson（Correctness 7）
  - [ ] 1.2 扩展 `AppSettings`（lib/models/app_settings.dart）：新增 `cfApiToken`、`cfAccountId` 字段及序列化
  - [ ] 1.3 新建 `lib/models/wizard_models.dart`：`WizardRequest`（mode / gitProvider / gitToken / cfApiToken / cfAccountId / repoName / repoPrivate / frameworkId / siteTitle / skipWelcomePost）与 `WizardResult`（repoConfig / siteProjectName / siteUrl / welcomePostPath）
  - [ ] 1.4 新建框架构建映射 `lib/services/framework_build_map.dart`：按 frameworkId 返回 buildCommand 与 buildOutputDirectory（对齐 design 第 4 节映射表，覆盖 hexo/hugo/jekyll/vuepress/gatsby/nextjs/astro/pelican/11ty 及 custom 默认）
  - [ ]* 1.5 为数据模型编写单元测试：RepoConfig/AppSettings 序列化往返、WizardRequest 默认值、框架映射表完整性（9 框架 + custom）

- [ ] 2. GitProvider 建站扩展（Components 2）
  - [ ] 2.1 `GitHubProvider` 新增：`createRepository`、`initDefaultBranch`、`enablePages`（POST /repos/{owner}/{name}/pages, source=Actions）、`getActionsRun`、`deleteRepository`（复用 `request`/`gitHttpRequest`，Requirement 3/5）
  - [ ] 2.2 `GitHubProvider` 新增：`verifyScopes`（解析 `X-OAuth-Scopes` 校验 repo+workflow）、`updateVisibility`（PATCH）、`setCustomDomain`（PUT pages 设 cname）（Requirement 2/7/10）
  - [ ] 2.3 `GitLabProvider` 新增：`createProject`、`initDefaultBranch`、`enablePages`（PUT /api/v4/projects/{id}/pages）、`getPipeline`、`deleteProject`（Requirement 3/5）
  - [ ] 2.4 `GitLabProvider` 新增：`verifyScopes`（校验 api scope）、`setCustomDomain`（Requirement 2/10）
  - [ ]* 2.5 单元测试：注入 mock HTTP 层验证各新方法的 URL/方法/请求体；verifyScopes 对不同 `X-OAuth-Scopes` 响应头判定缺失项

- [ ] 3. CloudflarePagesProvider（Components 3，新增 `lib/services/cloudflare_pages_provider.dart`）
  - [ ] 3.1 实现 `verifyToken`（GET /user/tokens/verify）、`listProjects`（GET /accounts/{id}/pages/projects）、`getProject`、`getDeployment`、`deleteProject`，复用 `gitHttpRequest` 新增 Cloudflare 域名
  - [ ] 3.2 实现模式二衔接逻辑：`listProjects` 轮询到目标仓库名对应项目后，从 `getProject` 详情解析 `deploy_hooks` 数组，返回首个 Deploy Hook URL（Requirement 5 AC 6）
  - [ ]* 3.3 单元测试：listProjects 轮询匹配、deploy_hooks 解析、空列表时返回空并触发错误分支

- [ ] 4. SiteScaffoldBuilder（Components 4，新增 `lib/services/site_scaffold_builder.dart`）
  - [ ] 4.1 实现按 `BlogFramework.presets` 生成骨架文件清单（_config.yml / package.json / scaffolds/ / 主题占位 / .gitignore），front matter 对齐 `postFrontMatter`（Requirement 4）
  - [ ] 4.2 实现 GitHub CI 生成：`.github/workflows/deploy.yml`，按框架类型生成构建步骤（Node 系 setup-node+npm ci；jekyll setup-ruby+bundle；hugo setup-hugo；pelican setup-python），上传产物路径对齐 `buildOutputDirectory`，permissions 含 pages:write/id-token:write（Requirement 4 AC 5-6）
  - [ ] 4.3 实现 GitLab CI 生成：`.gitlab-ci.yml`，按框架类型选择镜像与构建命令，artifacts path 对齐 `buildOutputDirectory`（Requirement 4 AC 5-6）
  - [ ] 4.4 生成「欢迎使用」示例文章（skipWelcomePost 为 false 时），front matter 对齐所选框架（Requirement 6 AC 1-2）
  - [ ]* 4.5 单元测试：9 框架骨架文件清单快照、四类框架 CI 构建步骤差异、产物目录对齐映射表、跳过欢迎文章分支

- [ ] 5. RollbackManager（Components 5，新增 `lib/services/rollback_manager.dart`）
  - [ ] 5.1 实现 `rollback(RollbackPlan)`：按「站点项目 → Git 仓库」逆序执行，每步 try-catch 收集失败项返回（Requirement 8 AC 2-3）
  - [ ] 5.2 实现取消场景复用：`cancel(plan, investedInWeb)` 区分「未投入网页操作走完整回滚」与「模式二已投入保留仓库」（Requirement 8 AC 7-8）
  - [ ]* 5.3 单元测试：注入失败 provider 验证逆序执行与失败项收集、取消两分支

- [ ] 6. SiteWizardService 编排（Components 1，新增 `lib/services/site_wizard_service.dart`）
  - [ ] 6.1 实现 `run(WizardRequest)`：模式一分派（GitHub：建仓→建 main→骨架+CI→启用 Pages→首文→轮询 Actions；GitLab：建项目→骨架+CI→启用 Pages→首文→轮询 Pipeline）；模式二分派（建仓→骨架→引导衔接→检测→拉 Hook→首文→触发 Hook）（Requirement 3-6）
  - [ ] 6.2 实现可见性切换与免费账号判定：GitHub 免费账号基于 `getUser` 的 plan 字段提示 Pages 私有限制；`siteProjectName`/`siteUrl` 记录与回填（Requirement 3 AC 5、6.3、Correctness 14）
  - [ ] 6.3 实现首次构建轮询：上限 `wizardBuildPollTimeout`（默认 10 分钟），超时停止轮询保留站点记录且 `siteUrl` 待回填；成功回填 `siteUrl`（Requirement 6 AC 4-8）
  - [ ] 6.4 实现失败/取消统一入口：任一步异常调 RollbackManager；`skipWelcomePost` 分支跳过首文与首文轮询（Requirement 6 AC 2、8 AC 1-8）
  - [ ] 6.5 实现建站结果自动接入：构造 RepoConfig 并写入站点管理、`_upsertGithubToken` 注册令牌、模式二保存 cfApiToken/cfAccountId/deployHooks，均为幂等（存在则跳过）（Requirement 7、Correctness 7）
  - [ ] 6.6 实现 GitHub Pages 免费限制提示与 Actions 免费额度提示文案（Requirement 3 AC 5、6 AC 5）
  - [ ]* 6.7 单元测试：mock provider 注入成功/失败序列验证编排顺序、回滚触发、skipWelcomePost、轮询超时保留站点记录、接入幂等

- [ ] 7. 检查点：数据层与服务层验证
  - [ ] 7.1 运行 `flutter analyze`（本机 /tmp/opencode/flutter）确保新服务层无编译错误
  - [ ] 7.2 运行单元测试（若环境允许）确认模型、映射表、RollbackManager、SiteWizardService 编排通过；如有疑问请询问用户

- [ ] 8. 入口注册与 UI（Components 6.6）
  - [ ] 8.1 `NavEntries.registry` 与 `SettingsEntries.registry` 新增 `'create_site': FeatureVisibility.shown`（lib/desktop/feature_entries.dart，Requirement 11 AC 7）
  - [ ] 8.2 侧边汉堡栏：`_buildDrawer`（lib/mixins/editor_ui_ext.dart）「创作」分区新增「一键建站」`_drawerAction`，回调 `_startAiSiteWizard()`（Requirement 11 AC 1）
  - [ ] 8.3 设置页：`lib/screens/settings_screen.dart` 新增「一键建站」`ListTile`，调用同一 `_startAiSiteWizard()`（Requirement 11 AC 2）
  - [ ] 8.4 实现 `_startAiSiteWizard()`：校验 `effectiveAiApiKey` 非空，未配置则提示「请先在 AI 设置中配置模型」并跳转 `_showAiModelManager`；已配置则打开 AI 对话并预置建站意图（Requirement 11 AC 3-4）

- [ ] 9. AI 建站工具 `create_site`（Components 8）
  - [ ] 9.1 在 `lib/core/tools/builtin_tools.dart` 注册 `create_site` ToolEntity，description 声明建站能力与所需参数；模型前置校验（effectiveAiApiKey 非空且 activeAiProfile 存在），未配置返回引导提示（Requirement 9 AC 1-3）
  - [ ] 9.2 实现工具执行：组装 WizardRequest 调 `SiteWizardService.run`，结果转 AI 可读报告（仓库地址/站点 URL/下一步建议）；失败/取消回滚结果一并回传（Requirement 9 AC 4、6）
  - [ ] 9.3 高风险操作确认：建仓/删除回滚对齐 `aiConfirmHighRiskTools`，开启前默认请求用户确认（Requirement 9 AC 5）
  - [ ]* 9.4 单元测试：未配置 AI 模型时工具不执行返回引导；配置后返回建站报告；高风险确认分支

- [ ] 10. 检查点：入口与 AI 工具验证
  - [ ] 10.1 运行 `flutter analyze` 确认 UI 与工具注册无编译错误
  - [ ] 10.2 验证 `NavEntries.visibleEntry('create_site', ...)` 简易模式返回 true；如有疑问请询问用户

- [ ] 11. 降级表单向导 UI（Components 6，`lib/screens/site_wizard_screen.dart`）
  - [ ] 11.1 Stepper 分步：模式选择 → 账号连接（含 verifyScopes）→ 站点信息（含仓库名校验）→ 选择模板 → 确认/执行 → 完成；返回保留已填数据（Requirement 1）
  - [ ] 11.2 仓库名实时校验：小写字母/数字/连字符/下划线，不以连字符首尾，1-100 字符（Requirement 3 AC 7）
  - [ ] 11.3 模式二引导页：Cloudflare 控制台连接 Git 的分步对照文案 + 轮询检测（60s 超时提示）；模式一进度页：Actions/Pipeline 轮询展示（Components 6）
  - [ ] 11.4 取消对话框与结果页：未投入回滚 / 已投入保留仓库；失败项手动删除入口；「使用 AI 对话」返回入口（Requirement 8）
  - [ ] 11.5 AI 对话页提供「使用表单向导」降级按钮，切换到本表单（Requirement 11 AC 6）

- [ ] 12. 站点管理扩展（Components 6.3 / 7）
  - [ ] 12.1 站点管理新增「切换可见性」：调 `GitHubProvider.updateVisibility`，免费账号公开→私有提示 Pages 停用风险（Requirement 7 AC 7、design 6.3）
  - [ ] 12.2 站点管理/完成页新增「绑定自定义域名」入口：GitHub（DNS CNAME 引导 + `setCustomDomain`）、GitLab（DNS 引导）、Cloudflare（控制台引导），成功后更新 `siteUrl`（Requirement 10）
  - [ ] 12.3 `siteUrl` 回填：站点管理打开该站点或下次发布成功时重新查询构建状态并回填（Requirement 6 AC 8、Correctness 15）
  - [ ]* 12.4 单元测试：可见性切换提示分支、域名绑定成功更新 siteUrl、回填触发逻辑

- [ ] 13. 检查点：全链路验证
  - [ ] 13.1 运行 `flutter analyze` 确认全模块无编译错误
  - [ ] 13.2 运行既有回归测试（test/ 目录）确认 `publishArticleWithMirrors` 链路不受 RepoConfig 新增字段影响（Test Strategy 回归）
  - [ ] 13.3 总结实施结果与待确认项，如有疑问请询问用户
