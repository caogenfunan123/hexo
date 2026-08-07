/// 工具库仓储：MCP/Skill 持久化、来源标记、站点私有/全局公用作用域过滤
library;

import 'dart:convert';

import 'skill_manager.dart';
import 'tool_entity.dart';
import 'tool_registry.dart';

/// 工具库仓储：管理全部 MCP/Skill 的持久化与作用域
class ToolBoxRepository {
  final SkillManager _skillManager;

  ToolBoxRepository({SkillManager? skillManager})
      : _skillManager = skillManager ?? SkillManager();

  /// 从 AI 定义创建 Skill
  Future<ToolEntity> createSkillFromAi(
    Map<String, dynamic> definition, {
    ToolScope scope = ToolScope.global,
    String? siteId,
    String? riskLevel,
    String? siteName,
  }) {
    final meta = (definition['meta'] as Map? ?? {});
    final displayName = meta['display_name']?.toString() ?? meta['name']?.toString() ?? '未命名技能';
    final description = meta['description']?.toString() ?? '';

    return _skillManager.createSkill(
      name: displayName,
      description: description,
      content: const JsonEncoder.withIndent('  ').convert(definition),
      parameters: _parseParams(definition['params'] ?? definition['variables']),
      scope: scope,
      source: ToolSource.ai,
      siteId: siteId,
      riskLevel: riskLevel,
    );
  }

  /// 从 AI 定义创建 MCP 工具
  Future<ToolEntity> createMcpFromAi(
    Map<String, dynamic> definition, {
    ToolScope scope = ToolScope.global,
    String? siteId,
    String? riskLevel,
    String? siteName,
  }) {
    final meta = (definition['meta'] as Map? ?? {});
    final displayName = meta['display_name']?.toString() ?? meta['name']?.toString() ?? '未命名工具';
    final description = meta['description']?.toString() ?? '';
    final name = meta['name']?.toString() ?? '';

    return _skillManager.registerMcpTool(
      name: displayName,
      description: description,
      endpoint: name,
      parameters: _parseParams(definition['params']),
      scope: scope,
      source: ToolSource.ai,
      siteId: siteId,
      riskLevel: riskLevel,
    );
  }

  /// 当前会话可见的工具（全局 + 当前站点私有）
  List<ToolEntity> toolsForSite(String? siteId) {
    final all = _skillManager.allTools;
    if (siteId == null || siteId.isEmpty) {
      return all.where((t) => t.scope == ToolScope.global).toList();
    }
    return all
        .where((t) =>
            t.scope == ToolScope.global ||
            (t.scope == ToolScope.sitePrivate && t.siteId == siteId))
        .toList();
  }

  /// 禁用/启用工具
  Future<bool> setEnabled(String id, bool enabled) {
    final tool = _skillManager.allTools.where((t) => t.id == id).firstOrNull;
    if (tool == null) return Future.value(false);
    if (tool.type == ToolType.skill) {
      return _skillManager
          .updateSkill(id, enabled: enabled)
          .then((_) => true);
    }
    return _skillManager.updateMcpTool(id, enabled: enabled).then((_) => true);
  }

  /// 切换工具作用域
  Future<bool> setScope(String id, ToolScope scope, {String? siteId}) {
    final tool = _skillManager.allTools.where((t) => t.id == id).firstOrNull;
    if (tool == null) return Future.value(false);
    final newSiteId = scope == ToolScope.sitePrivate ? (siteId ?? tool.siteId) : null;
    if (tool.type == ToolType.skill) {
      return _skillManager
          .updateSkill(
            id,
            scope: scope,
            siteId: newSiteId,
          )
          .then((_) => true);
    }
    return _skillManager
        .updateMcpTool(id, scope: scope, siteId: newSiteId)
        .then((_) => true);
  }

  /// 删除工具
  Future<bool> delete(String id) {
    final tool = _skillManager.allTools.where((t) => t.id == id).firstOrNull;
    if (tool == null) return Future.value(false);
    if (tool.type == ToolType.skill) return _skillManager.deleteSkill(id);
    return _skillManager.deleteMcpTool(id);
  }

  /// 解析 AI 定义中的参数列表
  static List<ToolParam> _parseParams(dynamic raw) {
    final params = <ToolParam>[];
    if (raw is! List) return params;
    for (final p in raw) {
      if (p is Map) {
        params.add(ToolParam(
          name: p['key']?.toString() ?? p['name']?.toString() ?? '',
          type: _normalizeType(p['type']?.toString()),
          description: p['description']?.toString() ?? '',
          required: p['required'] == true,
          defaultValue: p['default'],
        ));
      }
    }
    return params;
  }

  static String _normalizeType(String? type) {
    switch (type) {
      case 'bool':
      case 'boolean':
        return 'boolean';
      case 'int':
      case 'integer':
      case 'number':
        return 'number';
      case 'path':
        return 'string';
      case 'array':
        return 'array';
      case 'object':
        return 'object';
      default:
        return 'string';
    }
  }
}

/// 工具注册表扩展：支持按站点作用域加载工具
extension ToolRegistryScope on ToolRegistry {
  /// 将工具列表注册到全局注册表（供 Function Calling 使用）
  void registerScoped(List<ToolEntity> tools) {
    for (final t in tools) {
      _register(t);
    }
  }

  void _register(ToolEntity tool) {
    switch (tool.type) {
      case ToolType.builtin:
        registerBuiltin(tool);
      case ToolType.skill:
        registerSkill(tool);
      case ToolType.mcp:
        registerMcp(tool);
    }
  }
}
