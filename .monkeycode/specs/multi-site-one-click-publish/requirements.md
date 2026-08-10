# 一键发布到多静态站（每站独立模板 + 发布前预览对比）

## Introduction

用户在 Hexo Flutter App 中管理多个静态博客仓库（每个仓库独立的 GitHub Token、框架与目录）。
当前 `StaticBlogBatchPublishService` 已支持将一篇文章批量写入所有（或选定的）静态仓库，
但存在两个缺口：

1. **模板缺口**：批量发布仅按框架硬编码转换 frontmatter（`_toXxx` 方法），
   未使用每个仓库在 `RepoConfig.defaultPostTemplateId` 中绑定的独立自定义模板，
   也未复用单站发布链路的 `TemplateResolver` / `Article.toMarkdownWithFrontMatterForRepo`。
2. **确认缺口**：批量发布直接写入 GitHub，无「发布前预览 + 差异对比」，
   用户无法确认每个站点将生成的文件内容与变更范围。

本功能补齐这两个缺口，使「一键发布同一篇文章到所有已登录静态网站」具备
「每站独立模板渲染」与「发布前预览/差异对比确认」能力。

## Glossary

- **System**：Hexo Flutter App 的静态博客批量发布子系统。
- **已登录站点**：`RepoConfig.token` 非空且通过 GitHub `/user` 校验成功的静态仓库。
- **每站独立默认模板**：`TemplateResolver.resolvePostTemplate(repo, allTemplates)`
  按「仓库绑定模板 > 框架内置模板 > 首个可用模板」优先级解析出的 `TemplateItem`。
- **发布预览**：批量发布前，为每个目标站点生成「将写入的文件完整内容 + 目标路径 + 相对远端差异」的只读视图。
- **差异对比**：目标文件已存在于远程时，计算本地新内容与远端旧内容的行级差异。

## Requirements

### Requirement 1：每站独立默认模板渲染

**User Story:** AS 博主，I want 批量发布时每个站点使用各自配置的默认模板，so that 不同站点的 frontmatter 与正文格式符合该站约定。

#### Acceptance Criteria

1. WHEN 批量发布启动，THEN 系统 SHALL 对每个目标站点调用 `TemplateResolver.resolvePostTemplate(repo, allTemplates)` 解析该站默认模板。
2. WHEN 站点解析出绑定模板，THEN 系统 SHALL 以该模板渲染 frontmatter 与正文，SHALL NOT 使用框架硬编码转换。
3. WHEN 站点未绑定模板，THEN 系统 SHALL 按既有逻辑回退到框架内置模板并渲染。
4. WHEN 文章包含自定义模板 `templateId`，THEN 该模板 SHALL 优先于站点默认模板生效。
5. WHEN 渲染完成，THEN 生成的 Markdown 内容 SHALL 与单站发布 `upsertArticle` 使用同一渲染入口，保证两链路输出一致。

### Requirement 2：发布前预览与差异对比

**User Story:** AS 博主，I want 在真正写入前查看每个站点将生成的文件内容与差异，so that 避免误发布或格式错误。

#### Acceptance Criteria

1. WHEN 用户点击「一键发布」，THEN 系统 SHALL 先进入预览阶段，SHALL NOT 直接写入任何仓库。
2. WHEN 预览生成，THEN 系统 SHALL 对每个站点展示目标路径、将写入的文件完整内容与文件命名规则结果。
3. WHEN 目标文件在远程已存在，THEN 系统 SHALL 拉取远程内容并计算行级差异（新增/删除/修改行），以新增为主视图展示。
4. WHEN 目标文件在远程不存在，THEN 系统 SHALL 标记为「新建文件」并展示完整内容。
5. WHEN 用户点击「确认发布」，THEN 系统 SHALL 才执行批量写入；用户取消时 SHALL NOT 写入任何仓库。

### Requirement 3：已登录站点自动纳入目标

**User Story:** AS 博主，I want 一键发布默认覆盖所有已登录站点，so that 无需手动逐个勾选。

#### Acceptance Criteria

1. WHEN 用户未选择站点进入一键发布，THEN 系统 SHALL 默认将全部 token 校验通过的静态仓库纳入目标。
2. WHEN 目标站点 token 缺失或校验失败，THEN 系统 SHALL 在预览中标记为「未登录/跳过」并给出原因。
3. WHEN 用户手动勾选站点，THEN 系统 SHALL 仅发布勾选站点，且仅含已登录站点。

### Requirement 4：分站点结果与失败隔离

**User Story:** AS 博主，I want 每个站点发布结果独立呈现，so that 单站失败不影响其他站点。

#### Acceptance Criteria

1. WHEN 任一站点发布失败，THEN 系统 SHALL 记录该站失败原因并继续处理其余站点。
2. WHEN 全部处理完成，THEN 系统 SHALL 展示各站点成功/失败、目标路径与远程 SHA 汇总。
3. WHEN 所有站点失败，THEN 系统 SHALL 提示整体失败且 SHALL NOT 报告成功。
