/// 工具类型

import 'dart:convert';

enum ToolType {
  builtin,    // 内置工具（web_search, web_fetch）
  skill,      // 用户自定义技能
  mcp,        // MCP 协议工具
}

/// 工具参数定义
class ToolParam {
  final String name;
  final String type;       // string, number, boolean, object, array
  final String description;
  final bool required;
  final dynamic defaultValue;

  const ToolParam({
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.defaultValue,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'description': description,
    'required': required,
    if (defaultValue != null) 'default': defaultValue,
  };

  Map<String, dynamic> toOpenAiSchema() {
    final schema = <String, dynamic>{
      'type': type,
      'description': description,
    };
    if (type == 'array') {
      schema['items'] = {'type': 'string'};
    }
    return schema;
  }

  factory ToolParam.fromJson(Map<String, dynamic> j) => ToolParam(
    name: j['name']?.toString() ?? '',
    type: j['type']?.toString() ?? 'string',
    description: j['description']?.toString() ?? '',
    required: j['required'] == true,
    defaultValue: j['default'],
  );
}

/// 工具实体定义
class ToolEntity {
  final String id;
  final String name;
  final String description;
  final ToolType type;
  final List<ToolParam> parameters;
  final String? endpoint;        // MCP: 服务端点
  final String? skillContent;    // Skill: 技能内容（System Prompt）
  final String? builtinHandler;  // Builtin: 处理器标识
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool enabled;

  const ToolEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.parameters = const [],
    this.endpoint,
    this.skillContent,
    this.builtinHandler,
    required this.createdAt,
    required this.updatedAt,
    this.enabled = true,
  });

  /// 生成 OpenAI Function Calling 格式的工具定义
  Map<String, dynamic> toOpenAiFunction() {
    final props = <String, dynamic>{};
    final required = <String>[];
    for (final p in parameters) {
      props[p.name] = p.toOpenAiSchema();
      if (p.required) required.add(p.name);
    }
    return {
      'type': 'function',
      'function': {
        'name': id,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': props,
          if (required.isNotEmpty) 'required': required,
        },
      },
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.name,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'endpoint': endpoint,
    'skillContent': skillContent,
    'builtinHandler': builtinHandler,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'enabled': enabled,
  };

  factory ToolEntity.fromJson(Map<String, dynamic> j) => ToolEntity(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    description: j['description']?.toString() ?? '',
    type: _parseType(j['type']?.toString()),
    parameters: (j['parameters'] as List?)
        ?.whereType<Map>()
        .map((e) => ToolParam.fromJson(Map<String, dynamic>.from(e)))
        .toList() ?? [],
    endpoint: j['endpoint']?.toString(),
    skillContent: j['skillContent']?.toString(),
    builtinHandler: j['builtinHandler']?.toString(),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    enabled: j['enabled'] != false,
  );

  static ToolType _parseType(String? s) {
    switch (s) {
      case 'skill': return ToolType.skill;
      case 'mcp': return ToolType.mcp;
      default: return ToolType.builtin;
    }
  }

  ToolEntity copyWith({
    String? id,
    String? name,
    String? description,
    ToolType? type,
    List<ToolParam>? parameters,
    String? endpoint,
    String? skillContent,
    String? builtinHandler,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? enabled,
  }) {
    return ToolEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      parameters: parameters ?? this.parameters,
      endpoint: endpoint ?? this.endpoint,
      skillContent: skillContent ?? this.skillContent,
      builtinHandler: builtinHandler ?? this.builtinHandler,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// 工具调用请求
class ToolCallRequest {
  final String toolId;
  final String callId;
  final Map<String, dynamic> arguments;

  const ToolCallRequest({
    required this.toolId,
    this.callId = '',
    required this.arguments,
  });

  factory ToolCallRequest.fromOpenAi(Map<String, dynamic> j) {
    final func = j['function'] as Map<String, dynamic>? ?? {};
    return ToolCallRequest(
      toolId: func['name']?.toString() ?? '',
      callId: j['id']?.toString() ?? '',
      arguments: _parseArgs(func['arguments']),
    );
  }

  static Map<String, dynamic> _parseArgs(dynamic args) {
    if (args is Map) return Map<String, dynamic>.from(args);
    if (args is String) {
      try {
        final parsed = jsonDecode(args);
        if (parsed is Map) return Map<String, dynamic>.from(parsed);
      } catch (_) {}
    }
    return {};
  }
}

/// 工具调用结果
class ToolCallResult {
  final String toolId;
  final String content;
  final bool success;
  final String? error;

  const ToolCallResult({
    required this.toolId,
    required this.content,
    this.success = true,
    this.error,
  });
}