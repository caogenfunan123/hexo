import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

/// 本地 GGUF 模型推理提供者。
///
/// 内部基于 `llamadart`（Dart/Flutter binding of llama.cpp，FFI + isolate）。
/// 构建期 hook 自动下载匹配平台的预编译 native 运行时，Android 默认启用
/// **CPU + Vulkan 双后端**：模型加载时 [ModelParams.gpuLayers] 自动将
/// 算子卸载到 GPU（无 GPU 时自动回退 CPU），显著提升推理速度。
///
/// 提供逐 token 真流式接口 [generateStream]（内部为
/// `engine.generate` → `Stream<String>`），UI 可实时渲染，避免"思考完成才
/// 一次性显示"与"长时间无输出假死"。
///
/// 仅 Android / iOS / 桌面 / Web 等 llamadart 支持平台启用；其他平台
/// [isAvailable] 返回 false，上层应给出"本地模型当前平台不可用"的提示。
class LocalLlamaProvider {
  LocalLlamaProvider._();

  static final LocalLlamaProvider instance = LocalLlamaProvider._();

  /// llamadart 引擎与后端（FFI isolate）。
  LlamaEngine? _engine;
  String? _loadedModelPath;
  int? _loadedContextSize;
  String? _lastError;
  String? _backendName;
  ({int total, int free})? _vram;

  /// 是否可在当前平台使用（llamadart 支持 Android/iOS/桌面/Web）。
  bool get isAvailable {
    if (kIsWeb) return true;
    return true;
  }

  /// 当前已加载的模型是否在内存中。
  bool get isModelLoaded => _engine != null && (_engine?.isReady ?? false);

  /// 已加载模型的上文 token 数（llamadart 不直接暴露，返回 0）。
  int get currentTokens => 0;

  String? get lastError => _lastError;

  /// 实际生效的推理后端名称（如 llama.cpp Vulkan / CPU），用于确认
  /// GPU 加速是否真正启用；未加载模型时为 null。
  String? get backendName => _backendName;

  /// 显存信息（字节），Vulkan/GPU 后端可用时返回。
  ({int total, int free})? get vram => _vram;

  /// 是否已初始化（有已加载模型）。
  bool get initialized => isModelLoaded;

  /// 动态线程数：取设备物理核心数，超出 8 核封顶（避免线程过度竞争）。
  int get _dynamicThreads {
    try {
      if (kIsWeb) return 4;
      final cores = Platform.numberOfProcessors;
      if (cores > 0) return cores > 8 ? 8 : cores;
    } catch (_) {}
    return 4;
  }

  /// 加载 GGUF 模型文件（llamadart modelLoad + contextCreate）。
  /// [modelPath] 为本地 .gguf 文件绝对路径，[contextSize] 为上下文长度。
  /// 返回 null 表示成功，否则返回错误信息。
  Future<String?> loadModel(String modelPath, {int contextSize = 4096}) async {
    _lastError = null;
    if (!isAvailable) {
      _lastError = '本地模型当前平台不可用';
      return _lastError;
    }
    final normalizedPath = modelPath.trim();
    if (isModelLoaded &&
        _loadedModelPath == normalizedPath &&
        _loadedContextSize == contextSize) {
      return null;
    }
    if (isModelLoaded &&
        (_loadedModelPath != normalizedPath ||
            _loadedContextSize != contextSize)) {
      await unload();
    }
    try {
      final engine = _engine ??= LlamaEngine(LlamaBackend());

      // llamadart 在 Android 上把默认的 auto 后端强制解析为 CPU 并把 GPU
      // 层数归零（防止不稳定 Vulkan 栈崩溃），因此必须显式探测并指定
      // Vulkan 才能真正启用 GPU 加速；无 GPU 设备探测后回退 CPU。
      var useGpu = false;
      try {
        useGpu = await engine.isGpuSupported();
      } catch (_) {}

      await engine.loadModel(
        normalizedPath,
        modelParams: ModelParams(
          contextSize: contextSize,
          // GPU 层数：全量卸载到 GPU（配合显式 Vulkan 后端）。
          gpuLayers: ModelParams.maxGpuLayers,
          preferredBackend: useGpu ? GpuBackend.vulkan : GpuBackend.cpu,
          numberOfThreads: _dynamicThreads,
          useMmap: true,
          useMlock: false,
        ),
      );
      _loadedModelPath = normalizedPath;
      _loadedContextSize = contextSize;
      _backendName = null;
      _vram = null;
      try {
        _backendName = await engine.getBackendName();
      } catch (_) {}
      try {
        _vram = await engine.getVramInfo();
      } catch (_) {}
      return null;
    } catch (e) {
      _lastError = '加载本地模型失败: $e';
      return _lastError;
    }
  }

  /// 单次完整生成（流式聚合，适合短文本）。
  /// [prompt] 为完整提示词（含 system + user），返回生成的补全文本。
  /// [maxTokens] 最大生成 token 数，[temperature] 采样温度。
  Future<String> complete(
    String prompt, {
    int maxTokens = 1024,
    double temperature = 0.7,
  }) async {
    final engine = _engine;
    if (engine == null || !engine.isReady) {
      return '本地模型未加载。请先在"AI 模型管理"中导入并加载 GGUF 模型。';
    }
    final fit = await _fitToContext(prompt, maxTokens);
    if (fit.error != null) {
      return fit.error!;
    }
    final buf = StringBuffer();
    await for (final token in engine.generate(
      prompt,
      params: GenerationParams(
        maxTokens: fit.maxTokens,
        temp: temperature,
      ),
    )) {
      buf.write(token);
    }
    return buf.toString();
  }

  /// 生成前检查提示词是否超出上下文窗口，避免 llamadart 抛出
  /// "Tokenization failed or prompt too long"。
  ///
  /// 返回 [error] 表示提示词本身已超限（需要清理历史/缩短输入）；
  /// 否则返回调整后的 [maxTokens]：当提示词占用过多上下文时自动压缩
  /// 输出长度，保证 prompt + maxTokens 不会撑爆 KV 缓存。
  Future<({String? error, int maxTokens})> _fitToContext(
    String prompt,
    int maxTokens,
  ) async {
    final engine = _engine;
    final contextSize = _loadedContextSize ?? 4096;
    var promptTokens = 0;
    if (engine != null) {
      try {
        final tokens = await engine.tokenize(prompt, addSpecial: false);
        promptTokens = tokens.length;
      } catch (_) {
        promptTokens = prompt.length;
      }
    } else {
      promptTokens = prompt.length;
    }
    const safety = 32;
    final usable = contextSize - safety;
    if (promptTokens > usable) {
      return (
        error: '提示词过长（约 $promptTokens token，上下文上限 $contextSize）。'
            '请清空会话历史或缩短输入内容后再试。',
        maxTokens: 0,
      );
    }
    final roomForOutput = usable - promptTokens;
    final effective = maxTokens > roomForOutput
        ? (roomForOutput < 16 ? 16 : roomForOutput)
        : maxTokens;
    return (error: null, maxTokens: effective);
  }

  /// 流式生成：逐 token 产出补全文本（真流式）。
  ///
  /// 基于 llamadart `engine.generate` → `Stream<String>`，每个 token 立即
  /// 产出，首个 token 到达前不做任何缓冲；调用方（UI）可实时展示。
  Stream<String> generateStream(
    String prompt, {
    int maxTokens = 1024,
    double temperature = 0.7,
  }) async* {
    final engine = _engine;
    if (engine == null || !engine.isReady) {
      yield '本地模型未加载。请先在"AI 模型管理"中导入并加载 GGUF 模型。';
      return;
    }
    final fit = await _fitToContext(prompt, maxTokens);
    if (fit.error != null) {
      yield fit.error!;
      return;
    }
    yield* engine.generate(
      prompt,
      params: GenerationParams(
        maxTokens: fit.maxTokens,
        temp: temperature,
      ),
    );
  }

  /// 取消当前正在进行的生成（llamadart backend.cancelGeneration）。
  Future<void> stopCompletion() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      engine.cancelGeneration();
    } catch (_) {}
  }

  /// 卸载当前模型，释放内存。
  Future<void> unload() async {
    final engine = _engine;
    _loadedModelPath = null;
    _loadedContextSize = null;
    if (engine != null) {
      try {
        await engine.unloadModel();
      } catch (_) {}
    }
    _lastError = null;
    _backendName = null;
    _vram = null;
  }

  /// 释放全部引擎资源（应用退出时调用）。
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    _loadedModelPath = null;
    _loadedContextSize = null;
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (_) {}
    }
    _lastError = null;
    _backendName = null;
    _vram = null;
  }

  /// 从 GGUF 文件名推导一个可读的模型名。
  static String modelNameFromPath(String path) {
    final name = path.split('/').last.split('\\').last;
    var base = name;
    if (base.toLowerCase().endsWith('.gguf')) {
      base = base.substring(0, base.length - 5);
    }
    return base;
  }

  /// 估算模型上下文是否能容纳 [tokenCount] 个 token。
  bool canFit(int tokenCount, {int contextSize = 4096}) =>
      tokenCount <= contextSize;
}
