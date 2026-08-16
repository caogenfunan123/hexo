/// 会话场景 → 内置工具白名单映射。
///
/// 目的：避免把全部工具定义一次性塞给模型，减少 token 消耗并提升工具选择准确率。
/// 规则：
/// - 未列出的会话类型（null）默认返回全量工具，保持向后兼容。
/// - 仅过滤内置工具（builtin）；MCP 与自定义 Skill 始终保留（用户主动接入/创建的能力）。
/// - 动态 CMS 工具（wp_* / ghost_* / typecho_* / remote_media_upload）由 AiSessionManager
///   的场景 Prompt 约束，不在白名单里硬编码，避免站点类型变更时工具缺失。

import '../tools/tool_entity.dart';
import 'ai_session_manager.dart';

/// 各会话允许使用的内置工具 id 白名单。
/// 空集/未包含的会话 = 不限制（全量）。
const Map<AiSessionType, Set<String>> _sessionToolWhitelist = {
  // 文章创作：读仓库 + 搜索 + 模板 + 写文件
  AiSessionType.article: {
    'web_search',
    'web_fetch',
    'file_read',
    'file_write',
    'file_delete',
    'list_dir',
    'git_snapshot',
    'git_rollback',
    'git_clone',
    'create_dir',
    'list_posts',
    'list_templates',
    'read_template',
    'update_template',
    'list_skills',
    'create_skill',
    'update_skill',
    'delete_skill',
  },
  // 独立页面：与文章类似，页面无日期前缀
  AiSessionType.page: {
    'web_search',
    'web_fetch',
    'file_read',
    'file_write',
    'file_delete',
    'list_dir',
    'git_snapshot',
    'git_rollback',
    'git_clone',
    'create_dir',
    'list_posts',
    'list_templates',
    'read_template',
    'update_template',
    'list_skills',
    'create_skill',
    'update_skill',
    'delete_skill',
  },
  // 主题开发：文件 + Git + 快照回滚 + 搜索
  AiSessionType.theme: {
    'web_search',
    'web_fetch',
    'file_read',
    'file_write',
    'file_delete',
    'list_dir',
    'git_snapshot',
    'git_rollback',
    'git_clone',
    'create_dir',
    'list_skills',
    'create_skill',
    'update_skill',
    'delete_skill',
  },
  // 主题迁移：拉取 + 转换，无回滚
  AiSessionType.themeMigration: {
    'web_search',
    'web_fetch',
    'file_read',
    'file_write',
    'file_delete',
    'list_dir',
    'git_clone',
    'create_dir',
    'git_snapshot',
    'git_rollback',
    'list_skills',
    'create_skill',
    'update_skill',
    'delete_skill',
  },
  // 站点巡检：只读分析，不含写操作
  AiSessionType.audit: {
    'web_search',
    'web_fetch',
    'file_read',
    'list_dir',
    'list_posts',
    'git_snapshot',
    'list_templates',
    'read_template',
    'list_skills',
  },
  // 应用 UI 设计：只暴露设计配置工具
  AiSessionType.appDesign: {
    'read_app_config',
    'update_app_config',
    'list_skills',
    'create_skill',
    'update_skill',
    'delete_skill',
  },
  // 文章模板与框架诊断：模板 + 仓库分析
  AiSessionType.template: {
    'web_search',
    'web_fetch',
    'file_read',
    'file_write',
    'list_dir',
    'list_posts',
    'list_templates',
    'read_template',
    'update_template',
    'git_snapshot',
    'list_skills',
  },
};

/// 按会话场景过滤工具列表。
/// 仅过滤内置工具；MCP 与 Skill 工具始终保留。
List<ToolEntity> filterToolsForSession(
  List<ToolEntity> tools,
  AiSessionType? sessionType,
) {
  if (sessionType == null) return tools;
  final whitelist = _sessionToolWhitelist[sessionType];
  if (whitelist == null) return tools;
  return tools.where((t) {
    if (t.type != ToolType.builtin) return true;
    return whitelist.contains(t.id);
  }).toList();
}
