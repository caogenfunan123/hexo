import '../tools/tool_entity.dart';

/// 工具能力地图：把当前会话实际可用的工具按业务域分组，
/// 生成精简的清单文本注入 System Prompt。
///
/// 目的：让模型开局就掌握全局工具能力（不必先探测 list_tools 再规划），
/// 在规划阶段就能正确选型与组合工具，减少盲目探测的无效轮次。
///
/// 说明：只接收"已通过会话边界过滤"的工具列表（调用方负责过滤），
/// 本生成器不重复做权限判断。

/// 内置工具 → 业务域分组
const Map<String, String> _builtinDomain = {
  'web_search': '信息检索',
  'web_fetch': '信息检索',
  'file_read': '仓库文件',
  'file_write': '仓库文件',
  'file_delete': '仓库文件',
  'list_dir': '仓库文件',
  'create_dir': '仓库文件',
  'list_posts': '仓库文件',
  'git_clone': '仓库文件',
  'git_snapshot': '版本与回滚',
  'git_rollback': '版本与回滚',
  'list_posts2': '版本与回滚',
  'list_templates': '文章模板',
  'read_template': '文章模板',
  'update_template': '文章模板',
  'create_skill': '技能管理',
  'update_skill': '技能管理',
  'delete_skill': '技能管理',
  'list_skills': '技能管理',
  'read_app_config': '应用配置',
  'update_app_config': '应用配置',
  'create_site': '建站部署',
  'create_repo': '建站部署',
  'write_welcome_post': '建站部署',
  'poll_site_build': '建站部署',
  'trigger_cf_deploy': '建站部署',
  'rollback_site': '建站部署',
  'register_site': '建站部署',
  'verify_site': '建站部署',
};

/// 域展示顺序（未列出的域按字典序追加）
const List<String> _domainOrder = [
  '信息检索',
  '仓库文件',
  '文章模板',
  '版本与回滚',
  '建站部署',
  '技能管理',
  '应用配置',
  '其他工具',
];

/// 生成工具能力地图文本。
/// [tools]：会话边界过滤后实际可用的工具列表。
String buildToolCatalogPrompt(List<ToolEntity> tools) {
  if (tools.isEmpty) return '';

  final grouped = <String, List<ToolEntity>>{};
  for (final t in tools) {
    if (t.id == 'list_tools') continue; // 元工具不进入地图
    final domain = t.type == ToolType.builtin
        ? (_builtinDomain[t.id] ?? '其他工具')
        : (t.type == ToolType.skill ? '自定义技能' : 'MCP 工具');
    grouped.putIfAbsent(domain, () => []).add(t);
  }
  if (grouped.isEmpty) return '';

  final domains = <String>[
    ..._domainOrder,
    ...grouped.keys.where((d) => !_domainOrder.contains(d)),
  ];

  final buf = StringBuffer('\n=====工具能力地图（当前会话可用）=====\n');
  buf.writeln(
    '以下是本会话已授权的全部工具（均已直接可用，含完整参数定义）。'
    '规划任务时直接从能力地图选型并调用，需要核对参数名时再速查 list_tools。',
  );
  for (final domain in domains) {
    final list = grouped[domain];
    if (list == null || list.isEmpty) continue;
    buf.writeln('\n[$domain]');
    for (final t in list) {
      buf.writeln('- ${t.id}：${_shortDesc(t)}');
    }
  }
  buf.writeln('\n=====工具地图结束=====\n');
  return buf.toString();
}

/// 生成单行工具说明：名称 + 截断描述 + 必填参数。
String _shortDesc(ToolEntity t) {
  final name = t.name.isNotEmpty ? '${t.name}，' : '';
  final desc = t.description.trim();
  final brief = desc.isNotEmpty
      ? (desc.length <= 64 ? desc : '${desc.substring(0, 64)}…')
      : '';
  final required = t.parameters
      .where((p) => p.required)
      .map((p) => p.name)
      .toList();
  final reqText = required.isNotEmpty ? '（必填：${required.join('/')}）' : '';
  return '$name$brief$reqText';
}
