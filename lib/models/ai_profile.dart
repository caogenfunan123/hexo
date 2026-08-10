import '../core/ai/ai_provider.dart';
import 'local_model_settings.dart';

class AiProfile {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String? apiPath;
  final bool useBearer;
  final InterfaceType interfaceType;
  final List<String> cachedModels;
  final bool thinkingEnabled;
  final String reasoningEffort;
  final int reasoningBudgetTokens;
  final String? localModelPath;
  final int? localContextSize;
  final LocalModelSettings? localSettings;

  const AiProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.apiPath,
    this.useBearer = true,
    this.interfaceType = InterfaceType.openaiChat,
    this.cachedModels = const [],
    this.thinkingEnabled = false,
    this.reasoningEffort = 'medium',
    this.reasoningBudgetTokens = 1024,
    this.localModelPath,
    this.localContextSize,
    this.localSettings,
  });

  bool get isLocalModel => localModelPath != null && localModelPath!.isNotEmpty;

  AiProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? apiPath,
    bool? useBearer,
    InterfaceType? interfaceType,
    List<String>? cachedModels,
    bool? thinkingEnabled,
    String? reasoningEffort,
    int? reasoningBudgetTokens,
    String? localModelPath,
    int? localContextSize,
    LocalModelSettings? localSettings,
    bool clearLocalModel = false,
  }) {
    return AiProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      apiPath: apiPath ?? this.apiPath,
      useBearer: useBearer ?? this.useBearer,
      interfaceType: interfaceType ?? this.interfaceType,
      cachedModels: cachedModels ?? this.cachedModels,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      reasoningBudgetTokens:
          reasoningBudgetTokens ?? this.reasoningBudgetTokens,
      localModelPath:
          clearLocalModel ? null : (localModelPath ?? this.localModelPath),
      localContextSize: localContextSize ?? this.localContextSize,
      localSettings: localSettings ?? this.localSettings,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'apiPath': apiPath,
        'useBearer': useBearer,
        'interfaceType': interfaceType.code,
        'cachedModels': cachedModels,
        'thinkingEnabled': thinkingEnabled,
        'reasoningEffort': reasoningEffort,
        'reasoningBudgetTokens': reasoningBudgetTokens,
        'localModelPath': localModelPath,
        'localContextSize': localContextSize,
        'localSettings': localSettings?.toJson(),
      };

  factory AiProfile.fromJson(Map<String, dynamic> j) {
    return AiProfile(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      baseUrl: j['baseUrl']?.toString() ?? '',
      apiKey: j['apiKey']?.toString() ?? '',
      model: j['model']?.toString() ?? '',
      apiPath: j['apiPath']?.toString(),
      useBearer: j['useBearer'] as bool? ?? true,
      interfaceType:
          InterfaceType.fromCode(j['interfaceType']?.toString() ?? ''),
      cachedModels: (j['cachedModels'] as List?)?.cast<String>() ?? const [],
      thinkingEnabled: j['thinkingEnabled'] as bool? ?? false,
      reasoningEffort: j['reasoningEffort']?.toString() ?? 'medium',
      reasoningBudgetTokens: j['reasoningBudgetTokens'] as int? ?? 1024,
      localModelPath: j['localModelPath']?.toString(),
      localContextSize: (j['localContextSize'] as num?)?.toInt(),
      localSettings: j['localSettings'] is Map
          ? LocalModelSettings.fromJson(
              Map<String, dynamic>.from(j['localSettings'] as Map),
            )
          : null,
    );
  }

  String get displayLabel {
    final m = model.isEmpty ? '未选模型' : model;
    return '$name · $m';
  }
}
