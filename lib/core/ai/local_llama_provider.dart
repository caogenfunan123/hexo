import 'dart:async';

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
  String? _lastError;

  StreamSubscription<Map<Object?, dynamic>>? _tokenSub;

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
    try {
      final ctx = await llama.initContext(
        modelPath,
        nCtx: contextSize,
        nBatch: contextSize,
        nThreads: 4,
        useMlock: true,
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
      _listenTokens();
      return null;
    } catch (e) {
      _lastError = '加载本地模型失败: $e';
      return _lastError;
    }
  }

  /// 订阅流式 token（fcllama 通过 event channel 推送）。
  void _listenTokens() {
    _tokenSub?.cancel();
    _tokenSub = FCllama.instance()?.onTokenStream?.listen((data) {
      if (data['function'] != 'completion') return;
      final res = data['result'];
      if (res is Map && res['token'] != null) {
        _tokenCtrl.add(res['token'].toString());
      }
    });
  }

  final _tokenCtrl = StreamController<String>.broadcast(sync: false);

  /// 每次 completion 生成的完整文本（流式聚合）。
  Future<String> _collectCompletion(
    double contextId,
    String prompt,
    int maxTokens,
    double temperature,
  ) async {
    final buf = StringBuffer();
    final sub = _tokenCtrl.stream.listen(buf.write);
    try {
      await FCllama.instance()?.completion(
        contextId,
        prompt: prompt,
        nPredict: maxTokens,
        temperature: temperature,
        topP: 0.9,
        emitRealtimeCompletion: true,
      );
    } catch (e) {
      buf.write('本地模型生成失败: $e');
    } finally {
      // 等事件通道 flush 一下
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await sub.cancel();
    }
    return buf.toString();
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

  /// 流式生成：逐 token 产出补全文本。
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
    // fcllama 通过 event channel 推流，这里直接监听 token 并透传
    final buf = StringBuffer();
    final sub = _tokenCtrl.stream.listen(buf.write);
    try {
      await FCllama.instance()?.completion(
        id,
        prompt: prompt,
        nPredict: maxTokens,
        temperature: temperature,
        topP: 0.9,
        emitRealtimeCompletion: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // 吐出聚合结果（避免因未关闭广播流而死等）
      if (buf.isEmpty) return;
      yield buf.toString();
    } catch (e) {
      yield '本地模型生成失败: $e';
    } finally {
      await sub.cancel();
    }
  }

  /// 卸载当前模型，释放内存。
  Future<void> unload() async {
    final id = _contextId;
    _contextId = null;
    await _tokenSub?.cancel();
    _tokenSub = null;
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
