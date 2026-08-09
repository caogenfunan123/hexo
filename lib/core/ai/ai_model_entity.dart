import 'ai_provider.dart';

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
  final ModelProvider provider;
  final InterfaceType interfaceType;
  final bool supportImage;
  final bool thinkingEnabled;
  final String reasoningEffort;
  final int reasoningBudgetTokens;
  final int contextLimit;
  final int outputLimit;
  final DateTime createdAt;

  /// 备用密钥池（不含主密钥 [apiKey]）。
  final List<String> keyPool;

  /// 当前使用的密钥索引（0 = 主密钥 apiKey，1..n = keyPool 元素）。
  final int keyPoolIndex;

  /// 当前密钥连续失败次数（达到阈值后轮转到下一个密钥）。
  final int consecutiveFailures;

  /// 连续失败多少次后轮换密钥。
  static const int keyFailThreshold = 3;

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
    ModelProvider? provider,
    InterfaceType? interfaceType,
    this.supportImage = false,
    this.thinkingEnabled = false,
    this.reasoningEffort = 'medium',
    this.reasoningBudgetTokens = 1024,
    this.contextLimit = 0,
    this.outputLimit = 0,
    this.keyPool = const [],
    this.keyPoolIndex = 0,
    this.consecutiveFailures = 0,
    DateTime? createdAt,
  })  : provider = provider ?? ModelProvider.custom,
        interfaceType = interfaceType ?? inferInterfaceType(modelId),
        createdAt = createdAt ?? DateTime.now();

  /// 合并后的全部密钥（主密钥 + 池内备用）。
  List<String> get allKeys => [apiKey, ...keyPool];

  /// 当前生效的密钥（按索引回绕）。
  String get effectiveKey {
    final keys = allKeys.where((k) => k.isNotEmpty).toList();
    if (keys.isEmpty) return apiKey;
    final idx = keyPoolIndex % keys.length;
    return keys[idx];
  }

  /// 是否有备用密钥。
  bool get hasKeyPool => keyPool.isNotEmpty;

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
    ModelProvider? provider,
    InterfaceType? interfaceType,
    bool? supportImage,
    bool? thinkingEnabled,
    String? reasoningEffort,
    int? reasoningBudgetTokens,
    int? contextLimit,
    int? outputLimit,
    List<String>? keyPool,
    int? keyPoolIndex,
    int? consecutiveFailures,
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
      provider: provider ?? this.provider,
      interfaceType: interfaceType ?? this.interfaceType,
      supportImage: supportImage ?? this.supportImage,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      reasoningBudgetTokens:
          reasoningBudgetTokens ?? this.reasoningBudgetTokens,
      contextLimit: contextLimit ?? this.contextLimit,
      outputLimit: outputLimit ?? this.outputLimit,
      keyPool: keyPool ?? this.keyPool,
      keyPoolIndex: keyPoolIndex ?? this.keyPoolIndex,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
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
        'provider': provider.code,
        'interfaceType': interfaceType.code,
        'supportImage': supportImage,
        'thinkingEnabled': thinkingEnabled,
        'reasoningEffort': reasoningEffort,
        'reasoningBudgetTokens': reasoningBudgetTokens,
        'contextLimit': contextLimit,
        'outputLimit': outputLimit,
        'keyPool': keyPool,
        'keyPoolIndex': keyPoolIndex,
        'consecutiveFailures': consecutiveFailures,
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
        provider: ModelProvider.fromCode(j['provider']?.toString()),
        interfaceType: InterfaceType.fromCode(j['interfaceType']?.toString()),
        supportImage: j['supportImage'] == true,
        thinkingEnabled: j['thinkingEnabled'] == true,
        reasoningEffort: j['reasoningEffort']?.toString() ?? 'medium',
        reasoningBudgetTokens: j['reasoningBudgetTokens'] as int? ?? 1024,
        contextLimit: (j['contextLimit'] as num?)?.toInt() ?? 0,
        outputLimit: (j['outputLimit'] as num?)?.toInt() ?? 0,
        keyPool:
            (j['keyPool'] as List?)?.whereType<String>().toList() ?? const [],
        keyPoolIndex: (j['keyPoolIndex'] as num?)?.toInt() ?? 0,
        consecutiveFailures: (j['consecutiveFailures'] as num?)?.toInt() ?? 0,
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