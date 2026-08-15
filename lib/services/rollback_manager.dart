import '../models/git_provider.dart';
import '../models/wizard_models.dart';
import 'cloudflare_pages_provider.dart';
import 'git_providers.dart';

/// 回滚管理器
///
/// 逆序执行：站点项目（CF Pages 项目）→ Pages 设置 → Git 仓库。
/// 每步 try-catch，失败项收集到结果列表，由完成页展示并提供手动删除入口。
/// 模式二特例：用户已投入网页操作后失败，不执行仓库回滚。
class RollbackManager {
  const RollbackManager();

  static const _github = GitHubProvider();
  static const _gitlab = GitLabProvider();
  static const _cf = CloudflarePagesProvider();

  /// 执行回滚。返回未删除成功的资源描述列表（空表示全部清理成功）。
  Future<List<String>> rollback(RollbackPlan plan) async {
    final failures = <String>[];

    // 1. 站点项目（CF Pages 项目）逆序先删
    if (plan.cfProjectCreated && plan.cfProjectName.isNotEmpty) {
      try {
        await _cf.deleteProject(
            plan.cfApiToken, plan.cfAccountId, plan.cfProjectName);
      } catch (e) {
        failures.add('Cloudflare Pages 项目 ${plan.cfProjectName} 删除失败: $e');
      }
    }

    // 2. Git 仓库
    // 模式二用户已投入网页操作：保留仓库，由用户手动继续
    if (plan.gitRepoCreated && !plan.userInvestedInWeb) {
      try {
        if (plan.gitProvider == GitProviderType.gitlab) {
          await _gitlab.deleteProject(
            plan.gitToken,
            Uri.encodeComponent('${plan.repoOwner}/${plan.repoName}'),
          );
        } else {
          await _github.deleteRepository(
              plan.gitToken, plan.repoOwner, plan.repoName);
        }
      } catch (e) {
        failures.add('Git ${plan.repoOwner}/${plan.repoName} 删除失败: $e');
      }
    } else if (plan.gitRepoCreated && plan.userInvestedInWeb) {
      // 模式二已投入：保留仓库，仅记录提示（不算失败）
    }

    return failures;
  }

  /// 取消场景：区分「未投入网页操作走完整回滚」与「模式二已投入保留仓库」。
  /// [investedInWeb] 为 true 时按保留仓库处理（仓库不回滚），
  /// 由调用方在完成页提供「手动继续」入口。
  Future<List<String>> cancel(RollbackPlan plan, {required bool investedInWeb}) {
    return rollback(plan.copyWith(userInvestedInWeb: investedInWeb));
  }
}
