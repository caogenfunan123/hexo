import '../../core/ai/ai_session_manager.dart';
import 'agent_context.dart';

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

  /// 注册表：类型 → 新任务时的完整场景模板提示词
  ///
  /// 原独立场景屏（ai_article_chat / ai_theme_chat / ai_audit / ai_app_design /
  /// ai_template_chat）被工作台接管后，其初始引导文案在此统一收敛为任务模板。
  /// 支持占位符：{framework} 博客框架、{postsPath} 文章目录、{pagesPath} 页面目录。
  String starterPrompt([AgentContext? context]) {
    final fw = context?.blogFramework ?? '当前框架';
    final posts = context?.postsPath ?? '未指定';
    final pages = context?.pagesPath ?? '未指定';
    final themes = context?.themesPath ?? 'themes';
    switch (this) {
      case AgentTaskType.article:
        return '欢迎使用 AI 博文创作助手！\n\n我可以直接读取您的博客仓库，分析现有文章的 FrontMatter 格式和写作风格，生成精准匹配的博文内容。\n\n你可以直接告诉我：\n'
            '• 新建文章：标题xxx，内容方向xxx\n'
            '• 分析我的文章模板（自动读取仓库）\n'
            '• 读取文章 [文件名] 查看现有内容\n'
            '• 根据现有文章风格创作\n'
            '• 优化全文、精简文字、补充标签\n'
            '• SEO优化标题与描述\n\n'
            '当前框架：$fw | 博文目录：$posts';
      case AgentTaskType.page:
        return '欢迎使用 AI 页面创作助手！\n\n我可以直接读取您的博客仓库，分析现有页面格式和主题布局，生成精准匹配的页面内容。\n\n你可以直接告诉我：\n'
            '• 创建关于我页面 / 友链页面 / 归档页面\n'
            '• 分析我的页面模板（自动读取仓库）\n'
            '• 读取页面 [文件名] 查看现有内容\n'
            '• 根据现有页面风格创建新页面\n'
            '• 修改页面文案、调整排版布局\n\n'
            '当前框架：$fw | 页面目录：$pages';
      case AgentTaskType.theme:
        return '欢迎使用 AI 主题开发助手！\n\n你可以直接告诉我：\n'
            '• 新建主题 [名称]\n'
            '• 修改文件 [路径]，实现 [功能]\n'
            '• 优化样式、适配暗色模式\n'
            '• 创建主题备份快照\n'
            '• 回滚主题至上一个可用快照\n'
            '• 分析当前代码构建风险\n\n'
            '当前框架：$fw | 主题目录：$themes';
      case AgentTaskType.themeMigration:
        return '欢迎使用 AI 主题迁移助手！\n\n你可以直接告诉我：\n'
            '• 将当前主题迁移到 [目标框架]\n'
            '• 迁移 [主题名称] 到 [目标框架]\n'
            '• 保留原主题的布局与样式配置\n\n'
            '当前框架：$fw | 主题目录：$themes';
      case AgentTaskType.audit:
        return '欢迎使用 AI 站点巡检助手！\n\n你可以直接告诉我：\n'
            '• 开始全面巡检\n'
            '• 检查配置文件语法\n'
            '• 检查文章 FrontMatter 完整性\n'
            '• 检查模板文件闭合标签\n'
            '• 分析目录结构是否规范\n'
            '• 给出优化建议\n\n'
            '当前框架：$fw | 博文目录：$posts | 主题目录：$themes';
      case AgentTaskType.appDesign:
        return '欢迎使用 AI 应用 UI 设计助手！\n\n'
            '我可以帮你调整这个应用本身的界面外观，你可以直接告诉我：\n'
            '• 换成紫色主题\n'
            '• 界面紧凑一点\n'
            '• 圆角大一点，更有圆润感\n'
            '• 字号调大一些\n'
            '• 推荐一个护眼配色方案\n'
            '• 极简风格\n'
            '• 圆润可爱风\n'
            '• 查看当前配置\n'
            '• 重置为默认\n\n'
            '我会先读取当前配置，再给出调整建议并实时应用修改。';
      case AgentTaskType.template:
        return '欢迎使用 AI 模板与博客框架助手！\n\n'
            '我可以读取您绑定的博客仓库代码，诊断「文章发布后博客上不显示」的根因，并直接修复文章模板与博客框架。\n\n'
            '你可以直接告诉我：\n'
            '• 分析为什么我的文章发布后不显示\n'
            '• 查看当前仓库的框架配置和文章 FrontMatter\n'
            '• 修复文章模板以适配 $fw\n'
            '• 修改仓库中的博客框架/主题文件\n'
            '• 按主题要求补全模板字段（cover、layout 等）\n\n'
            '当前框架：$fw | 文章目录：$posts';
      case AgentTaskType.general:
        return '欢迎使用 Agent 任务工作台（通用任务）！\n\n'
            '我可以读取绑定的博客仓库、调用工具执行任务并产出结果。\n\n'
            '你可以直接告诉我：\n'
            '• 分析仓库结构或代码\n'
            '• 生成文章/页面/主题文件\n'
            '• 执行多步骤任务\n\n'
            '当前框架：$fw';
    }
  }
}
