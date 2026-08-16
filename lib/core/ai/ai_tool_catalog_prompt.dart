import '../tools/tool_entity.dart';

/// 工具分层暴露：把工具分为"核心层"与"扩展层"。
///
/// - 核心层：高频、轻量的工具，直接通过 API tools 数组暴露完整定义，
///   让模型开局就能动手，避免反复探测 list_tools 却不执行任务。
/// - 扩展层：低频或重量级（建站长链路、大文件拉取等）工具，不进 tools
///   数组，仅在系统提示词的能力地图中列出，模型需要时用
///   list_tools(tool_name=...) 单个注入后调用。
///
/// 目的：避免全量暴露 30+ 工具撑爆上下文预算，同时保证高频工具可直接调用。

/// 核心层工具白名单：当前会话最常用、定义轻量的工具。
/// 其余内置工具自动归入扩展层。自定义技能与 MCP 工具按此处理：
/// 全部归入扩展层（由模型按需拉取，避免数量膨胀）。
const Set<String> _coreToolIds = {
  // 信息检索
  'web_search',
  'web_fetch',
  // 仓库文件
  'file_read',
  'file_write',
  'list_dir',
  'create_dir',
  'list_posts',
  // 文章模板
  'list_templates',
  'read_template',
  'update_template',
  // 版本回滚
  'git_snapshot',
  // 技能管理
  'list_skills',
  'create_skill',
  // 应用配置
  'read_app_config',
  'update_app_config',
};

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
  '技能管理',
  '应用配置',
  '建站部署',
  '自定义技能',
  'MCP 工具',
  '其他工具',
];

/// 分层结果
class ToolLayers {
  /// 核心层工具：直接通过 tools 数组暴露完整定义
  final List<ToolEntity> coreTools;
  /// 能力地图文本（含核心/扩展工具速查索引）
  final String catalogPrompt;

  const ToolLayers({required this.coreTools, required this.catalogPrompt});
}

/// 从会话边界过滤后的工具列表计算分层结果。
/// [tools]：filterToolsForSession 之后实际可用的工具。
ToolLayers buildToolLayers(List<ToolEntity> tools) {
  final core = <ToolEntity>[];
  final extended = <ToolEntity>[];
  for (final t in tools) {
    if (t.id == 'list_tools') continue;
    // 核心层：仅内置工具且在白名单内；技能与 MCP 归扩展层
    if (t.type == ToolType.builtin && _coreToolIds.contains(t.id)) {
      core.add(t);
    } else {
      extended.add(t);
    }
  }

  return ToolLayers(
    coreTools: core,
    catalogPrompt: _buildCatalogText(core, extended),
  );
}

/// 生成能力地图文本：核心工具直接可用，扩展工具需 list_tools 拉取。
String _buildCatalogText(List<ToolEntity> core, List<ToolEntity> extended) {
  if (core.isEmpty && extended.isEmpty) return '';

  final buf = StringBuffer('\n=====工具能力地图（当前会话可用）=====\n');
  buf.writeln(
    '工具分两层：\n'
    '- 核心工具：已直接提供完整参数定义，可直接调用（见下方[核心工具]）。\n'
    '- 扩展工具：仅列出速查，调用前先用 list_tools(tool_name="xxx") 注入后再调。\n'
    '规划任务时优先用核心工具；涉及扩展工具时先拉取对应定义再执行。',
  );

  final groupedCore = _groupByDomain(core);
  final groupedExt = _groupByDomain(extended);

  if (groupedCore.isNotEmpty) {
    buf.writeln('\n[核心工具 · 直接可用]');
    _writeGroups(buf, groupedCore);
  }
  if (groupedExt.isNotEmpty) {
    buf.writeln('\n[扩展工具 · 需先拉取]');
    _writeGroups(buf, groupedExt);
  }
  buf.writeln('\n=====工具地图结束=====\n');
  return buf.toString();
}

void _writeGroups(
  StringBuffer buf,
  Map<String, List<ToolEntity>> grouped,
) {
  final domains = <String>[
    ..._domainOrder,
    ...grouped.keys.where((d) => !_domainOrder.contains(d)),
  ];
  for (final domain in domains) {
    final list = grouped[domain];
    if (list == null || list.isEmpty) continue;
    buf.writeln('\n[$domain]');
    for (final t in list) {
      buf.writeln('- ${t.id}：${_shortDesc(t)}');
    }
  }
}

Map<String, List<ToolEntity>> _groupByDomain(List<ToolEntity> tools) {
  final grouped = <String, List<ToolEntity>>{};
  for (final t in tools) {
    final domain = t.type == ToolType.builtin
        ? (_builtinDomain[t.id] ?? '其他工具')
        : (t.type == ToolType.skill ? '自定义技能' : 'MCP 工具');
    grouped.putIfAbsent(domain, () => []).add(t);
  }
  return grouped;
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
