import '../../core/ai/ai_session_manager.dart';

/// Agent 任务类型注册表：统一 AI 大脑的任务分类。
///
/// 各独立场景屏（文章/页面/主题/模板/巡检/应用设计）在
/// 工作台接管后降级为「任务模板」，由 [AgentTaskType] 注册表统一驱动。
enum AgentTaskType {
  general('general', '通用任务', AiSessionType.article, '文章/通用任务'),
  article('article', '文章创作', AiSessionType.article, 'AI 博文创作'),
  page('page', '页面创作', AiSessionType.page, 'AI 页面创作'),
  theme('theme', '主题开发', AiSessionType.theme, 'AI 主题开发'),
  themeMigration(
      'themeMigration', '主题迁移', AiSessionType.themeMigration, 'AI 主题迁移'),
  audit('audit', '站点巡检', AiSessionType.audit, 'AI 站点巡检'),
  appDesign(
      'appDesign', '应用设计', AiSessionType.appDesign, 'AI 应用 UI 设计'),
  template('template', '模板配置', AiSessionType.template, '文章模板配置');

  final String key;
  final String label;
  final AiSessionType sessionType;
  final String description;

  const AgentTaskType(
    this.key,
    this.label,
    this.sessionType,
    this.description,
  );

  static AgentTaskType fromKey(String? key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return AgentTaskType.general;
  }

  /// 注册表：类型 → 新任务时的初始提示词
  String get starterPrompt {
    switch (this) {
      case AgentTaskType.article:
        return '请开始创作一篇新文章，先描述主题，我会提供内容。';
      case AgentTaskType.page:
        return '请开始创建新页面，告诉我页面的用途与内容。';
      case AgentTaskType.theme:
        return '请开始主题开发，告诉我想要的风格或需要修改的方面。';
      case AgentTaskType.themeMigration:
        return '请描述要迁移的主题与目标框架。';
      case AgentTaskType.audit:
        return '请对当前站点进行巡检，检查构建、链接、内容质量。';
      case AgentTaskType.appDesign:
        return '请开始应用 UI 设计，描述应用类型与风格。';
      case AgentTaskType.template:
        return '请开始配置文章模板或博客框架。';
      case AgentTaskType.general:
        return '请描述你的任务目标，我来规划并执行。';
    }
  }
}
