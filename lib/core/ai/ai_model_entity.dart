/// AI 模型实体，用于中转站模型管理
class AiModelEntity {
  final String modelId;
  final String modelName;
  final String apiBase;
  final String apiKey;
  final String? apiPath;
  final bool useBearer;
  final int timeoutSecond;
  final bool enable;
  final int priority;
  final String group; // 'code' | 'general' | 'longtext'
  final DateTime createdAt;

  const AiModelEntity({
    required this.modelId,
    required this.modelName,
    required this.apiBase,
    required this.apiKey,
    this.apiPath,
    this.useBearer = true,
    this.timeoutSecond = 30,
    this.enable = true,
    this.priority = 0,
    this.group = 'general',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  AiModelEntity copyWith({
    String? modelId,
    String? modelName,
    String? apiBase,
    String? apiKey,
    String? apiPath,
    bool? useBearer,
    int? timeoutSecond,
    bool? enable,
    int? priority,
    String? group,
    DateTime? createdAt,
  }) {
    return AiModelEntity(
      modelId: modelId ?? this.modelId,
      modelName: modelName ?? this.modelName,
      apiBase: apiBase ?? this.apiBase,
      apiKey: apiKey ?? this.apiKey,
      apiPath: apiPath ?? this.apiPath,
      useBearer: useBearer ?? this.useBearer,
      timeoutSecond: timeoutSecond ?? this.timeoutSecond,
      enable: enable ?? this.enable,
      priority: priority ?? this.priority,
      group: group ?? this.group,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'modelId': modelId,
        'modelName': modelName,
        'apiBase': apiBase,
        'apiKey': apiKey,
        'apiPath': apiPath,
        'useBearer': useBearer,
        'timeoutSecond': timeoutSecond,
        'enable': enable,
        'priority': priority,
        'group': group,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AiModelEntity.fromJson(Map<String, dynamic> j) => AiModelEntity(
        modelId: j['modelId']?.toString() ?? '',
        modelName: j['modelName']?.toString() ?? '',
        apiBase: j['apiBase']?.toString() ?? '',
        apiKey: j['apiKey']?.toString() ?? '',
        apiPath: j['apiPath']?.toString(),
        useBearer: j['useBearer'] != false,
        timeoutSecond: (j['timeoutSecond'] as num?)?.toInt() ?? 30,
        enable: j['enable'] != false,
        priority: (j['priority'] as num?)?.toInt() ?? 0,
        group: j['group']?.toString() ?? 'general',
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  String get groupLabel {
    switch (group) {
      case 'code':
        return '🧑‍💻 代码优选';
      case 'general':
        return '📝 通用对话';
      case 'longtext':
        return '📄 长文本';
      default:
        return group;
    }
  }

  String get displayLabel => '$modelName · $modelId';
}