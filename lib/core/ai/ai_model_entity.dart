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

  AiModelEntity({
    required this.modelId,
    required this.modelName,
    required this.apiBase,
    required this.apiKey,
    this.apiPath,
    this.useBearer = true,
    this.timeoutSecond = 50,
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
        timeoutSecond: (j['timeoutSecond'] as num?)?.toInt() ?? 50,
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

/// 模型响应速度统计
class ModelStats {
  final String modelId;
  final String apiBase;
  final int totalCalls;
  final int totalSuccess;
  final int totalFail;
  final int totalDurationMs;
  final int fastestMs;
  final int slowestMs;
  final DateTime lastUsedAt;

  ModelStats({
    required this.modelId,
    required this.apiBase,
    this.totalCalls = 0,
    this.totalSuccess = 0,
    this.totalFail = 0,
    this.totalDurationMs = 0,
    this.fastestMs = 0,
    this.slowestMs = 0,
    DateTime? lastUsedAt,
  }) : lastUsedAt = lastUsedAt ?? DateTime.now();

  double get avgDurationMs =>
      totalCalls > 0 ? totalDurationMs / totalCalls : 0;

  double get successRate =>
      totalCalls > 0 ? totalSuccess / totalCalls : 0;

  String get avgLabel => '${avgDurationMs.toStringAsFixed(0)}ms';
  String get successLabel => '${(successRate * 100).toStringAsFixed(0)}%';

  ModelStats recordCall(int durationMs, bool success) {
    return ModelStats(
      modelId: modelId,
      apiBase: apiBase,
      totalCalls: totalCalls + 1,
      totalSuccess: totalSuccess + (success ? 1 : 0),
      totalFail: totalFail + (success ? 0 : 1),
      totalDurationMs: totalDurationMs + durationMs,
      fastestMs: fastestMs == 0 ? durationMs : (durationMs < fastestMs ? durationMs : fastestMs),
      slowestMs: durationMs > slowestMs ? durationMs : slowestMs,
      lastUsedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'modelId': modelId,
        'apiBase': apiBase,
        'totalCalls': totalCalls,
        'totalSuccess': totalSuccess,
        'totalFail': totalFail,
        'totalDurationMs': totalDurationMs,
        'fastestMs': fastestMs,
        'slowestMs': slowestMs,
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  factory ModelStats.fromJson(Map<String, dynamic> j) => ModelStats(
        modelId: j['modelId']?.toString() ?? '',
        apiBase: j['apiBase']?.toString() ?? '',
        totalCalls: (j['totalCalls'] as num?)?.toInt() ?? 0,
        totalSuccess: (j['totalSuccess'] as num?)?.toInt() ?? 0,
        totalFail: (j['totalFail'] as num?)?.toInt() ?? 0,
        totalDurationMs: (j['totalDurationMs'] as num?)?.toInt() ?? 0,
        fastestMs: (j['fastestMs'] as num?)?.toInt() ?? 0,
        slowestMs: (j['slowestMs'] as num?)?.toInt() ?? 0,
        lastUsedAt: DateTime.tryParse(j['lastUsedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}