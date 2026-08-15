import 'git_provider.dart';
import 'repo_config.dart';

/// 一键建站模式
enum WizardMode {
  one, // 模式一：平台 Pages（GitHub Pages / GitLab Pages），CI 自部署
  two; // 模式二：Cloudflare Pages，App 触发 Deploy Hook 部署

  static WizardMode fromKey(Object? key) =>
      key?.toString() == 'two' ? WizardMode.two : WizardMode.one;
}

/// 一键建站请求参数
///
/// 由 AI 工具或降级表单向导组装后交给 [SiteWizardService.run]。
class WizardRequest {
  final WizardMode mode;
  final GitProviderType gitProvider; // github / gitlab
  final String gitToken;
  final String cfApiToken; // 模式二必填，模式一为空
  final String cfAccountId; // 模式二必填，模式一为空
  final String repoName; // 仓库名（同时作为站点项目名）
  final bool repoPrivate; // 默认 private，用户显式选择才改 public
  final String frameworkId; // 博客框架ID
  final String siteTitle; // 站点标题
  final bool skipWelcomePost; // 是否跳过欢迎文章（默认 false）

  const WizardRequest({
    this.mode = WizardMode.one,
    this.gitProvider = GitProviderType.github,
    this.gitToken = '',
    this.cfApiToken = '',
    this.cfAccountId = '',
    this.repoName = '',
    this.repoPrivate = true,
    this.frameworkId = 'hexo',
    this.siteTitle = '',
    this.skipWelcomePost = false,
  });

  WizardRequest copyWith({
    WizardMode? mode,
    GitProviderType? gitProvider,
    String? gitToken,
    String? cfApiToken,
    String? cfAccountId,
    String? repoName,
    bool? repoPrivate,
    String? frameworkId,
    String? siteTitle,
    bool? skipWelcomePost,
  }) {
    return WizardRequest(
      mode: mode ?? this.mode,
      gitProvider: gitProvider ?? this.gitProvider,
      gitToken: gitToken ?? this.gitToken,
      cfApiToken: cfApiToken ?? this.cfApiToken,
      cfAccountId: cfAccountId ?? this.cfAccountId,
      repoName: repoName ?? this.repoName,
      repoPrivate: repoPrivate ?? this.repoPrivate,
      frameworkId: frameworkId ?? this.frameworkId,
      siteTitle: siteTitle ?? this.siteTitle,
      skipWelcomePost: skipWelcomePost ?? this.skipWelcomePost,
    );
  }
}

/// 一键建站结果
class WizardResult {
  final RepoConfig repoConfig; // 新站点 RepoConfig
  final String siteProjectName; // 站点项目名
  final String siteUrl; // 首次构建成功后回填；超时为空待后续回填
  final String welcomePostPath; // 欢迎文章远程路径（跳过首文时为空）

  const WizardResult({
    required this.repoConfig,
    this.siteProjectName = '',
    this.siteUrl = '',
    this.welcomePostPath = '',
  });
}

/// 分步建站上下文：保存「建仓库」步骤完成后的中间状态，
/// 供后续步骤（写欢迎文章 / 轮询构建 / 回滚）断点续跑。
class SiteStepContext {
  final WizardMode mode;
  final GitProviderType gitProvider;
  final String gitToken;
  final String cfApiToken; // 模式二衔接用
  final String cfAccountId;
  final String repoName;
  final String repoOwner; // GitHub login / GitLab username
  final String projectId; // GitLab 项目数字 ID；GitHub 为空
  final String frameworkId;
  final String siteTitle;

  const SiteStepContext({
    required this.mode,
    required this.gitProvider,
    required this.gitToken,
    this.cfApiToken = '',
    this.cfAccountId = '',
    required this.repoName,
    required this.repoOwner,
    this.projectId = '',
    required this.frameworkId,
    this.siteTitle = '',
  });
}

/// 回滚计划：记录已创建的远程资源，供失败/取消时逆序清理
class RollbackPlan {
  final String repoOwner;
  final String repoName;
  final GitProviderType gitProvider;
  final String gitToken;
  final String cfApiToken;
  final String cfAccountId;
  final String cfProjectName; // 模式二已创建的 CF Pages 项目名（可空）
  final bool gitRepoCreated; // Git 仓库是否已创建
  final bool pagesEnabled; // Pages 是否已启用（GitHub/GitLab）
  final bool cfProjectCreated; // CF Pages 项目是否已创建
  final bool userInvestedInWeb; // 模式二用户是否已投入网页操作（为 true 不删仓库）

  const RollbackPlan({
    this.repoOwner = '',
    this.repoName = '',
    this.gitProvider = GitProviderType.github,
    this.gitToken = '',
    this.cfApiToken = '',
    this.cfAccountId = '',
    this.cfProjectName = '',
    this.gitRepoCreated = false,
    this.pagesEnabled = false,
    this.cfProjectCreated = false,
    this.userInvestedInWeb = false,
  });

  RollbackPlan copyWith({
    String? repoOwner,
    String? repoName,
    GitProviderType? gitProvider,
    String? gitToken,
    String? cfApiToken,
    String? cfAccountId,
    String? cfProjectName,
    bool? gitRepoCreated,
    bool? pagesEnabled,
    bool? cfProjectCreated,
    bool? userInvestedInWeb,
  }) {
    return RollbackPlan(
      repoOwner: repoOwner ?? this.repoOwner,
      repoName: repoName ?? this.repoName,
      gitProvider: gitProvider ?? this.gitProvider,
      gitToken: gitToken ?? this.gitToken,
      cfApiToken: cfApiToken ?? this.cfApiToken,
      cfAccountId: cfAccountId ?? this.cfAccountId,
      cfProjectName: cfProjectName ?? this.cfProjectName,
      gitRepoCreated: gitRepoCreated ?? this.gitRepoCreated,
      pagesEnabled: pagesEnabled ?? this.pagesEnabled,
      cfProjectCreated: cfProjectCreated ?? this.cfProjectCreated,
      userInvestedInWeb: userInvestedInWeb ?? this.userInvestedInWeb,
    );
  }
}
