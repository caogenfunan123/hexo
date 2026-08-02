import 'dart:convert';
import 'dart:io';

import 'tool_entity.dart';
import 'tool_registry.dart';
import 'builtin_tools.dart';

/// 技能管理器：管理用户自定义技能（Skill）的 CRUD 和持久化
class SkillManager {
  static final SkillManager _instance = SkillManager._();
  factory SkillManager() => _instance;
  SkillManager._();

  final ToolRegistry _registry = ToolRegistry();
  List<ToolEntity> _skills = [];
  Directory? _storageDir;

  /// 初始化：加载已保存的技能并注册内置工具
  Future<void> init(Directory storageDir) async {
    _storageDir = storageDir;
    // 注册内置工具
    _registry.registerAll(BuiltinTools.all);
    // 加载自定义技能
    await _loadSkills();
  }

  /// 获取所有工具（内置 + 自定义）
  List<ToolEntity> get allTools => _registry.allTools;

  /// 获取所有自定义技能
  List<ToolEntity> get skills => _skills;

  /// 获取内置工具
  List<ToolEntity> get builtinTools => _registry.getByType(ToolType.builtin);

  /// 获取 MCP 工具
  List<ToolEntity> get mcpTools => _registry.getByType(ToolType.mcp);

  /// 生成 OpenAI tools 参数
  List<Map<String, dynamic>> get openAiTools => _registry.toOpenAiTools();

  /// 创建技能
  Future<ToolEntity> createSkill({
    required String name,
    required String description,
    String? content,
    List<ToolParam> parameters = const [],
  }) async {
    final now = DateTime.now();
    final id = 'skill_${now.millisecondsSinceEpoch}';
    final skill = ToolEntity(
      id: id,
      name: name,
      description: description,
      type: ToolType.skill,
      parameters: parameters,
      skillContent: content,
      createdAt: now,
      updatedAt: now,
    );
    _skills.add(skill);
    _registry.registerSkill(skill);
    await _saveSkills();
    return skill;
  }

  /// 更新技能
  Future<ToolEntity?> updateSkill(String id, {
    String? name,
    String? description,
    String? content,
    List<ToolParam>? parameters,
    bool? enabled,
  }) async {
    final idx = _skills.indexWhere((s) => s.id == id);
    if (idx < 0) return null;

    final updated = _skills[idx].copyWith(
      name: name,
      description: description,
      skillContent: content,
      parameters: parameters,
      enabled: enabled,
      updatedAt: DateTime.now(),
    );
    _skills[idx] = updated;
    _registry.unregister(id);
    _registry.registerSkill(updated);
    await _saveSkills();
    return updated;
  }

  /// 删除技能
  Future<bool> deleteSkill(String id) async {
    _skills.removeWhere((s) => s.id == id);
    _registry.unregister(id);
    await _saveSkills();
    return true;
  }

  /// 注册 MCP 工具
  Future<ToolEntity> registerMcpTool({
    required String name,
    required String description,
    required String endpoint,
    List<ToolParam> parameters = const [],
  }) async {
    final now = DateTime.now();
    final id = 'mcp_${now.millisecondsSinceEpoch}';
    final tool = ToolEntity(
      id: id,
      name: name,
      description: description,
      type: ToolType.mcp,
      parameters: parameters,
      endpoint: endpoint,
      createdAt: now,
      updatedAt: now,
    );
    _registry.registerMcp(tool);
    await _saveMcpTools();
    return tool;
  }

  /// 删除 MCP 工具
  Future<bool> deleteMcpTool(String id) async {
    _registry.unregister(id);
    await _saveMcpTools();
    return true;
  }

  /// 获取所有 MCP 工具定义
  Future<List<ToolEntity>> loadMcpTools() async {
    if (_storageDir == null) return [];
    try {
      final file = File('${_storageDir!.path}/mcp_tools.json');
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      final list = jsonDecode(text) as List;
      final tools = list
          .whereType<Map>()
          .map((e) => ToolEntity.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      for (final t in tools) {
        _registry.registerMcp(t);
      }
      return tools;
    } catch (_) {
      return [];
    }
  }

  // ── 私有方法 ──

  Future<void> _loadSkills() async {
    if (_storageDir == null) return;
    try {
      final file = File('${_storageDir!.path}/skills.json');
      if (!await file.exists()) return;
      final text = await file.readAsString();
      final list = jsonDecode(text) as List;
      _skills = list
          .whereType<Map>()
          .map((e) => ToolEntity.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      for (final s in _skills) {
        _registry.registerSkill(s);
      }
    } catch (_) {
      _skills = [];
    }
  }

  Future<void> _saveSkills() async {
    if (_storageDir == null) return;
    try {
      final file = File('${_storageDir!.path}/skills.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          _skills.map((s) => s.toJson()).toList(),
        ),
      );
    } catch (_) {}
  }

  Future<void> _saveMcpTools() async {
    if (_storageDir == null) return;
    try {
      final mcpTools = _registry.getByType(ToolType.mcp);
      final file = File('${_storageDir!.path}/mcp_tools.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          mcpTools.map((t) => t.toJson()).toList(),
        ),
      );
    } catch (_) {}
  }
}