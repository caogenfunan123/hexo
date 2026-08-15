import '../../core/ai/ai_session_manager.dart';
import '../../models/repo_config.dart';
import 'agent_task_type.dart';

/// Agent 上下文收敛：统一携带「任务类型 + 场景上下文」。
///
/// 原各场景屏各自维护的 settings / activeRepo / sessionType / 路径等
/// 参数在此收敛，工作台据此统一构建 System Prompt 并驱动任务。
class AgentContext {
  final AgentTaskType taskType;
  final RepoConfig? activeRepo;
  final String? blogFramework;
  final String? postsPath;
  final String? pagesPath;
  final String? themesPath;
  final String? targetFramework;

  const AgentContext({
    this.taskType = AgentTaskType.general,
    this.activeRepo,
    this.blogFramework,
    this.postsPath,
    this.pagesPath,
    this.themesPath,
    this.targetFramework,
  });

  AiSessionType get sessionType => taskType.sessionType;

  AgentContext copyWith({
    AgentTaskType? taskType,
    RepoConfig? activeRepo,
    String? blogFramework,
    String? postsPath,
    String? pagesPath,
    String? themesPath,
    String? targetFramework,
  }) {
    return AgentContext(
      taskType: taskType ?? this.taskType,
      activeRepo: activeRepo ?? this.activeRepo,
      blogFramework: blogFramework ?? this.blogFramework,
      postsPath: postsPath ?? this.postsPath,
      pagesPath: pagesPath ?? this.pagesPath,
      themesPath: themesPath ?? this.themesPath,
      targetFramework: targetFramework ?? this.targetFramework,
    );
  }

  /// 从仓库推导默认上下文
  factory AgentContext.fromRepo({
    required RepoConfig? repo,
    AgentTaskType taskType = AgentTaskType.general,
  }) {
    return AgentContext(
      taskType: taskType,
      activeRepo: repo,
      blogFramework: repo?.frameworkId,
      postsPath: repo?.postsPath,
      pagesPath: repo?.pagesPath,
      themesPath: repo?.frameworkId == 'hexo' || repo?.frameworkId == 'hugo'
          ? 'themes'
          : null,
    );
  }

  /// 序列化为 JSON（供 AgentTask 持久化断点恢复）
  Map<String, dynamic> toJson() => {
        'taskType': taskType.key,
        'blogFramework': blogFramework,
        'postsPath': postsPath,
        'pagesPath': pagesPath,
        'themesPath': themesPath,
        'targetFramework': targetFramework,
        'activeRepoFullName': activeRepo?.fullName,
      };

  /// 从 JSON 恢复（activeRepo 由工作台按 activeRepoFullName 重建，
  /// 因为 RepoConfig 需引用仓库 token 等敏感字段，不适合整体序列化）
  factory AgentContext.fromJson(Map<String, dynamic> j) {
    return AgentContext(
      taskType: AgentTaskType.fromKey(j['taskType']?.toString()),
      blogFramework: j['blogFramework']?.toString(),
      postsPath: j['postsPath']?.toString(),
      pagesPath: j['pagesPath']?.toString(),
      themesPath: j['themesPath']?.toString(),
      targetFramework: j['targetFramework']?.toString(),
    );
  }

  /// 恢复时携带的仓库 fullName（供工作台从 repos 列表重建 activeRepo）
  String? get activeRepoFullName => activeRepo?.fullName;
}
