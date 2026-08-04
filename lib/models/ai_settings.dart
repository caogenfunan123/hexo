/// AI 设置子配置
/// 从 AppSettings 拆分，独立管理 AI 模型、API、Profile 配置
library;

import 'ai_profile.dart';

class AiSettings {
  final String aiProvider;
  final String aiApiKey;
  final String aiBaseUrl;
  final String aiModel;
  final List<AiProfile> aiProfiles;
  final String activeAiProfileId;
  final String defaultModelId;
  final String defaultModelBase;

  const AiSettings({
    this.aiProvider = 'openai',
    this.aiApiKey = '',
    this.aiBaseUrl = 'https://api.openai.com/v1',
    this.aiModel = 'gpt-4o-mini',
    this.aiProfiles = const [],
    this.activeAiProfileId = '',
    this.defaultModelId = '',
    this.defaultModelBase = '',
  });

  AiProfile? get activeAiProfile {
    if (aiProfiles.isEmpty) return null;
    for (final p in aiProfiles) {
      if (p.id == activeAiProfileId) return p;
    }
    return aiProfiles.first;
  }

  String get effectiveAiBaseUrl =>
      activeAiProfile?.baseUrl.isNotEmpty == true
          ? activeAiProfile!.baseUrl
          : aiBaseUrl;

  String get effectiveAiApiKey =>
      activeAiProfile?.apiKey.isNotEmpty == true
          ? activeAiProfile!.apiKey
          : aiApiKey;

  String get effectiveAiModel =>
      activeAiProfile?.model.isNotEmpty == true
          ? activeAiProfile!.model
          : aiModel;

  AiSettings copyWith({
    String? aiProvider,
    String? aiApiKey,
    String? aiBaseUrl,
    String? aiModel,
    List<AiProfile>? aiProfiles,
    String? activeAiProfileId,
    String? defaultModelId,
    String? defaultModelBase,
  }) {
    return AiSettings(
      aiProvider: aiProvider ?? this.aiProvider,
      aiApiKey: aiApiKey ?? this.aiApiKey,
      aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
      aiModel: aiModel ?? this.aiModel,
      aiProfiles: aiProfiles ?? this.aiProfiles,
      activeAiProfileId: activeAiProfileId ?? this.activeAiProfileId,
      defaultModelId: defaultModelId ?? this.defaultModelId,
      defaultModelBase: defaultModelBase ?? this.defaultModelBase,
    );
  }

  Map<String, dynamic> toJson() => {
        'aiProvider': aiProvider,
        'aiApiKey': aiApiKey,
        'aiBaseUrl': aiBaseUrl,
        'aiModel': aiModel,
        'aiProfiles': aiProfiles.map((e) => e.toJson()).toList(),
        'activeAiProfileId': activeAiProfileId,
        'defaultModelId': defaultModelId,
        'defaultModelBase': defaultModelBase,
      };

  factory AiSettings.fromJson(Map<String, dynamic> j) {
    final profilesRaw = j['aiProfiles'];
    final profiles = <AiProfile>[];
    if (profilesRaw is List) {
      for (final e in profilesRaw) {
        if (e is Map) {
          profiles.add(AiProfile.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final legacyKey = j['aiApiKey']?.toString() ?? '';
    final legacyUrl = j['aiBaseUrl']?.toString() ?? 'https://api.openai.com/v1';
    final legacyModel = j['aiModel']?.toString() ?? 'gpt-4o-mini';
    if (profiles.isEmpty && (legacyKey.isNotEmpty || legacyUrl.isNotEmpty)) {
      profiles.add(AiProfile(
        id: 'legacy',
        name: j['aiProvider']?.toString().isNotEmpty == true
            ? j['aiProvider'].toString()
            : '默认中转站',
        baseUrl: legacyUrl,
        apiKey: legacyKey,
        model: legacyModel,
      ));
    }
    final activeId = j['activeAiProfileId']?.toString() ??
        (profiles.isNotEmpty ? profiles.first.id : '');
    return AiSettings(
      aiProvider: j['aiProvider']?.toString() ?? 'openai',
      aiApiKey: legacyKey,
      aiBaseUrl: legacyUrl,
      aiModel: legacyModel,
      aiProfiles: profiles,
      activeAiProfileId: activeId,
      defaultModelId: j['defaultModelId']?.toString() ?? '',
      defaultModelBase: j['defaultModelBase']?.toString() ?? '',
    );
  }
}