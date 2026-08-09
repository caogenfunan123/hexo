import 'dart:async';
import 'dart:io';

import 'package:fcllama/fllama.dart';
import 'package:flutter/foundation.dart';

/// 本地 GGUF 模型推理提供者。
///
/// 内部基于 `fcllama`（Flutter binding of llama.cpp，platform channel）。
/// Android 构建时通过 CMake 自动编译 llama.cpp，APK 内已包含全部 native
/// 库，因此**导入 GGUF 即可用**，无需手动放置 .so。
///
/// 仅 Android 平台启用；其他平台 [isAvailable] 返回 false，
/// 上层应给出"本地模型仅在 Android 可用"的提示。
class LocalLlamaProvider {
  LocalLlamaProvider._();

  static final LocalLlamaProvider instance = LocalLlamaProvider._();

  /// fcllama 上下文 id（double，>0 表示已成功 initContext）
  double? _contextId;
  String? _loadedModelPath;
  int? _loadedContextSize;
  String? _lastError;
  Future<void> _completionQueue = Future<void>.value();

  /// 是否可在当前平台使用（仅 Android）。
  bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 当前已加载的模型是否在内存中。
  bool get isModelLoaded => _contextId != null;

  /// 已加载模型的上文 token 数（fcllama 不直接暴露，返回 0）。
  int get currentTokens => 0;

  String? get lastError => _lastError;

  /// 是否已在 Android 上初始化过（有上下文）。
  bool get initialized => _contextId != null;

  /// 动态线程数：取设备物理核心数，超出 8 核封顶（避免线程过度竞争）。
  int get _dynamicThreads {
    try {
      if (kIsWeb) return 4;
      final cores = Platform.numberOfProcessors;
      if (cores > 0) return cores > 8 ? 8 : cores;
    } catch (_) {}
    return 4;
  }

  /// 加载 GGUF 模型文件（fcllama initContext）。
  /// [modelPath] 为本地 .gguf 文件绝对路径，[contextSize] 为上下文长度。
  /// 返回 null 表示成功，否则返回错误信息。
  Future<String?> loadModel(String modelPath, {int contextSize = 4096}) async {
    _lastError = null;
    if (!isAvailable) {
      _lastError = '本地模型仅在 Android 设备上可用';
      return _lastError;
    }
    final llama = FCllama.instance();
    if (llama == null) {
      _lastError = 'fcllama 插件未初始化';
      return _lastError;
    }
    final normalizedPath = modelPath.trim();
    if (_contextId != null &&
        _loadedModelPath == normalizedPath &&
        _loadedContextSize == contextSize) {
      return null;
    }
    if (_contextId != null &&
        (_loadedModelPath != normalizedPath ||
            _loadedContextSize != contextSize)) {
      await unload();
    }
    try {
      final ctx = await llama.initContext(
        normalizedPath,
        nCtx: contextSize,
        nBatch: contextSize > 512 ? 512 : contextSize,
        nThreads: _dynamicThreads,
        useMlock: false,
        useMmap: true,
        emitLoadProgress: false,
      );
      final idStr = ctx?['contextId']?.toString() ?? '';
      final id = double.tryParse(idStr);
      if (id == null || id <= 0) {
        _lastError = '加载本地模型失败：上下文初始化未返回有效 id（${ctx ?? '空响应'}）';
        return _lastError;
      }
      _contextId = id;
      _loadedModelPath = normalizedPath;
      _loadedContextSize = contextSize;
      return null;
    } catch (e) {
      _lastError = '加载本地模型失败: $e';
      return _lastError;
    }
  }

  Future<T> _serializeCompletion<T>(Future<T> Function() action) {
    final next = _completionQueue.then((_) => action());
    _completionQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  /// 每次 completion 生成的完整文本（流式聚合）。
  Future<String> _collectCompletion(
    double contextId,
    String prompt,
    int maxTokens,
    double temperature,
  ) async {
    final buf = StringBuffer();
    await for (final token
        in _streamCompletion(contextId, prompt, maxTokens, temperature)) {
      buf.write(token);
    }
    return buf.toString();
  }

  /// 真流式：逐 token 从 onTokenStream 读取并产出。
  ///
  /// 返回 controller stream，内部在 `_completionQueue` 中串行执行
  /// completion 并实时向 controller 推送 token；首个 token 到达前不做任何
  /// 缓冲，调用方（UI）可实时展示，避免"长时间思考无输出"的假死感知。
  /// 消费者取消订阅时自动停止原生生成。
  Stream<String> _streamCompletion(
    double contextId,
    String prompt,
    int maxTokens,
    double temperature,
  ) {
    final controller = StreamController<String>();
    controller.onCancel = () async {
      await stopCompletion();
      if (!controller.isClosed) await controller.close();
    };
    unawaited(_serializeCompletion(() async {
      final llama = FCllama.instance();
      if (llama == null) {
        controller.addError(Exception('fcllama 插件未初始化'));
        if (!controller.isClosed) await controller.close();
        return;
      }
      StreamSubscription<Map<Object?, dynamic>>? sub;
      var done = false;
      try {
        final stream = llama.onTokenStream;
        if (stream != null) {
          sub = stream.listen((data) {
            if (done) return;
            if (data['function'] != 'completion') return;
            final eventContextId =
                double.tryParse(data['contextId']?.toString() ?? '');
            if (eventContextId != null && eventContextId != contextId) return;
            final res = data['result'];
            if (res is Map && res['token'] != null) {
              controller.add(res['token'].toString());
            }
          });
        }
        await llama.completion(
          contextId,
          prompt: prompt,
          nPredict: maxTokens,
          temperature: temperature,
          topP: 0.9,
          emitRealtimeCompletion: true,
        );
      } catch (e) {
        controller.addError(Exception('本地模型生成失败: $e'));
      } finally {
        done = true;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await sub?.cancel();
        if (!controller.isClosed) await controller.close();
      }
    }));
    return controller.stream;
  }

  /// 单次完整生成（流式聚合，适合短文本）。
  /// [prompt] 为完整提示词（含 system + user），返回生成的补全文本。
  /// [maxTokens] 最大生成 token 数，[temperature] 采样温度。
  Future<String> complete(
    String prompt, {
    int maxTokens = 1024,
    double temperature = 0.7,
  }) async {
    final id = _contextId;
    if (id == null) {
      return '本地模型未加载。请先在"AI 模型管理"中导入并加载 GGUF 模型。';
    }
    return _collectCompletion(id, prompt, maxTokens, temperature);
  }

  /// 流式生成：逐 token 产出补全文本（真流式）。
  Stream<String> generateStream(
    String prompt, {
    int maxTokens = 1024,
    double temperature = 0.7,
  }) async* {
    final id = _contextId;
    if (id == null) {
      yield '本地模型未加载。请先在"AI 模型管理"中导入并加载 GGUF 模型。';
      return;
    }
    yield* _streamCompletion(id, prompt, maxTokens, temperature);
  }

  /// 取消当前正在进行的生成（fcllama 原生 stop）。
  Future<void> stopCompletion() async {
    final id = _contextId;
    if (id == null) return;
    try {
      await FCllama.instance()?.stopCompletion(contextId: id);
    } catch (_) {}
  }

  /// 卸载当前模型，释放内存。
  Future<void> unload() async {
    final id = _contextId;
    _contextId = null;
    _loadedModelPath = null;
    _loadedContextSize = null;
    if (id != null) {
      try {
        await FCllama.instance()?.releaseContext(id);
      } catch (_) {}
    }
    _lastError = null;
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
