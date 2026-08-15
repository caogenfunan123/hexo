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

  /// 校验令牌 scope（账号连接步预校验，早失败）。
  /// 返回缺失 scope 列表；为空表示通过。
  Future<List<String>> verifyScopes(WizardRequest req) async {
    try {
      final result = req.gitProvider == GitProviderType.gitlab
          ? await _gitlab.verifyScopes(req.gitToken)
          : await _github.verifyScopes(req.gitToken);
      final missing = result['missing'];
      return missing is List
          ? missing.map((e) => e.toString()).toList()
          : const <String>[];
    } catch (e) {
      return ['账号校验失败: $e'];
    }
  }

  /// 读取账号计划（GitHub 免费账号判定）。免费账号私有仓库不能启用 Pages。
  Future<String> getGithubPlan(String token) async {
    try {
      final result = await _github.verifyScopes(token);
      return result['plan']?.toString() ?? '';
    } catch (_) {
      return '';
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
      final siteUrl = await _pollGithubBuild(req.gitToken, owner, req.repoName);

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
      debugPrint('GitHub 建站失败，触发回滚: $e');
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
      final siteUrl = await _pollGitlabBuild(
          req.gitToken, projectId, username, req.repoName);

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
      debugPrint('GitLab 建站失败，触发回滚: $e');
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
        // 60s 未检测到项目：保留仓库，提示用户继续
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
      // 模式二已检测到项目后失败：保留仓库，仅清理可清理项
      final cleanupPlan = plan.copyWith(userInvestedInWeb: plan.cfProjectCreated);
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

  /// 轮询 GitHub Actions run，返回站点 URL；超时返回空串（不抛异常，站点保留待回填）。
  Future<String> _pollGithubBuild(
      String token, String owner, String name) async {
    final deadline = DateTime.now().add(buildPollTimeout);
    const interval = Duration(seconds: 10);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      try {
        final run = await _github.getActionsRun(token, owner, name);
        if (run == null) continue;
        final status = run['status']?.toString() ?? '';
        if (status == 'completed') {
          final conclusion = run['conclusion']?.toString() ?? '';
          if (conclusion == 'success') {
            return 'https://$owner.github.io/$name/';
          }
          // 构建失败：保留站点，返回空 siteUrl 待回填
          debugPrint('GitHub Actions 构建失败: $conclusion');
          return '';
        }
      } catch (e) {
        debugPrint('GitHub Actions 轮询异常: $e');
      }
    }
    return '';
  }

  /// 轮询 GitLab pipeline，返回站点 URL；超时返回空串。
  Future<String> _pollGitlabBuild(
      String token, String projectId, String username, String projectName) async {
    final deadline = DateTime.now().add(buildPollTimeout);
    const interval = Duration(seconds: 10);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      try {
        final pipeline = await _gitlab.getPipeline(token, projectId);
        if (pipeline == null) continue;
        final status = pipeline['status']?.toString() ?? '';
        if (status == 'success') {
          return 'https://$username.gitlab.io/$projectName/';
        }
        if (status == 'failed' || status == 'canceled') {
          debugPrint('GitLab Pipeline 构建失败: $status');
          return '';
        }
      } catch (e) {
        debugPrint('GitLab Pipeline 轮询异常: $e');
      }
    }
    return '';
  }

  Future<void> _triggerHook(String hook) async {
    // 复用既有部署钩子触发逻辑
    await GitHubService.triggerCloudflareDeploy(hook);
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
