import '../core/ai/ai_provider.dart';

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
  });

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
      };

  factory AiProfile.fromJson(Map<String, dynamic> j) {
    final raw = j['cachedModels'];
    final models = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e != null) models.add(e.toString());
      }
    }
    return AiProfile(
      id: j['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: j['name']?.toString() ?? '未命名',
      baseUrl: j['baseUrl']?.toString() ?? 'https://api.openai.com/v1',
      apiKey: j['apiKey']?.toString() ?? '',
      model: j['model']?.toString() ?? 'gpt-4o-mini',
      apiPath: j['apiPath']?.toString(),
      useBearer: j['useBearer'] != false,
      interfaceType: InterfaceType.fromCode(j['interfaceType']?.toString()),
      cachedModels: models,
    );
  }

  String get displayLabel {
    final m = model.isEmpty ? '未选模型' : model;
    return '$name · $m';
  }
}
