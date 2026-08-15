import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/blog_framework.dart';
import '../models/git_provider.dart';
import '../models/repo_config.dart';
import '../models/wizard_models.dart';
import 'cloudflare_pages_provider.dart';
import 'git_providers.dart';
import 'github_service.dart';
import 'rollback_manager.dart';
import 'site_scaffold_builder.dart';

/// 一键建站编排服务
///
/// 唯一编排者：模式一（GitHub Pages / GitLab Pages）按
/// 「建仓 → 骨架+CI → 启用 Pages → 首文 → 轮询构建」顺序执行；
/// 模式二（Cloudflare Pages）按
/// 「建仓 → 骨架 → 引导网页 → 检测衔接 → 拉 Hook → 首文 → 触发 Hook」顺序执行。
///
/// 任一步抛异常即触发 [RollbackManager] 逆序清理（模式二用户已投入网页操作后不删仓库）。
/// 结果中的 [WizardResult.repoConfig] 由调用方接入站点持久化链路。
class SiteWizardService {
  SiteWizardService({
    this.buildPollTimeout = wizardBuildPollTimeout,
    this.cfPollTimeout = wizardCfPollTimeout,
  });

  static const _github = GitHubProvider();
  static const _gitlab = GitLabProvider();
  static const _cf = CloudflarePagesProvider();
  static const _builder = SiteScaffoldBuilder();
  static const _rollback = RollbackManager();

  /// 首次构建轮询上限（默认 10 分钟）
  static const Duration wizardBuildPollTimeout = Duration(minutes: 10);

  /// 模式二衔接轮询上限（60 秒）
  static const Duration wizardCfPollTimeout = Duration(seconds: 60);

  final Duration buildPollTimeout;
  final Duration cfPollTimeout;

  /// 取消回调：由宿主（AiChatPanel 取消按钮）设置。返回 true 表示用户已取消，
  /// 长轮询（构建轮询 / 模式二衔接轮询）据此及时中止。
  bool Function()? _isCancelled;
  bool Function()? get isCancelled => _isCancelled;
  set isCancelled(bool Function()? cb) => _isCancelled = cb;

  /// 执行建站。成功返回结果；失败抛异常（已触发回滚清理）。
  Future<WizardResult> run(WizardRequest req) async {
    switch (req.mode) {
      case WizardMode.one:
        if (req.gitProvider == GitProviderType.gitlab) {
          return _runGitLabPages(req);
        }
        return _runGitHubPages(req);
      case WizardMode.two:
        return _runCloudflarePages(req);
    }
  }

  /// 是否因用户取消而中断。取消异常在构建/衔接轮询中抛出。
  /// 判定同时参考异常消息与取消回调，避免取消后继续执行重操作。
  bool _isCancelException(Object e) {
    if (_isCancelled != null && _isCancelled!()) return true;
    return e.toString().contains('操作已被用户取消');
  }

  // ────────────────────────────────────────────────
  // 分步建站：供 AI 细粒度工具断点续跑
  // 步骤不自动回滚（失败交由调用方决定重试或显式 rollbackSite）
  // ────────────────────────────────────────────────

  /// 步骤 1：建仓库 + 初始化 main 分支 + 写入骨架与 CI。
  /// 返回步骤上下文供后续步骤使用；失败抛异常（不自动回滚）。
  Future<SiteStepContext> createRepo(WizardRequest req) async {
    final owner = req.gitProvider == GitProviderType.gitlab
        ? await _getGitLabUsername(req.gitToken)
        : await _getGitHubOwner(req.gitToken);

    if (req.gitProvider == GitProviderType.gitlab) {
      final project = await _gitlab.createProject(
          req.gitToken, req.repoName, req.repoPrivate);
      final rawId = project['id'];
      final projectId =
          rawId is num ? rawId.toInt().toString() : req.repoName;
      final defaultBranch =
          project['default_branch']?.toString() ?? 'main';
      await _gitlab.initDefaultBranch(req.gitToken, projectId, defaultBranch);
      final skeleton = _builder.build(
        req.mode,
        GitProviderType.gitlab,
        frameworkId: req.frameworkId,
        siteTitle: req.siteTitle,
      );
      await _writeSkeleton(req, skeleton, owner: owner);
      if (req.mode == WizardMode.one) {
        await _gitlab.enablePages(req.gitToken, projectId);
      }
      return SiteStepContext(
        mode: req.mode,
        gitProvider: GitProviderType.gitlab,
        gitToken: req.gitToken,
        cfApiToken: req.cfApiToken,
        cfAccountId: req.cfAccountId,
        repoName: req.repoName,
        repoOwner: owner,
        projectId: projectId,
        frameworkId: req.frameworkId,
        siteTitle: req.siteTitle,
      );
    }

    // GitHub
    await _github.createRepository(
        req.gitToken, req.repoName, req.repoPrivate);
    await _github.initDefaultBranch(req.gitToken, owner, req.repoName);
    final skeleton = _builder.build(
      req.mode,
      GitProviderType.github,
      frameworkId: req.frameworkId,
      siteTitle: req.siteTitle,
    );
    await _writeSkeleton(req, skeleton, owner: owner);
    if (req.mode == WizardMode.one) {
      await _github.enablePages(req.gitToken, owner, req.repoName);
    }
    return SiteStepContext(
      mode: req.mode,
      gitProvider: GitProviderType.github,
      gitToken: req.gitToken,
      cfApiToken: req.cfApiToken,
      cfAccountId: req.cfAccountId,
      repoName: req.repoName,
      repoOwner: owner,
      frameworkId: req.frameworkId,
      siteTitle: req.siteTitle,
    );
  }

  /// 步骤 2：启用 Pages（模式一）。幂等：对 GitHub/GitLab 均安全。
  Future<void> enablePages(SiteStepContext ctx) async {
    if (ctx.gitProvider == GitProviderType.gitlab) {
      await _gitlab.enablePages(ctx.gitToken, ctx.projectId);
    } else {
      await _github.enablePages(
          ctx.gitToken, ctx.repoOwner, ctx.repoName);
    }
  }

  /// 步骤 3：写入欢迎文章。返回远程路径。
  Future<String> writeWelcomePost(SiteStepContext ctx) async {
    final req = WizardRequest(
      mode: ctx.mode,
      gitProvider: ctx.gitProvider,
      gitToken: ctx.gitToken,
      cfApiToken: ctx.cfApiToken,
      cfAccountId: ctx.cfAccountId,
      repoName: ctx.repoName,
      frameworkId: ctx.frameworkId,
      siteTitle: ctx.siteTitle,
    );
    return _writeWelcomePost(req, owner: ctx.repoOwner);
  }

  /// 步骤 4：等待首次构建完成，返回站点 URL（超时返回空串，站点保留待回填）。
  /// 模式一：轮询 GitHub Actions / GitLab Pipeline；
  /// 模式二：等待 Cloudflare 同名项目出现并拉取 Deploy Hook（返回 hook）。
  /// 返回 (siteUrl, deployHook)；deployHook 模式二返回、模式一为空。
  Future<(String, String)> waitForBuild(SiteStepContext ctx) async {
    if (ctx.mode == WizardMode.two) {
      final hook = await _cf.waitForProjectWithHook(
        ctx.cfApiToken,
        ctx.cfAccountId,
        projectName: ctx.repoName,
        maxAttempts: cfPollTimeout.inSeconds,
        intervalMs: 1000,
      );
      if (hook == null || hook.isEmpty) {
        throw Exception(
            '未检测到 Cloudflare Pages 项目，请确认已在控制台创建名为 ${ctx.repoName} 的项目');
      }
      return ('https://${ctx.repoName}.pages.dev', hook);
    }
    if (ctx.gitProvider == GitProviderType.gitlab) {
      final (url, failed) = await _pollGitlabBuild(
          ctx.gitToken, ctx.projectId, ctx.repoOwner, ctx.repoName);
      if (failed) {
        throw Exception('GitLab Pipeline 构建失败，请检查仓库 CI 配置');
      }
      return (url, '');
    }
    final (url, failed) =
        await _pollGithubBuild(ctx.gitToken, ctx.repoOwner, ctx.repoName);
    if (failed) {
      throw Exception('GitHub Actions 构建失败，请检查仓库工作流配置');
    }
    return (url, '');
  }

  /// 步骤 5：触发 Cloudflare 部署（模式二收尾）。
  Future<void> triggerCfDeploy(String hook) async {
    if (hook.isEmpty) return;
    await _triggerHook(hook);
  }

  /// 步骤 6：组装最终站点结果。
  WizardResult finalize(
    SiteStepContext ctx, {
    required String siteUrl,
    required List<String> deployHooks,
    required String welcomePostPath,
  }) {
    final req = WizardRequest(
      mode: ctx.mode,
      gitProvider: ctx.gitProvider,
      gitToken: ctx.gitToken,
      cfApiToken: ctx.cfApiToken,
      cfAccountId: ctx.cfAccountId,
      repoName: ctx.repoName,
      frameworkId: ctx.frameworkId,
      siteTitle: ctx.siteTitle,
    );
    return WizardResult(
      repoConfig: _buildRepoConfig(
        req,
        owner: ctx.repoOwner,
        siteUrl: siteUrl,
        deployHooks: deployHooks,
      ),
      siteProjectName: ctx.repoName,
      siteUrl: siteUrl,
      welcomePostPath: welcomePostPath,
    );
  }

  /// 显式回滚：清理分步建站已创建的远程资源，返回未清理成功的资源描述列表。
  Future<List<String>> rollbackSite(RollbackPlan plan) {
    return _rollback.rollback(plan);
  }

  /// 校验令牌 scope（账号连接步预校验，早失败）。
  /// 返回缺失 scope 列表；为空表示通过。
  Future<List<String>> verifyScopes(WizardRequest req) async {
    try {
      final result = req.gitProvider == GitProviderType.gitlab
          ? await _gitlab.verifyScopes(req.gitToken)
          : await _github.verifyScopes(req.gitToken);
      final missing = result['missing'];
      final list = missing is List
          ? missing.map((e) => e.toString()).toList()
          : <String>[];
      // GitHub 免费账号 + 私有仓库 + 模式一：无法启用 Pages，提前失败给明确提示
      if (list.isEmpty &&
          req.gitProvider == GitProviderType.github &&
          req.repoPrivate &&
          req.mode == WizardMode.one) {
        final plan = result['plan']?.toString() ?? '';
        if (plan == 'free') {
          list.add('免费 GitHub 账号的私有仓库无法启用 Pages，请将仓库改为公开');
        }
      }
      return list;
    } catch (e) {
      return ['账号校验失败: $e'];
    }
  }

  // ────────────────────────────────────────────────
  // 模式一：GitHub Pages
  // ────────────────────────────────────────────────

  Future<WizardResult> _runGitHubPages(WizardRequest req) async {
    final owner = await _getGitHubOwner(req.gitToken);
    var plan = RollbackPlan(
      repoOwner: owner,
      repoName: req.repoName,
      gitProvider: GitProviderType.github,
      gitToken: req.gitToken,
    );

    try {
      // 1. 建仓
      await _github.createRepository(
          req.gitToken, req.repoName, req.repoPrivate);
      plan = plan.copyWith(gitRepoCreated: true);

      // 2. 规整 main 分支
      await _github.initDefaultBranch(req.gitToken, owner, req.repoName);

      // 3. 骨架 + CI 写入
      final skeleton = _builder.build(
        WizardMode.one,
        GitProviderType.github,
        frameworkId: req.frameworkId,
        siteTitle: req.siteTitle,
      );
      await _writeSkeleton(req, skeleton, owner: owner);

      // 4. 启用 Pages（source = GitHub Actions）
      await _github.enablePages(req.gitToken, owner, req.repoName);
      plan = plan.copyWith(pagesEnabled: true);

      // 5. 欢迎文章
      var welcomePath = '';
      if (!req.skipWelcomePost) {
        welcomePath = await _writeWelcomePost(req, owner: owner);
      }

      // 6. 轮询 Actions 构建
      final (siteUrl, buildFailed) =
          await _pollGithubBuild(req.gitToken, owner, req.repoName);
      if (buildFailed) {
        // 构建失败：保留仓库与骨架（不回滚），抛明确信息供上层提示。
        // 复用 userInvestedInWeb 语义（=true 时 RollbackManager 跳过仓库删除）。
        plan = plan.copyWith(userInvestedInWeb: true);
        throw Exception('GitHub Actions 构建失败，仓库已创建并保留，请检查工作流配置后重试');
      }

      return WizardResult(
        repoConfig: _buildRepoConfig(
          req,
          owner: owner,
          siteUrl: siteUrl,
          deployHooks: const [],
        ),
        siteProjectName: req.repoName,
        siteUrl: siteUrl,
        welcomePostPath: welcomePath,
      );
    } catch (e) {
      debugPrint('GitHub 建站失败: $e');
      // 用户取消：保留已建仓库，不执行回滚（用户可手动修复后继续）
      if (_isCancelException(e)) {
        plan = plan.copyWith(userInvestedInWeb: true);
      }
      await _rollback.rollback(plan);
      rethrow;
    }
  }

  // ────────────────────────────────────────────────
  // 模式一：GitLab Pages
  // ────────────────────────────────────────────────

  Future<WizardResult> _runGitLabPages(WizardRequest req) async {
    final username = await _getGitLabUsername(req.gitToken);
    var plan = RollbackPlan(
      repoOwner: username,
      repoName: req.repoName,
      gitProvider: GitProviderType.gitlab,
      gitToken: req.gitToken,
    );

    try {
      // 1. 建项目
      final project = await _gitlab.createProject(
          req.gitToken, req.repoName, req.repoPrivate);
      plan = plan.copyWith(gitRepoCreated: true);
      final rawId = project['id'];
      final projectId =
          rawId is num ? rawId.toInt().toString() : req.repoName;
      final defaultBranch =
          project['default_branch']?.toString() ?? 'main';

      // 2. 规整 main 分支
      await _gitlab.initDefaultBranch(
          req.gitToken, projectId, defaultBranch);

      // 3. 骨架 + CI 写入
      final skeleton = _builder.build(
        WizardMode.one,
        GitProviderType.gitlab,
        frameworkId: req.frameworkId,
        siteTitle: req.siteTitle,
      );
      await _writeSkeleton(req, skeleton, owner: username);

      // 4. 启用 Pages
      await _gitlab.enablePages(req.gitToken, projectId);
      plan = plan.copyWith(pagesEnabled: true);

      // 5. 欢迎文章
      var welcomePath = '';
      if (!req.skipWelcomePost) {
        welcomePath = await _writeWelcomePost(req, owner: username);
      }

      // 6. 轮询 Pipeline 构建
      final (siteUrl, buildFailed) = await _pollGitlabBuild(
          req.gitToken, projectId, username, req.repoName);
      if (buildFailed) {
        // 构建失败：保留仓库（不回滚），抛明确信息
        plan = plan.copyWith(userInvestedInWeb: true);
        throw Exception('GitLab Pipeline 构建失败，仓库已创建并保留，请检查 CI 配置后重试');
      }

      return WizardResult(
        repoConfig: _buildRepoConfig(
          req,
          owner: username,
          siteUrl: siteUrl,
          deployHooks: const [],
        ),
        siteProjectName: req.repoName,
        siteUrl: siteUrl,
        welcomePostPath: welcomePath,
      );
    } catch (e) {
      debugPrint('GitLab 建站失败: $e');
      // 用户取消：保留已建仓库，不执行回滚
      if (_isCancelException(e)) {
        plan = plan.copyWith(userInvestedInWeb: true);
      }
      await _rollback.rollback(plan);
      rethrow;
    }
  }

  // ────────────────────────────────────────────────
  // 模式二：Cloudflare Pages
  // ────────────────────────────────────────────────

  Future<WizardResult> _runCloudflarePages(WizardRequest req) async {
    final owner = await _getGitHubOwner(req.gitToken);
    var plan = RollbackPlan(
      repoOwner: owner,
      repoName: req.repoName,
      gitProvider: GitProviderType.github,
      gitToken: req.gitToken,
      cfApiToken: req.cfApiToken,
      cfAccountId: req.cfAccountId,
    );

    try {
      // 1. 建仓
      await _github.createRepository(
          req.gitToken, req.repoName, req.repoPrivate);
      plan = plan.copyWith(gitRepoCreated: true);

      // 2. 规整 main 分支
      await _github.initDefaultBranch(req.gitToken, owner, req.repoName);

      // 3. 骨架写入（无 CI）
      final skeleton = _builder.build(
        WizardMode.two,
        GitProviderType.github,
        frameworkId: req.frameworkId,
        siteTitle: req.siteTitle,
      );
      await _writeSkeleton(req, skeleton, owner: owner);

      // 4. 引导网页 → 检测衔接 → 拉 Deploy Hook
      // 调用方负责展示「在 Cloudflare 控制台创建 Pages 项目」引导文案，
      // 此处阻塞轮询检测用户是否已在控制台创建同名项目。
      final hook = await _cf.waitForProjectWithHook(
        req.cfApiToken,
        req.cfAccountId,
        projectName: req.repoName,
        maxAttempts: cfPollTimeout.inSeconds,
        intervalMs: 1000,
      );

      if (hook == null) {
        // 60s 未检测到项目：用户已被引导去控制台操作，保留仓库。
        // 先标记 userInvestedInWeb，catch 据此跳过仓库回滚。
        plan = plan.copyWith(userInvestedInWeb: true);
        throw Exception(
            '未检测到 Cloudflare Pages 项目，请确认已在控制台创建名为 ${req.repoName} 的项目');
      }
      plan = plan.copyWith(cfProjectCreated: true);

      // 5. 欢迎文章
      var welcomePath = '';
      if (!req.skipWelcomePost) {
        welcomePath = await _writeWelcomePost(req, owner: owner);
      }

      // 6. 触发 Hook 部署
      await _triggerHook(hook);

      // 站点 URL：CF 默认域名占位，待构建完成后由回填机制刷新
      final siteUrl = 'https://${req.repoName}.pages.dev';

      return WizardResult(
        repoConfig: _buildRepoConfig(
          req,
          owner: owner,
          siteUrl: siteUrl,
          deployHooks: [hook],
        ),
        siteProjectName: req.repoName,
        siteUrl: siteUrl,
        welcomePostPath: welcomePath,
      );
    } catch (e) {
      debugPrint('Cloudflare 建站失败: $e');
      // 用户取消：保留仓库与 CF 项目，不执行回滚（用户可手动继续）
      final keepRepo = _isCancelException(e) || plan.cfProjectCreated;
      final cleanupPlan = plan.copyWith(userInvestedInWeb: keepRepo);
      await _rollback.rollback(cleanupPlan);
      rethrow;
    }
  }

  // ────────────────────────────────────────────────
  // 骨架写入 / 欢迎文章
  // ────────────────────────────────────────────────

  Future<void> _writeSkeleton(
    WizardRequest req,
    List<SkeletonFile> skeleton, {
    String owner = '',
  }) async {
    final repo = _skeletonRepo(req, owner: owner);
    final files = skeleton
        .map((f) => (path: f.path, bytes: _utf8(f.content)))
        .toList();

    if (req.gitProvider == GitProviderType.gitlab) {
      // GitLab 无 writeBatch，逐文件写入
      for (final f in files) {
        await _gitlab.writeFile(repo, f.path, f.bytes,
            message: 'feat: 初始化站点骨架');
      }
      return;
    }

    await _github.writeBatch(repo, files,
        message: 'feat: 初始化站点骨架', authorName: 'Hexo Blog Manager');
  }

  Future<String> _writeWelcomePost(WizardRequest req, {String owner = ''}) async {
    final (path, content) = _builder.buildWelcomePost(
      frameworkId: req.frameworkId,
      siteTitle: req.siteTitle,
    );
    final repo = _skeletonRepo(req, owner: owner);
    if (req.gitProvider == GitProviderType.gitlab) {
      await _gitlab.writeFile(repo, path, _utf8(content),
          message: 'docs: 欢迎文章');
    } else {
      await _github.writeFile(repo, path, _utf8(content),
          message: 'docs: 欢迎文章');
    }
    return path;
  }

  /// 构造用于写入骨架的临时 RepoConfig（branch 固定 main）。
  RepoConfig _skeletonRepo(WizardRequest req, {String owner = ''}) {
    final framework = BlogFramework.byId(req.frameworkId);
    return RepoConfig(
      id: 'wizard_${req.repoName}',
      name: req.repoName,
      owner: owner,
      repo: req.repoName,
      branch: 'main',
      postsPath: framework?.defaultPostsPath ?? 'source/_posts',
      pagesPath: framework?.defaultPagesPath ?? 'source',
      frameworkId: req.frameworkId,
      token: req.gitToken,
      provider: req.gitProvider,
    );
  }

  RepoConfig _buildRepoConfig(
    WizardRequest req, {
    required String owner,
    required String siteUrl,
    required List<String> deployHooks,
  }) {
    final framework = BlogFramework.byId(req.frameworkId);
    return RepoConfig(
      id: 'repo_${req.repoName}',
      name: req.siteTitle.isEmpty ? req.repoName : req.siteTitle,
      owner: owner,
      repo: req.repoName,
      branch: 'main',
      postsPath: framework?.defaultPostsPath ?? 'source/_posts',
      pagesPath: framework?.defaultPagesPath ?? 'source',
      frameworkId: req.frameworkId,
      siteUrl: siteUrl,
      siteProjectName: req.repoName,
      deployHooks: deployHooks,
      token: req.gitToken,
      defaultPostTemplateId:
          RepoConfig.defaultPostTemplateForFramework(req.frameworkId),
      defaultPageTemplateId:
          RepoConfig.defaultPageTemplateForFramework(req.frameworkId),
      provider: req.gitProvider,
    );
  }

  // ────────────────────────────────────────────────
  // 构建轮询
  // ────────────────────────────────────────────────

  /// 轮询 GitHub Actions run。返回 (url, failed)：
  /// url 为站点地址（成功）/空串（超时未完成）；failed 表示构建明确失败。
  Future<(String, bool)> _pollGithubBuild(
      String token, String owner, String name) async {
    final deadline = DateTime.now().add(buildPollTimeout);
    const interval = Duration(seconds: 10);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      // 用户取消：中止轮询，避免后台静默建站
      if (_isCancelled != null && _isCancelled!()) {
        throw Exception('操作已被用户取消');
      }
      try {
        final run = await _github.getActionsRun(token, owner, name);
        if (run == null) continue;
        final status = run['status']?.toString() ?? '';
        if (status == 'completed') {
          final conclusion = run['conclusion']?.toString() ?? '';
          // 骨架 commit 触发 R1，欢迎文章 commit 触发 R2 并取消 R1。
          // 轮询期间可能先看到被取消的 R1，跳过继续等最新 run。
          if (conclusion == 'cancelled' ||
              conclusion == 'skipped' ||
              conclusion == 'action_required') {
            continue;
          }
          if (conclusion == 'success') {
            return ('https://$owner.github.io/$name/', false);
          }
          // 构建失败：区分于超时，failed=true
          debugPrint('GitHub Actions 构建失败: $conclusion');
          return ('', true);
        }
      } catch (e) {
        debugPrint('GitHub Actions 轮询异常: $e');
      }
    }
    return ('', false);
  }

  /// 轮询 GitLab pipeline，返回 (url, failed)。
  Future<(String, bool)> _pollGitlabBuild(
      String token, String projectId, String username, String projectName) async {
    final deadline = DateTime.now().add(buildPollTimeout);
    const interval = Duration(seconds: 10);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      if (_isCancelled != null && _isCancelled!()) {
        throw Exception('操作已被用户取消');
      }
      try {
        final pipeline = await _gitlab.getPipeline(token, projectId);
        if (pipeline == null) continue;
        final status = pipeline['status']?.toString() ?? '';
        if (status == 'success') {
          return ('https://$username.gitlab.io/$projectName/', false);
        }
        if (status == 'canceled' || status == 'skipped') {
          // 旧 pipeline 被新提交取消，继续等待最新 pipeline
          continue;
        }
        if (status == 'failed') {
          debugPrint('GitLab Pipeline 构建失败: $status');
          return ('', true);
        }
      } catch (e) {
        debugPrint('GitLab Pipeline 轮询异常: $e');
      }
    }
    return ('', false);
  }

  Future<void> _triggerHook(String hook) async {
    // 复用既有部署钩子触发逻辑；失败视为部署未触发，上抛避免假成功
    final ok = await GitHubService.triggerCloudflareDeploy(hook);
    if (!ok) throw Exception('触发 Cloudflare 部署失败（Deploy Hook 无效或不可达）');
  }

  // ────────────────────────────────────────────────
  // 辅助
  // ────────────────────────────────────────────────

  Future<String> _getGitHubOwner(String token) async {
    final account = await _github.getUser(token);
    if (account.login.isEmpty) throw Exception('无法识别 GitHub 账号');
    return account.login;
  }

  Future<String> _getGitLabUsername(String token) async {
    final account = await _gitlab.getUser(token);
    if (account.login.isEmpty) throw Exception('无法识别 GitLab 账号');
    return account.login;
  }

  static List<int> _utf8(String s) => utf8.encode(s);
}
