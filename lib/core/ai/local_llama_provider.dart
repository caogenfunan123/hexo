import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/local_model_settings.dart';

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
  LocalModelSettings? _loadedSettings;
  String? _lastError;
  String? _backendName;
  ({int total, int free})? _vram;
  bool _gpuFallbackToCpu = false;

  /// llama.cpp 原生 + Dart 诊断日志环形缓冲（用于手动导出定位卡点）。
  final List<String> _logRing = [];
  bool _loggingConfigured = false;
  bool _loggingEnabled = false;
  static const int _logRingCapacity = 2000;

  /// 原生日志 FFI 桥接回调（防止被 GC 回收）。
  NativeCallable<_NativeLogCallback>? _nativeLogCallable;
  String _nativeLogLine = '';

  /// 最近一次 [_fitToContext] 计算的 prompt token 数（供日志打点）。
  int _lastPromptTokens = 0;

  /// 是否开启了日志记录（默认关闭，避免 debug 日志开销）。
  bool get loggingEnabled => _loggingEnabled;

  /// 开关日志记录。开启后 llama.cpp 原生层日志写入环形缓冲，
  /// 供 [exportDiagnosticLogs] 导出定位卡点；关闭后停止写入。
  void setLoggingEnabled(bool enabled) {
    _loggingEnabled = enabled;
    if (enabled) {
      _configureLogging();
      // 立即把原生层日志级别调到 debug，避免用户开启开关但模型已加载
      // 时抓不到 info/debug 级别日志。
      if (!kIsWeb) {
        final engine = _engine;
        if (engine != null) {
          try {
            engine.setLogLevel(LlamaLogLevel.debug);
          } catch (_) {}
        }
      }
    } else {
      _logRing.clear();
    }
  }

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

  /// 是否因无 GPU / 探测失败而回退到 CPU 推理。
  bool get gpuFallbackToCpu => _gpuFallbackToCpu;

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
  /// [modelPath] 为本地 .gguf 文件绝对路径，[settings] 为本地模型完整设置
  /// （上下文、批处理、线程、KV cache、GPU 层数、后端等）；为 null 时使用
  /// 默认设置。
  ///
  /// 返回 null 表示成功，否则返回错误信息。
  Future<String?> loadModel(
    String modelPath, {
    LocalModelSettings? settings,
  }) async {
    _lastError = null;
    if (!isAvailable) {
      _lastError = '本地模型当前平台不可用';
      return _lastError;
    }
    final normalizedPath = modelPath.trim();
    // 强制钉死一组移动端已知的稳定配置：Android 上 mlock 无权限会导致
    // 生成阶段异常；非 F16 KV cache / flash attention / kv_unified 在部分
    // CPU 设备上会卡 prefill。此处无条件覆盖为 llama.cpp 最稳默认，
    // 避免用户在设置面板误开后再次触发"发送消息后无回复"。
    final raw = settings ?? const LocalModelSettings();
    final effective = raw.copyWith(
      useMlock: false,
      cacheTypeK: 'f16',
      cacheTypeV: 'f16',
      flashAttention: 'auto',
      kvUnified: true,
    );
    if (isModelLoaded &&
        _loadedModelPath == normalizedPath &&
        _sameSettings(_loadedSettings, effective)) {
      return null;
    }
    if (isModelLoaded &&
        (_loadedModelPath != normalizedPath ||
            !_sameSettings(_loadedSettings, effective))) {
      await unload();
    }
    try {
      final engine = _engine ??= LlamaEngine(LlamaBackend());

      // 仅在用户开启「诊断日志」开关时才设置原生层 debug 级别并捕获；
      // 默认关闭，避免 debug 日志影响正式体验。
      if (_loggingEnabled && !kIsWeb) {
        _configureLogging();
        try {
          await engine.setLogLevel(LlamaLogLevel.debug);
        } catch (_) {}
      }

      // 设备选择：
      // - auto：Android 上默认 CPU。llamadart 在 Android 上把 auto 强制解析
      //   为 CPU（官方为避开不稳定 Vulkan 驱动栈），而 engine.isGpuSupported()
      //   只是编译期特性检查，不代表真机 Vulkan 可用；一旦据此强制走 Vulkan，
      //   部分设备会在 ggml 加载模型张量时原生层空函数指针崩溃（SIGSEGV）。
      //   android 上仅显式选择 vulkan 才尝试 GPU；桌面/其他平台保留探测逻辑。
      // - vulkan：显式选择时仍做真实设备枚举（listGpuDevices），枚举不到
      //   Vulkan 设备则回退 CPU，避免把不存在的后端传给 llama.cpp。
      var useGpu = effective.isVulkan;
      _gpuFallbackToCpu = false;
      if (effective.isAuto) {
        if (!kIsWeb && Platform.isAndroid) {
          useGpu = false;
        } else {
          try {
            useGpu = await engine.isGpuSupported();
          } catch (_) {
            useGpu = false;
          }
        }
        if (!useGpu) _gpuFallbackToCpu = true;
      } else if (useGpu) {
        if (!await _hasRealVulkanDevice(engine)) {
          useGpu = false;
          _gpuFallbackToCpu = true;
        }
      } else {
        _gpuFallbackToCpu = true;
      }
      final gpuLayers = useGpu
          ? (effective.gpuLayers > 0
                ? effective.gpuLayers
                : ModelParams.maxGpuLayers)
          : 0;

      var modelParams = ModelParams(
        contextSize: effective.effectiveContextSize,
        gpuLayers: gpuLayers,
        preferredBackend: useGpu ? GpuBackend.vulkan : GpuBackend.cpu,
        numberOfThreads: effective.threads > 0
            ? effective.threads
            : _dynamicThreads,
        numberOfThreadsBatch:
            effective.threadsBatch > 0 ? effective.threadsBatch : 0,
        batchSize: effective.batchSize,
        microBatchSize: effective.microBatchSize,
        maxParallelSequences: effective.maxParallelSequences,
        useMmap: effective.useMmap,
        useMlock: effective.useMlock,
        flashAttention: _mapFlashAttention(effective.flashAttention),
        cacheTypeK: _mapKvCacheType(effective.cacheTypeK),
        cacheTypeV: _mapKvCacheType(effective.cacheTypeV),
        kvUnified: effective.kvUnified,
        chatTemplate: effective.chatTemplate,
      );
      try {
        modelParams.validate();
      } catch (_) {
        // llama.cpp 不允许非 F16 KV cache + flash attention 禁用；此处兜底：
        // 强制打开 flash attention，避免参数校验失败导致加载崩溃。
        modelParams = modelParams.copyWith(flashAttention: FlashAttention.enabled);
      }
      final loadT0 = DateTime.now();
      _pushLog(
        '[DART] 开始加载模型: $normalizedPath, '
        'backend=${modelParams.preferredBackend.name}, gpuLayers=${modelParams.gpuLayers}',
      );
      try {
        await engine.loadModel(normalizedPath, modelParams: modelParams);
      } catch (e) {
        // GPU 加载失败（驱动/后端异常）时自动回退 CPU 重试，避免设备上
        // 直接中断；llamadart 在加载失败后会清理内部加载状态，可安全重入。
        if (useGpu && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          _gpuFallbackToCpu = true;
          modelParams = modelParams.copyWith(
            gpuLayers: 0,
            preferredBackend: GpuBackend.cpu,
          );
          _pushLog('[DART] GPU 加载失败，回退 CPU 重试: $e');
          try {
            await engine.loadModel(normalizedPath, modelParams: modelParams);
          } catch (e2) {
            _lastError = '加载本地模型失败: $e（GPU 回退 CPU 仍失败: $e2）';
            _pushLog('[DART] 加载最终失败: $_lastError');
            return _lastError;
          }
        } else {
          _pushLog('[DART] 加载失败: $e');
          rethrow;
        }
      }
      _pushLog(
        '[DART] 模型加载成功, 耗时=${DateTime.now().difference(loadT0).inMilliseconds}ms',
      );
      _loadedModelPath = normalizedPath;
      _loadedSettings = effective;
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

  /// 配置 llamadart 日志写入环形缓冲（幂等，只配置一次）。
  ///
  /// 通过 [LlamaEngine.configureLogging] 挂 handler 捕获 Dart 侧日志；
  /// 再通过 FFI 直接调用 `llama_log_set` 注册原生回调，把 llama.cpp
  /// 的原生 stderr 日志（后端注册、张量加载、prefill、解码、线程等）
  /// 一并写入环形缓冲，弥补 llamadart 未桥接原生层日志的盲区。
  void _configureLogging() {
    if (_loggingConfigured) return;
    _loggingConfigured = true;
    try {
      LlamaEngine.configureLogging(
        level: LlamaLogLevel.debug,
        handler: (record) {
          _pushLog('[${record.level.name.toUpperCase()}] ${record.message}');
        },
      );
    } catch (_) {}
    _installNativeLogBridge();
  }

  /// 通过 FFI 调用 llama.cpp 的 `llama_log_set`，把原生层日志写入缓冲。
  ///
  /// llamadart 只在 bindings 里声明 `llama_log_set` 却不调用，导致原生
  /// 日志只进 Android stderr/logcat。这里用 [DynamicLibrary.open] 复用
  /// 已加载的 `libllamadart.so`（同名 SONAME 返回同一句柄），lookup 出
  /// `llama_log_set` 符号并注册回调。回调需长期存活，存入字段防 GC。
  void _installNativeLogBridge() {
    if (!_loggingEnabled) return;
    if (_nativeLogCallable != null) return;
    // llamadart 原生库的实际文件名因平台/打包布局而异，逐一尝试打开，
    // 取第一个能 lookup 到 llama_log_set 的句柄。
    const candidates = [
      'libllamadart.so',
      'libllamadart.so.0',
      'libllama.so',
      'libllama.so.0',
    ];
    Object? lastError;
    for (final name in candidates) {
      try {
        final lib = DynamicLibrary.open(name);
        // llama_log_set 返回 ggml_log_callback（旧回调），参数为
        // (ggml_log_callback log_callback, void* user_data)。
        final setLog = lib.lookupFunction<
            Pointer<NativeFunction<_NativeLogCallback>> Function(
              Pointer<NativeFunction<_NativeLogCallback>>,
              Pointer<Void>,
            ),
            Pointer<NativeFunction<_NativeLogCallback>> Function(
              Pointer<NativeFunction<_NativeLogCallback>>,
              Pointer<Void>,
            )>('llama_log_set');
        _nativeLogCallable =
            NativeCallable<_NativeLogCallback>.listener(_nativeLogSink);
        setLog(_nativeLogCallable!.nativeFunction, nullptr);
        _pushLog('[NATIVE] 原生日志桥接已挂载（$name）');
        return;
      } catch (e) {
        lastError = e;
      }
    }
    _pushLog('[NATIVE] 原生日志桥接挂载失败: $lastError');
  }

  /// 原生日志回调入口（来自 llama.cpp 工作线程，经 NativeCallable 调度到
  /// 本 isolate 事件队列）。text 为以 '\0' 结尾的 C 字符串，逐条累积到
  /// 当前行，遇到换行再推入缓冲（llama.cpp 常分多次回调同一行日志）。
  void _nativeLogSink(int level, Pointer<Utf8> text, Pointer<Void> userData) {
    if (!_loggingEnabled) return;
    try {
      final chunk = text.toDartString();
      _nativeLogLine += chunk;
      final nl = _nativeLogLine.indexOf('\n');
      if (nl >= 0) {
        final line = _nativeLogLine.substring(0, nl).trimRight();
        if (line.isNotEmpty) {
          final levelName = switch (level) {
            1 => 'DEBUG',
            2 => 'INFO',
            3 => 'WARN',
            4 => 'ERROR',
            _ => 'NATIVE',
          };
          _pushLog('[$levelName] $line');
        }
        _nativeLogLine = _nativeLogLine.substring(nl + 1);
      }
    } catch (_) {}
  }

  /// 写入一条带时间戳的日志到环形缓冲。
  void _pushLog(String line) {
    _logRing.add('[${DateTime.now().toIso8601String()}] $line');
    if (_logRing.length > _logRingCapacity) {
      _logRing.removeRange(0, _logRing.length - _logRingCapacity);
    }
  }

  /// 导出诊断日志到 `{modelsDir}/llama_diag_log.txt`，返回导出文件路径。
  ///
  /// 日志内容包含：设备/平台/系统信息、存储与内存、模型文件信息、
  /// 已加载设置、GPU 枚举结果，以及 llama.cpp 原生 + Dart 环形缓冲日志。
  /// 用于在真机上"卡住加载不出来对话"时定位卡点（后端注册、张量分配、
  /// prefill、线程等）。
  Future<String?> exportDiagnosticLogs() async {
    try {
      final buf = StringBuffer();
      buf.writeln('===== Hexo 本地模型诊断日志 =====');
      buf.writeln('导出时间: ${DateTime.now().toIso8601String()}');
      buf.writeln('平台: ${defaultTargetPlatform.name}');
      buf.writeln('日志记录开关: ${_loggingEnabled ? '开' : '关'}');
      if (!_loggingEnabled) {
        buf.writeln('');
        buf.writeln('>>> 提示：诊断日志开关为「关」，以下仅有设备信息。');
        buf.writeln('>>> 请先开启「记录诊断日志」开关，重新加载模型/复现卡顿，');
        buf.writeln('>>> 再回到此处导出，才能包含 llama.cpp 原生加载日志。');
      }

      // 系统与设备信息
      buf.writeln();
      buf.writeln('===== 系统信息 =====');
      if (!kIsWeb) {
        try {
          buf.writeln('操作系统: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
        } catch (_) {}
        try {
          buf.writeln('CPU 核心数: ${Platform.numberOfProcessors}');
        } catch (_) {}
        try {
          buf.writeln('操作系统架构: ${Platform.version}');
        } catch (_) {}
        try {
          final fs = await _modelFileInfo(_loadedModelPath);
          buf.writeln(fs);
        } catch (_) {}
      }

      // 模型与推理状态
      buf.writeln();
      buf.writeln('===== 模型与推理状态 =====');
      buf.writeln('已加载模型: ${_loadedModelPath ?? '（无）'}');
      buf.writeln('后端: ${_backendName ?? '（未知）'}');
      buf.writeln('GPU 回退 CPU: $_gpuFallbackToCpu');
      buf.writeln('最近错误: ${_lastError ?? '（无）'}');
      if (_loadedSettings != null) {
        buf.writeln('设置: ${_loadedSettings!.toJson()}');
      }
      if (!kIsWeb) {
        final engine = _engine;
        if (engine != null) {
          try {
            final devices = await _safeEngineCall(
              () => engine.listGpuDevices(),
            );
            if (devices != null && devices.isNotEmpty) {
              buf.writeln('GPU 设备枚举:');
              for (final d in devices) {
                buf.writeln('  - ${d.backend.name}: ${d.name}');
              }
            } else {
              buf.writeln('GPU 设备枚举: （无可用设备，走 CPU）');
            }
          } catch (_) {}
        } else {
          buf.writeln('GPU 设备枚举: （引擎未初始化）');
        }
      }

      buf.writeln();
      buf.writeln('===== llama.cpp 日志（最近 ${_logRing.length} 条）=====');
      if (_logRing.isEmpty) {
        buf.writeln('（无日志，请先触发一次模型加载/对话后再导出）');
      } else {
        for (final line in _logRing) {
          buf.writeln(line);
        }
      }

      final root = await _storageRoot();
      final dir = Directory('$root/models');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/llama_diag_log.txt');
      await file.writeAsString(buf.toString());
      return file.path;
    } catch (e) {
      return '导出失败: $e';
    }
  }

  /// 执行引擎调用并吞掉异常（枚举/信息接口在部分后端可能不可用）。
  Future<T?> _safeEngineCall<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }

  /// 收集已加载模型文件的大小/路径信息（用于确认模型文件本身是否完整）。
  Future<String> _modelFileInfo(String? path) async {
    if (path == null || path.isEmpty) return '模型文件: （无）';
    try {
      final f = File(path);
      if (await f.exists()) {
        final bytes = await f.length();
        final mb = bytes / (1024 * 1024);
        return '模型文件: $path（${mb.toStringAsFixed(1)} MB）';
      }
      return '模型文件: $path（文件不存在！）';
    } catch (_) {
      return '模型文件: $path（读取失败）';
    }
  }

  Future<String> _storageRoot() async {
    try {
      // 与 GgufModelService 共用同一存储根目录；通过 path_provider 获取
      // 移动端应用文件目录（Android getFilesDir），桌面端应用支持目录。
      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        final appDir = await getApplicationSupportDirectory();
        return '${appDir.path}/hexo_blog_manager';
      }
    } catch (_) {}
    try {
      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        return dir.path;
      }
    } catch (_) {}
    return '.';
  }

  /// 两次设置是否完全一致（决定是否复用已加载模型）。
  bool _sameSettings(
    LocalModelSettings? a,
    LocalModelSettings b,
  ) {
    if (a == null) return false;
    return a.toJson().toString() == b.toJson().toString();
  }

  /// 运行时探测是否存在真实可用的 Vulkan 设备。
  ///
  /// [LlamaBackend.isGpuSupported] 只反映编译期是否包含 GPU 后端（等价于
  /// llama.cpp 的 `llama_supports_gpu_offload`），无法证明当前设备驱动可用。
  /// 这里改用 `listGpuDevices(probeBackends: [vulkan])` 做真实设备枚举，
  /// 只有枚举到 Vulkan 设备才允许走 GPU 路径；枚举不到就回退 CPU，从源头
  /// 规避 ggml 在加载模型张量时的空函数指针原生崩溃。
  Future<bool> _hasRealVulkanDevice(LlamaEngine engine) async {
    try {
      final devices = await engine.listGpuDevices(
        probeBackends: const [GpuBackend.vulkan],
      );
      return devices.any((d) => d.backend == GpuBackend.vulkan);
    } catch (_) {
      return false;
    }
  }

  /// 映射 flash attention 字符串到 llamadart 枚举。
  FlashAttention _mapFlashAttention(String value) {
    switch (value) {
      case 'enabled':
        return FlashAttention.enabled;
      case 'disabled':
        return FlashAttention.disabled;
      default:
        return FlashAttention.auto;
    }
  }

  /// 映射 KV cache 类型字符串到 llamadart 枚举。
  KvCacheType _mapKvCacheType(String value) {
    switch (value) {
      case 'q8_0':
        return KvCacheType.q8_0;
      case 'q4_0':
        return KvCacheType.q4_0;
      default:
        return KvCacheType.f16;
    }
  }

  /// 单次完整生成（流式聚合，适合短文本）。
  /// [prompt] 为完整提示词（含 system + user），返回生成的补全文本。
  /// [settings] 提供采样参数（maxTokens/temperature/top_k/top_p/min_p/
  /// 惩罚/停止词）；为 null 时使用当前已加载模型的设置（或默认值）。
  Future<String> complete(
    String prompt, {
    LocalModelSettings? settings,
    int? maxTokens,
    double? temperature,
  }) async {
    final engine = _engine;
    if (engine == null || !engine.isReady) {
      return '本地模型未加载。请先在"AI 模型管理"中导入并加载 GGUF 模型。';
    }
    final s = settings ?? _loadedSettings ?? const LocalModelSettings();
    final maxOut = maxTokens ?? s.maxTokens;
    final fit = await _fitToContext(prompt, maxOut);
    if (fit.error != null) {
      return fit.error!;
    }
    final buf = StringBuffer();
    await for (final token in engine.generate(
      prompt,
      params: _generationParams(
        s,
        maxTokens: fit.maxTokens,
        temperature: temperature,
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
    final contextSize = _loadedSettings?.effectiveContextSize ?? 2048;
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
    _lastPromptTokens = promptTokens;
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
    // n_predict = -1（无限）：用满上下文剩余空间，直到 EOS 才停止。
    final target = maxTokens <= 0 ? roomForOutput : maxTokens;
    final effective = target > roomForOutput
        ? (roomForOutput < 16 ? 16 : roomForOutput)
        : target;
    return (error: null, maxTokens: effective);
  }

  /// 从 [LocalModelSettings] 构造 llamadart [GenerationParams]。
  /// [maxTokens] / [temperature] 非空时覆盖设置中的对应值。
  GenerationParams _generationParams(
    LocalModelSettings s, {
    int? maxTokens,
    double? temperature,
  }) {
    return GenerationParams(
      maxTokens: maxTokens ?? s.maxTokens,
      temp: temperature ?? s.temperature,
      topK: s.topK,
      topP: s.topP,
      minP: s.minP,
      penalty: s.repeatPenalty,
      presencePenalty: s.presencePenalty,
      seed: s.seed,
      stopSequences: s.stopSequences,
    );
  }

  /// 流式生成：逐 token 产出补全文本（真流式）。
  ///
  /// 基于 llamadart `engine.generate` → `Stream<String>`，每个 token 立即
  /// 产出，首个 token 到达前不做任何缓冲；调用方（UI）可实时展示。
  ///
  /// 在生成前/首 token/结束各阶段写入诊断日志（[generateStream] 的 Dart 侧
  /// 打点），即使原生桥接不可用，也能定位到"卡在 prefill 还是 decode"。
  Stream<String> generateStream(
    String prompt, {
    LocalModelSettings? settings,
    int? maxTokens,
    double? temperature,
  }) async* {
    final engine = _engine;
    if (engine == null || !engine.isReady) {
      yield '本地模型未加载。请先在"AI 模型管理"中导入并加载 GGUF 模型。';
      return;
    }
    final s = settings ?? _loadedSettings ?? const LocalModelSettings();
    final maxOut = maxTokens ?? s.maxTokens;
    final t0 = DateTime.now();
    _pushLog('[DART] 生成开始 prompt=${prompt.length} 字符, maxTokens=$maxOut');
    final fit = await _fitToContext(prompt, maxOut);
    if (fit.error != null) {
      _pushLog('[DART] 生成中止: ${fit.error}');
      yield fit.error!;
      return;
    }
    _pushLog(
      '[DART] _fitToContext 完成: promptTokens=${_lastPromptTokens}'
      ', 输出预算=${fit.maxTokens}, 耗时=${DateTime.now().difference(t0).inMilliseconds}ms',
    );
    final params = _generationParams(
      s,
      maxTokens: fit.maxTokens,
      temperature: temperature,
    );
    _pushLog('[DART] 提交 llama.cpp 生成 (engine.generate)...');
    var count = 0;
    final firstStart = DateTime.now();
    await for (final token in engine.generate(prompt, params: params)) {
      if (count == 0) {
        _pushLog(
          '[DART] 首个 token 到达: 耗时=${DateTime.now().difference(firstStart).inMilliseconds}ms',
        );
      }
      count++;
      yield token;
    }
    _pushLog(
      '[DART] 生成结束: 共 $count token, 总耗时='
      '${DateTime.now().difference(t0).inMilliseconds}ms',
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
    _loadedSettings = null;
    _gpuFallbackToCpu = false;
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
    _loadedSettings = null;
    _gpuFallbackToCpu = false;
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (_) {}
    }
    _nativeLogCallable?.close();
    _nativeLogCallable = null;
    _nativeLogLine = '';
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
  bool canFit(int tokenCount, {int contextSize = 2048}) =>
      tokenCount <= contextSize;
}

/// llama.cpp `llama_log_set` 回调签名：
/// `void callback(ggml_log_level level, const char * text, void * user_data)`
typedef _NativeLogCallback = Void Function(
  Uint32 level,
  Pointer<Utf8> text,
  Pointer<Void> userData,
);