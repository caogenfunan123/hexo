/// 本地 GGUF 模型的完整推理设置（上下文参数 + 采样参数）。
///
/// 对标 pocketpal-ai 的 `ContextInitParams` + `CompletionParams` 版本化
/// 参数体系，但适配 llamadart 的 `ModelParams` / `GenerationParams`：
///
/// - 上下文/运行时参数：contextSize、batchSize、microBatchSize、线程数、
///   KV cache 类型、flash attention、kv_unified、mmap/mlock、GPU 层数、
///   设备选择、chat template。
/// - 采样参数：maxTokens、temperature、top_k/top_p/min_p、重复惩罚、
///   presence 惩罚、停止词。
///
/// 所有字段带默认值并序列化为 JSON；[version] 字段用于未来 schema 迁移，
/// 读取时缺失字段自动补默认值（对应 pocketpal 的 migrate 逻辑）。
class LocalModelSettings {
  /// 设备选择（对应 pocketpal 的 DeviceSelection，适配 llamadart）。
  final String device; // 'auto' | 'cpu' | 'vulkan'

  /// 卸载到 GPU 的层数（n_gpu_layers）。0 = 纯 CPU，999 = 全部。
  final int gpuLayers;

  /// 上下文长度（n_ctx，token 数）。
  final int contextSize;

  /// 逻辑批处理大小（n_batch）。0 = llamadart 自动。
  final int batchSize;

  /// 物理批处理大小（n_ubatch）。0 = llamadart 自动。
  final int microBatchSize;

  /// 生成线程数（n_threads）。0 = llamadart 自动探测。
  final int threads;

  /// 批处理线程数（n_threads_batch）。0 = llamadart 自动探测。
  final int threadsBatch;

  /// KV cache 类型 K（cache_type_k）：'f16' | 'q8_0' | 'q4_0'。
  final String cacheTypeK;

  /// KV cache 类型 V（cache_type_v）：'f16' | 'q8_0' | 'q4_0'。
  final String cacheTypeV;

  /// 是否统一 K/V 缓存（kv_unified）。省内存但部分模型不支持。
  final bool kvUnified;

  /// 是否内存映射加载权重（use_mmap）。
  final bool useMmap;

  /// 是否锁定权重常驻内存（use_mlock）。
  final bool useMlock;

  /// FlashAttention：'auto' | 'enabled' | 'disabled'。
  final String flashAttention;

  /// 最大并行序列槽位（n_seq_max）。
  final int maxParallelSequences;

  /// 覆盖模型的默认 chat template（可为 null 使用模型内置）。
  final String? chatTemplate;

  /// 最大生成 token 数（n_predict）。-1 = 直到 EOS。
  final int maxTokens;

  /// 采样温度。
  final double temperature;

  /// Top-K 采样（0 = 禁用）。
  final int topK;

  /// Top-P 采样。
  final double topP;

  /// Min-P 采样（0 = 禁用）。
  final double minP;

  /// 重复惩罚（1.0 = 无惩罚）。
  final double repeatPenalty;

  /// Presence 惩罚（0.0 = 禁用）。
  final double presencePenalty;

  /// 随机种子（null = 时间种子）。
  final int? seed;

  /// 停止序列列表。
  final List<String> stopSequences;

  /// 设置 schema 版本（当前 1）。
  final int version;

  const LocalModelSettings({
    this.device = 'auto',
    this.gpuLayers = 0,
    this.contextSize = 2048,
    this.batchSize = 0,
    this.microBatchSize = 0,
    this.threads = 0,
    this.threadsBatch = 0,
    this.cacheTypeK = 'f16',
    this.cacheTypeV = 'f16',
    this.kvUnified = true,
    this.useMmap = true,
    this.useMlock = false,
    this.flashAttention = 'auto',
    this.maxParallelSequences = 1,
    this.chatTemplate,
    this.maxTokens = 2048,
    this.temperature = 0.7,
    this.topK = 40,
    this.topP = 0.95,
    this.minP = 0.05,
    this.repeatPenalty = 1.0,
    this.presencePenalty = 0.0,
    this.seed,
    this.stopSequences = const ['</s>'],
    this.version = 1,
  });

  /// 当前 schema 版本。
  static const int currentVersion = 1;

  /// 合法设备选择值。
  static const List<String> devices = ['auto', 'cpu', 'vulkan'];

  /// 合法 KV cache 类型值。
  static const List<String> kvCacheTypes = ['f16', 'q8_0', 'q4_0'];

  /// 合法 flash attention 值。
  static const List<String> flashAttentionValues = [
    'auto',
    'enabled',
    'disabled',
  ];

  /// 设备是否为纯 CPU。
  bool get isCpuOnly => device == 'cpu';

  /// 是否显式指定 Vulkan GPU。
  bool get isVulkan => device == 'vulkan';

  /// 是否自动选择设备（探测 GPU，无则回退 CPU）。
  bool get isAuto => device == 'auto';

  /// GPU 层数是否全量卸载。
  bool get allGpuLayers => gpuLayers >= 999;

  /// 生效的上下文长度（自动 / 手动的公共展示）。
  int get effectiveContextSize => contextSize > 0 ? contextSize : 2048;

  LocalModelSettings copyWith({
    String? device,
    int? gpuLayers,
    int? contextSize,
    int? batchSize,
    int? microBatchSize,
    int? threads,
    int? threadsBatch,
    String? cacheTypeK,
    String? cacheTypeV,
    bool? kvUnified,
    bool? useMmap,
    bool? useMlock,
    String? flashAttention,
    int? maxParallelSequences,
    String? chatTemplate,
    bool clearChatTemplate = false,
    int? maxTokens,
    double? temperature,
    int? topK,
    double? topP,
    double? minP,
    double? repeatPenalty,
    double? presencePenalty,
    int? seed,
    List<String>? stopSequences,
  }) {
    return LocalModelSettings(
      device: device ?? this.device,
      gpuLayers: gpuLayers ?? this.gpuLayers,
      contextSize: contextSize ?? this.contextSize,
      batchSize: batchSize ?? this.batchSize,
      microBatchSize: microBatchSize ?? this.microBatchSize,
      threads: threads ?? this.threads,
      threadsBatch: threadsBatch ?? this.threadsBatch,
      cacheTypeK: cacheTypeK ?? this.cacheTypeK,
      cacheTypeV: cacheTypeV ?? this.cacheTypeV,
      kvUnified: kvUnified ?? this.kvUnified,
      useMmap: useMmap ?? this.useMmap,
      useMlock: useMlock ?? this.useMlock,
      flashAttention: flashAttention ?? this.flashAttention,
      maxParallelSequences: maxParallelSequences ?? this.maxParallelSequences,
      chatTemplate: clearChatTemplate
          ? null
          : (chatTemplate ?? this.chatTemplate),
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      topK: topK ?? this.topK,
      topP: topP ?? this.topP,
      minP: minP ?? this.minP,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      seed: seed ?? this.seed,
      stopSequences: stopSequences ?? this.stopSequences,
      version: version,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'device': device,
        'gpuLayers': gpuLayers,
        'contextSize': contextSize,
        'batchSize': batchSize,
        'microBatchSize': microBatchSize,
        'threads': threads,
        'threadsBatch': threadsBatch,
        'cacheTypeK': cacheTypeK,
        'cacheTypeV': cacheTypeV,
        'kvUnified': kvUnified,
        'useMmap': useMmap,
        'useMlock': useMlock,
        'flashAttention': flashAttention,
        'maxParallelSequences': maxParallelSequences,
        'chatTemplate': chatTemplate,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topK': topK,
        'topP': topP,
        'minP': minP,
        'repeatPenalty': repeatPenalty,
        'presencePenalty': presencePenalty,
        'seed': seed,
        'stopSequences': stopSequences,
      };

  /// 从 JSON 恢复设置。缺失字段自动补默认值（迁移逻辑），非法枚举
  /// 回退到默认值，保证任意旧数据可安全加载。
  factory LocalModelSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null || j.isEmpty) return const LocalModelSettings();

    String _enumString(
      dynamic raw,
      String fallback,
      List<String> allowed,
    ) {
      final s = raw?.toString() ?? '';
      return allowed.contains(s) ? s : fallback;
    }

    double _double(dynamic raw, double fallback) =>
        raw is num ? raw.toDouble() : fallback;

    int _int(dynamic raw, int fallback) => raw is num ? raw.toInt() : fallback;

    bool _bool(dynamic raw, bool fallback) => raw is bool ? raw : fallback;

    return LocalModelSettings(
      version: _int(j['version'], currentVersion),
      device: _enumString(j['device'], 'auto', devices),
      gpuLayers: _int(j['gpuLayers'], 0),
      contextSize: _int(j['contextSize'], 2048),
      batchSize: _int(j['batchSize'], 0),
      microBatchSize: _int(j['microBatchSize'], 0),
      threads: _int(j['threads'], 0),
      threadsBatch: _int(j['threadsBatch'], 0),
      cacheTypeK: _enumString(j['cacheTypeK'], 'f16', kvCacheTypes),
      cacheTypeV: _enumString(j['cacheTypeV'], 'f16', kvCacheTypes),
      kvUnified: _bool(j['kvUnified'], true),
      useMmap: _bool(j['useMmap'], true),
      useMlock: _bool(j['useMlock'], false),
      flashAttention: _enumString(
        j['flashAttention'],
        'auto',
        flashAttentionValues,
      ),
      maxParallelSequences: _int(j['maxParallelSequences'], 1),
      chatTemplate: j['chatTemplate']?.toString(),
      maxTokens: _int(j['maxTokens'], 2048),
      temperature: _double(j['temperature'], 0.7),
      topK: _int(j['topK'], 40),
      topP: _double(j['topP'], 0.95),
      minP: _double(j['minP'], 0.05),
      repeatPenalty: _double(j['repeatPenalty'], 1.0),
      presencePenalty: _double(j['presencePenalty'], 0.0),
      seed: j.containsKey('seed') && j['seed'] != null
          ? (j['seed'] as num?)?.toInt()
          : null,
      stopSequences:
          (j['stopSequences'] as List?)?.whereType<String>().toList() ??
              const ['</s>'],
    );
  }

  @override
  String toString() {
    final buf = StringBuffer();
    buf.writeln('设备: ${_deviceLabel}');
    buf.writeln('上下文: ${effectiveContextSize}');
    if (batchSize > 0) buf.writeln('批处理: n_batch=$batchSize n_ubatch=$microBatchSize');
    if (threads > 0) buf.writeln('线程: $threads${threadsBatch > 0 ? '(batch $threadsBatch)' : ''}');
    buf.writeln('KV cache: K=$cacheTypeK V=$cacheTypeV${kvUnified ? ' · 统一' : ''}');
    buf.writeln('FlashAttention: $_flashAttentionLabel');
    if (device != 'cpu') buf.writeln('GPU 层数: ${allGpuLayers ? '全部' : gpuLayers}');
    buf.writeln('采样: temp=$temperature top_k=$topK top_p=$topP min_p=$minP');
    if (repeatPenalty != 1.0) buf.writeln('重复惩罚: $repeatPenalty');
    if (presencePenalty != 0.0) buf.writeln('presence 惩罚: $presencePenalty');
    buf.writeln('最大输出: ${maxTokens == -1 ? '不限' : maxTokens}');
    return buf.toString();
  }

  String get _deviceLabel {
    switch (device) {
      case 'auto':
        return '自动（有 GPU 则加速）';
      case 'cpu':
        return 'CPU';
      case 'vulkan':
        return 'Vulkan GPU';
      default:
        return device;
    }
  }

  String get _flashAttentionLabel {
    switch (flashAttention) {
      case 'enabled':
        return '启用';
      case 'disabled':
        return '禁用';
      default:
        return '自动';
    }
  }
}
