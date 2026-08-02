import 'tool_entity.dart';

/// 工具注册表：管理所有可用工具（内置 + 自定义技能 + MCP）
class ToolRegistry {
  static final ToolRegistry _instance = ToolRegistry._();
  factory ToolRegistry() => _instance;
  ToolRegistry._();

  final Map<String, ToolEntity> _tools = {};

  /// 注册内置工具
  void registerBuiltin(ToolEntity tool) {
    _tools[tool.id] = tool;
  }

  /// 注册自定义技能
  void registerSkill(ToolEntity tool) {
    _tools[tool.id] = tool;
  }

  /// 注册 MCP 工具
  void registerMcp(ToolEntity tool) {
    _tools[tool.id] = tool;
  }

  /// 批量注册
  void registerAll(List<ToolEntity> tools) {
    for (final t in tools) {
      _tools[t.id] = t;
    }
  }

  /// 移除工具
  void unregister(String toolId) {
    _tools.remove(toolId);
  }

  /// 获取工具
  ToolEntity? get(String toolId) => _tools[toolId];

  /// 获取所有启用的工具
  List<ToolEntity> get enabledTools =>
      _tools.values.where((t) => t.enabled).toList();

  /// 获取所有工具
  List<ToolEntity> get allTools => _tools.values.toList();

  /// 按类型过滤
  List<ToolEntity> getByType(ToolType type) =>
      _tools.values.where((t) => t.type == type && t.enabled).toList();

  /// 生成 OpenAI tools 参数
  List<Map<String, dynamic>> toOpenAiTools() =>
      enabledTools.map((t) => t.toOpenAiFunction()).toList();

  /// 清空非内置工具
  void clearCustom() {
    _tools.removeWhere((_, t) => t.type != ToolType.builtin);
  }

  /// 重置所有
  void reset() {
    _tools.clear();
  }
}