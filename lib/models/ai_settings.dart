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

  // ── 全局模型调度器配置 ──
  final int aiRequestTimeoutSec;   // 请求超时阈值（秒），默认 25
  final int aiMaxSwitchCount;      // 最大自动切换次数，默认 3
  final bool aiAutoOptimalModel;   // 自动择优模式，默认开启
  final bool aiAllowAutoSaveTools; // 允许 AI 自动保存工具到工具箱，默认开启
  final bool aiConfirmHighRiskTools; // 高风险工具（删除/回滚/克隆）执行前需用户确认，默认关闭（AI 全权）

  const AiSettings({
    this.aiProvider = 'openai',
    this.aiApiKey = '',
    this.aiBaseUrl = 'https://api.openai.com/v1',
    this.aiModel = 'gpt-4o-mini',
    this.aiProfiles = const [],
    this.activeAiProfileId = '',
    this.defaultModelId = '',
    this.defaultModelBase = '',
    this.aiRequestTimeoutSec = 50,
    this.aiMaxSwitchCount = 3,
    this.aiAutoOptimalModel = true,
    this.aiAllowAutoSaveTools = true,
    this.aiConfirmHighRiskTools = false,
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

  /// 是否有可用的模型配置。
  ///
  /// 兼容两套体系：settings 内 profile / 全局密钥字段非空即视为已配置。
  /// 注意：中转站模型（modelManager 的 ai_models.json）不在此判断范围内，
  /// 因为 settings 层不可见该数据——对话本身能运行即代表模型可用，
  /// 调用方不应仅凭本 getter 拒绝功能。
  bool get hasModelConfig =>
      effectiveAiApiKey.isNotEmpty ||
      aiApiKey.isNotEmpty ||
      aiProfiles.any((p) => p.apiKey.isNotEmpty);

  AiSettings copyWith({
    String? aiProvider,
    String? aiApiKey,
    String? aiBaseUrl,
    String? aiModel,
    List<AiProfile>? aiProfiles,
    String? activeAiProfileId,
    String? defaultModelId,
    String? defaultModelBase,
    int? aiRequestTimeoutSec,
    int? aiMaxSwitchCount,
    bool? aiAutoOptimalModel,
    bool? aiAllowAutoSaveTools,
    bool? aiConfirmHighRiskTools,
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
      aiRequestTimeoutSec: aiRequestTimeoutSec ?? this.aiRequestTimeoutSec,
      aiMaxSwitchCount: aiMaxSwitchCount ?? this.aiMaxSwitchCount,
      aiAutoOptimalModel: aiAutoOptimalModel ?? this.aiAutoOptimalModel,
      aiAllowAutoSaveTools: aiAllowAutoSaveTools ?? this.aiAllowAutoSaveTools,
      aiConfirmHighRiskTools:
          aiConfirmHighRiskTools ?? this.aiConfirmHighRiskTools,
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
        'aiRequestTimeoutSec': aiRequestTimeoutSec,
        'aiMaxSwitchCount': aiMaxSwitchCount,
        'aiAutoOptimalModel': aiAutoOptimalModel,
        'aiAllowAutoSaveTools': aiAllowAutoSaveTools,
        'aiConfirmHighRiskTools': aiConfirmHighRiskTools,
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
      aiRequestTimeoutSec: (j['aiRequestTimeoutSec'] as num?)?.toInt() ?? 50,
      aiMaxSwitchCount: (j['aiMaxSwitchCount'] as num?)?.toInt() ?? 3,
      aiAutoOptimalModel: j['aiAutoOptimalModel'] != false,
      aiAllowAutoSaveTools: j['aiAllowAutoSaveTools'] != false,
      aiConfirmHighRiskTools: j['aiConfirmHighRiskTools'] == true,
    );
  }
}