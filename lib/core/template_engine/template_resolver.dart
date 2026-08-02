import '../../models/repo_config.dart';
import '../../models/template_item.dart';

/// 模板解析引擎 —— 纯业务逻辑，Android/PC 完全共用
/// 负责仓库 ↔ 模板自动联动、默认模板解析、降级回退
class TemplateResolver {
  /// 解析仓库的文章默认模板
  /// 优先级：仓库绑定的模板 > 框架内置模板 > 第一个可用模板
  static TemplateItem? resolvePostTemplate(
    RepoConfig repo,
    List<TemplateItem> allTemplates,
  ) {
    // 1. 仓库显式绑定的模板
    if (repo.defaultPostTemplateId != null) {
      final bound = _findTemplate(allTemplates, repo.defaultPostTemplateId!);
      if (bound != null && bound.isPost) return bound;
    }

    // 2. 框架内置文章模板
    final builtinId = RepoConfig.defaultPostTemplateForFramework(repo.frameworkId);
    if (builtinId != null) {
      final builtin = _findTemplate(allTemplates, builtinId);
      if (builtin != null && builtin.isPost) return builtin;
    }

    // 3. 回退到第一个可用文章模板
    for (final t in allTemplates) {
      if (t.isPost) return t;
    }
    return null;
  }

  /// 解析仓库的页面默认模板
  static TemplateItem? resolvePageTemplate(
    RepoConfig repo,
    List<TemplateItem> allTemplates,
  ) {
    // 1. 仓库显式绑定的模板
    if (repo.defaultPageTemplateId != null) {
      final bound = _findTemplate(allTemplates, repo.defaultPageTemplateId!);
      if (bound != null && !bound.isPost) return bound;
    }

    // 2. 框架内置页面模板
    final builtinId = RepoConfig.defaultPageTemplateForFramework(repo.frameworkId);
    if (builtinId != null) {
      final builtin = _findTemplate(allTemplates, builtinId);
      if (builtin != null && !builtin.isPost) return builtin;
    }

    // 3. 回退到第一个可用页面模板
    for (final t in allTemplates) {
      if (!t.isPost) return t;
    }
    return null;
  }

  /// 获取仓库文章默认模板 ID（用于显示）
  static String? resolvePostTemplateId(
    RepoConfig repo,
    List<TemplateItem> allTemplates,
  ) {
    return resolvePostTemplate(repo, allTemplates)?.id;
  }

  /// 获取仓库页面默认模板 ID（用于显示）
  static String? resolvePageTemplateId(
    RepoConfig repo,
    List<TemplateItem> allTemplates,
  ) {
    return resolvePageTemplate(repo, allTemplates)?.id;
  }

  /// 框架切换时，计算新的默认模板ID
  static RepoConfig autoBindTemplatesForFramework(
    RepoConfig repo,
    String newFrameworkId,
  ) {
    return repo.copyWith(
      frameworkId: newFrameworkId,
      fileNameRule: FileNameRule.fromFramework(newFrameworkId),
      defaultPostTemplateId: RepoConfig.defaultPostTemplateForFramework(newFrameworkId),
      defaultPageTemplateId: RepoConfig.defaultPageTemplateForFramework(newFrameworkId),
    );
  }

  /// 模板被删除后的降级处理：检查仓库默认模板是否仍存在
  static RepoConfig ensureTemplateFallback(
    RepoConfig repo,
    List<TemplateItem> allTemplates,
  ) {
    String? newPostId = repo.defaultPostTemplateId;
    String? newPageId = repo.defaultPageTemplateId;

    // 检查文章模板
    if (newPostId != null) {
      final found = _findTemplate(allTemplates, newPostId);
      if (found == null || !found.isPost) {
        // 降级到框架内置
        newPostId = RepoConfig.defaultPostTemplateForFramework(repo.frameworkId);
      }
    }

    // 检查页面模板
    if (newPageId != null) {
      final found = _findTemplate(allTemplates, newPageId);
      if (found == null || found.isPost) {
        newPageId = RepoConfig.defaultPageTemplateForFramework(repo.frameworkId);
      }
    }

    if (newPostId == repo.defaultPostTemplateId &&
        newPageId == repo.defaultPageTemplateId) {
      return repo;
    }

    return repo.copyWith(
      defaultPostTemplateId: newPostId,
      defaultPageTemplateId: newPageId,
    );
  }

  /// 查找模板（按 ID）
  static TemplateItem? _findTemplate(List<TemplateItem> templates, String id) {
    for (final t in templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 获取模板显示名称
  static String getTemplateDisplayName(
    String? templateId,
    List<TemplateItem> allTemplates,
  ) {
    if (templateId == null) return '未设置';
    final t = _findTemplate(allTemplates, templateId);
    return t?.name ?? '未找到($templateId)';
  }

  /// 生成仓库默认模板的描述文本
  static String describeRepoDefaults(
    RepoConfig repo,
    List<TemplateItem> allTemplates,
  ) {
    final postName = getTemplateDisplayName(
      resolvePostTemplateId(repo, allTemplates),
      allTemplates,
    );
    final pageName = getTemplateDisplayName(
      resolvePageTemplateId(repo, allTemplates),
      allTemplates,
    );
    final fw = repo.frameworkId;
    return '框架: $fw | 文章模板: $postName | 页面模板: $pageName';
  }
}