import 'dart:async';

import '../../models/ai_profile.dart';
import '../../models/app_settings.dart';
import '../../services/ai_service.dart';
import '../../services/storage_service.dart';
import '../../services/usage_tracker.dart';
import '../../services/volcengine_adapter.dart';
import '../tools/tool_executor.dart';
import '../tools/tool_registry.dart';
import 'ai_model_entity.dart';
import 'ai_model_manager.dart';
import 'ai_model_probe_service.dart';

/// 模型切换事件（UI 提示条用）
class SwitchEvent {
  final String fromModel;
  final String toModel;
  final String reason;
  final int attempt;
  final DateTime time;

  SwitchEvent({
    required this.fromModel,
    required this.toModel,
    required this.reason,
    required this.attempt,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}

/// 请求调度器：超时监听、故障自动切换备选模型、完整上下文继承、非流式 MCP 工具调用循环
class AiRequestDispatcher {
  final AiService _aiService;
  final AiModelManager _modelManager;
  final AiModelProbeService _probeService;
  StreamController<StreamChunk>? _activeStreamController;

  /// 模型切换事件回调（UI 展示提示条）
  void Function(SwitchEvent event)? onModelSwitched;

  AiRequestDispatcher(this._aiService, this._modelManager)
      : _probeService = AiModelProbeService(_modelManager);

  /// 取消当前正在进行的请求
  void cancelCurrent() {
    _activeStreamController?.close();
    _activeStreamController = null;
  }

  /// 上下文持有器：保存完整会话历史（含 tool_calls），保证切换模型时上下文不丢失
  final List<Map<String, dynamic>> _chatHistory = [];
  String _systemPrompt = '';

  List<Map<String, dynamic>> get chatHistory => List.unmodifiable(_chatHistory);

  void restoreHistory(List<Map<String, dynamic>> history) {
    _chatHistory.clear();
    _chatHistory.addAll(history);
  }

  void setSystemPrompt(String prompt) {
    _systemPrompt = prompt;
  }

  void addUserMessage(String content) {
    _chatHistory.add({'role': 'user', 'content': content});
  }

  void addAssistantMessage(String content) {
    _chatHistory.add({'role': 'assistant', 'content': content});
  }

  void clearHistory() {
    _chatHistory.clear();
  }

  /// 分发 AI 请求（非流式 HTTP POST，通过 Stream<StreamChunk> 兼容旧接口）
  Stream<StreamChunk> dispatchStream({
    required AppSettings settings,
    required String userMessage,
    AiModelEntity? preferredModel,
    double temperature = 0.7,
    bool autoOptimal = true,
    int? timeoutSeconds,
    int? maxSwitchCount,
  }) {
    // 取消之前的请求
    cancelCurrent();

    addUserMessage(userMessage);

    final controller = StreamController<StreamChunk>();
    _activeStreamController = controller;

    // 异步构建备选队列并启动处理
    _prepareAndRunStream(
      controller,
      settings: settings,
      preferredModel: preferredModel,
      temperature: temperature,
      autoOptimal: autoOptimal,
      timeoutSeconds: timeoutSeconds,
      maxSwitchCount: maxSwitchCount,
    );

    return controller.stream;
  }

  Future<void> _prepareAndRunStream(
    StreamController<StreamChunk> controller, {
    required AppSettings settings,
    AiModelEntity? preferredModel,
    double temperature = 0.7,
    bool autoOptimal = true,
    int? timeoutSeconds,
    int? maxSwitchCount,
  }) async {
    List<AiModelEntity> fallbacks = [];
    try {
      if (autoOptimal) {
        fallbacks = await _probeService.getPriorityQueue();
      } else {
        fallbacks = await _modelManager.getEnabled();
      }
    } catch (_) {
      fallbacks = await _modelManager.getEnabled();
    }

    final effectiveTimeout =
        timeoutSeconds ?? settings.ai.aiRequestTimeoutSec;
    final effectiveMaxSwitch = maxSwitchCount ?? settings.ai.aiMaxSwitchCount;

    await _runStream(
      controller,
      settings: settings,
      preferredModel: preferredModel,
      temperature: temperature,
      fallbackModels: fallbacks,
      maxSwitchCount: effectiveMaxSwitch,
      timeoutSeconds: effectiveTimeout,
    );
  }

  Future<void> _runStream(
    StreamController<StreamChunk> controller, {
    required AppSettings settings,
    AiModelEntity? preferredModel,
    double temperature = 0.7,
    int toolRound = 0,
    List<AiModelEntity> fallbackModels = const [],
    int maxSwitchCount = 3,
    int timeoutSeconds = 50,
    int switchCount = 0,
    bool disableTools = false,
  }) async {
    const maxToolRounds = 5;
    final fullContent = StringBuffer();

    try {
      AiProfile? profile;
      if (preferredModel != null) {
        profile = _profileFromModel(preferredModel);
      }

      final messages = [
        {'role': 'system', 'content': _systemPrompt},
        ..._chatHistory,
      ];

      final tools = !disableTools && ToolRegistry().enabledTools.isNotEmpty
          ? ToolRegistry().toOpenAiTools()
          : null;

      final stopwatch = Stopwatch()..start();
      try {
        final response = await _aiService
            .completeWithTools(
              settings: settings,
              systemPrompt: _systemPrompt,
              messages: messages,
              profile: profile,
              tools: tools,
              temperature: temperature,
              toolRound: toolRound,
            )
            .timeout(Duration(seconds: timeoutSeconds));

        stopwatch.stop();
        _recordStreamCall(preferredModel, stopwatch, true);
        await _recordUsage(profile, response);

        if (controller.isClosed) return;

        if (response.hasToolCalls && toolRound < maxToolRounds) {
          final assistantMsg = response.allMessages.last;
          if (assistantMsg['role'] == 'assistant' && assistantMsg['tool_calls'] != null) {
            _chatHistory.add(Map<String, dynamic>.from(assistantMsg));
          }

          final toolExecutor = ToolExecutor();
          final results = await toolExecutor.executeAll(response.toolCalls!);

          final toolResults = ToolExecutor.formatToolResultsForAi(
            response.toolCalls!,
            results,
          );
          for (final tr in toolResults) {
            _chatHistory.add(Map<String, dynamic>.from(tr));
          }

          final toolNames = response.toolCalls!
              .map((tc) => tc.toolId)
              .where((n) => n.isNotEmpty)
              .join(', ');
          if (toolNames.isNotEmpty) {
            controller.add(StreamChunk(content: '正在使用工具: $toolNames...\n'));
          }

          await _runStream(
            controller,
            settings: settings,
            preferredModel: preferredModel,
            temperature: temperature,
            toolRound: toolRound + 1,
            fallbackModels: fallbackModels,
            maxSwitchCount: maxSwitchCount,
            timeoutSeconds: timeoutSeconds,
            switchCount: switchCount,
          );
          return;
        }

        if (response.content != null && response.content!.isNotEmpty) {
          fullContent.write(response.content);
          controller.add(StreamChunk(content: response.content!));
        }

        if (fullContent.isNotEmpty) {
          addAssistantMessage(fullContent.toString());
        }

        if (!controller.isClosed) {
          controller.add(const StreamChunk(content: '', isDone: true));
          await controller.close();
        }
      } on TimeoutException {
        stopwatch.stop();
        _recordStreamCall(preferredModel, stopwatch, false);
        throw Exception('请求超时（${timeoutSeconds}秒）');
      } catch (e) {
        stopwatch.stop();
        _recordStreamCall(preferredModel, stopwatch, false);
        rethrow;
      }
    } catch (e) {
      final errorMsg = e.toString();

      if (errorMsg.contains('HTTP 400') || errorMsg.contains('InvalidParameter')) {
        final isVolcengine = preferredModel != null
            ? VolcengineAdapter.isVolcengineArk(preferredModel.apiBase)
            : false;
        if (isVolcengine && toolRound == 0) {
          onModelSwitched?.call(SwitchEvent(
            fromModel: preferredModel.modelName,
            toModel: preferredModel.modelName,
            reason: '火山方舟参数不兼容，降级为无工具模式重试',
            attempt: switchCount + 1,
          ));
          await _runStream(
            controller,
            settings: settings,
            preferredModel: preferredModel,
            temperature: temperature,
            toolRound: toolRound,
            fallbackModels: fallbackModels,
            maxSwitchCount: maxSwitchCount,
            timeoutSeconds: timeoutSeconds,
            switchCount: switchCount + 1,
            disableTools: true,
          );
          return;
        }
      }

      if (switchCount < maxSwitchCount && fallbackModels.isNotEmpty) {
        final next = _pickNextModel(preferredModel, fallbackModels);
        if (next != null) {
          onModelSwitched?.call(SwitchEvent(
            fromModel: preferredModel?.modelName ?? '当前模型',
            toModel: next.modelName,
            reason: '请求失败（$errorMsg）',
            attempt: switchCount + 1,
          ));
          await _runStream(
            controller,
            settings: settings,
            preferredModel: next,
            temperature: temperature,
            toolRound: toolRound,
            fallbackModels: fallbackModels,
            maxSwitchCount: maxSwitchCount,
            timeoutSeconds: timeoutSeconds,
            switchCount: switchCount + 1,
          );
          return;
        }
      }

      if (!controller.isClosed) {
        controller.addError(Exception(errorMsg));
        await controller.close();
      }
    }
  }

  /// 记录单次流式调用（成功/失败）到模型管理器，供择优评分
  void _recordStreamCall(    AiModelEntity? model,
    Stopwatch stopwatch,
    bool success,
  ) {
    if (model == null) return;
    _modelManager.recordCall(
      model.modelId,
      model.apiBase,
      stopwatch.elapsedMilliseconds,
      success,
    );
  }

  /// 记录 token 用量（对标 MonkeyCode usage_capture）
  Future<void> _recordUsage(AiProfile? profile, ToolCallResponse response) async {
    final usage = response.usage;
    if (usage == null) return;
    if (profile == null) return;
    try {
      final tracker = UsageTracker(await StorageService().root);
      await tracker.record(TokenUsage(
        id: 'usage_${DateTime.now().microsecondsSinceEpoch}',
        time: DateTime.now(),
        model: profile.model,
        provider: profile.interfaceType.name,
        inputTokens: (usage['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (usage['outputTokens'] as num?)?.toInt() ?? 0,
        cacheReadTokens: (usage['cacheReadTokens'] as num?)?.toInt() ?? 0,
        cacheCreationTokens: (usage['cacheCreationTokens'] as num?)?.toInt() ?? 0,
        reasoningTokens: (usage['reasoningTokens'] as num?)?.toInt() ?? 0,
        usedTools: response.hasToolCalls,
      ));
    } catch (_) {
      // 用量记录失败不影响主流程
    }
  }

  /// 从备选队列挑选下一个模型（跳过当前模型）
  AiModelEntity? _pickNextModel(
    AiModelEntity? current,
    List<AiModelEntity> fallbacks,
  ) {
    if (current == null) {
      return fallbacks.isEmpty ? null : fallbacks.first;
    }
    for (final m in fallbacks) {
      if (m.modelId != current.modelId) return m;
    }
    return null;
  }

  /// 完整的请求分发：自动故障切换
  /// 返回 {content, usedModel, switched}
  Future<DispatchResult> dispatch({
    required AppSettings settings,
    required String userMessage,
    AiModelEntity? preferredModel,
    AiProfile? preferredProfile,
    double temperature = 0.7,
    int maxRetries = 3,
    bool enableAutoSwitch = true,
    bool autoOptimal = true,
    int timeoutSeconds = 50,
    bool Function(String)? isRetryableError,
  }) async {
    addUserMessage(userMessage);

    // 构建备选模型队列（自动择优时按探测优先级排序）
    final fallbackModels = enableAutoSwitch
        ? await _probeService.getPriorityQueue(
            autoOptimal: autoOptimal,
          )
        : <AiModelEntity>[];

    // 当前尝试的模型
    AiModelEntity? currentModel = preferredModel;
    int attemptIndex = 0;
    String? lastError;

    final stopwatch = Stopwatch();
    while (attemptIndex <= maxRetries) {
      try {
        // 确定当前使用的 profile
        AiProfile? profile;
        if (currentModel != null) {
          profile = _profileFromModel(currentModel);
        } else if (preferredProfile != null) {
          profile = preferredProfile;
        }

        // 构建完整消息列表
        final messages = [
          {'role': 'system', 'content': _systemPrompt},
          ..._chatHistory,
        ];

        stopwatch.reset();
        stopwatch.start();
        final result = await _aiService
            .complete(
              settings: settings,
              systemPrompt: _systemPrompt,
              userPrompt: _buildMessagesString(messages),
              profile: profile,
              temperature: temperature,
            )
            .timeout(
              Duration(seconds: currentModel?.timeoutSecond ?? timeoutSeconds),
            );
        stopwatch.stop();

        // 记录响应速度
        if (currentModel != null) {
          _modelManager.recordCall(
            currentModel.modelId,
            currentModel.apiBase,
            stopwatch.elapsedMilliseconds,
            true,
          );
        }

        addAssistantMessage(result);
        return DispatchResult(
          content: result,
          usedModel: currentModel?.modelId ?? (profile?.model ?? 'default'),
          switched: attemptIndex > 0,
          attempts: attemptIndex + 1,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      } catch (e) {
        lastError = e.toString();
        attemptIndex++;
        stopwatch.stop();

        // 记录失败
        if (currentModel != null) {
          _modelManager.recordCall(
            currentModel.modelId,
            currentModel.apiBase,
            stopwatch.elapsedMilliseconds,
            false,
          );
        }

        // 判断是否可重试
        if (isRetryableError != null && !isRetryableError(lastError)) {
          break;
        }

        // 自动选取下一个备选模型
        if (enableAutoSwitch && fallbackModels.isNotEmpty) {
          // 移除当前模型
          if (currentModel != null) {
            fallbackModels.removeWhere(
              (m) => m.modelId == currentModel!.modelId &&
                m.apiBase == currentModel.apiBase,
            );
          }
          if (fallbackModels.isEmpty) break;
          // 找优先级最高的
          final nextModel = fallbackModels.first;
          // 触发切换事件
          if (currentModel != null) {
            onModelSwitched?.call(SwitchEvent(
              fromModel: currentModel.modelName,
              toModel: nextModel.modelName,
              reason: '响应超时或请求失败（$lastError）',
              attempt: attemptIndex,
            ));
          }
          currentModel = nextModel;
        } else {
          break;
        }
      }
    }

    throw DispatchException(
      '所有模型请求失败（尝试了 ${attemptIndex} 次）\n最后错误: $lastError',
      lastError: lastError,
      attempts: attemptIndex,
    );
  }

  /// 简单单次请求（不切换模型，不带历史）
  Future<String> singleRequest({
    required AppSettings settings,
    required String systemPrompt,
    required String userPrompt,
    AiProfile? profile,
    double temperature = 0.7,
    int timeoutSeconds = 30,
  }) async {
    return _aiService
        .complete(
          settings: settings,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          profile: profile,
          temperature: temperature,
        )
        .timeout(Duration(seconds: timeoutSeconds));
  }

  /// 从模型实体构造 AiProfile（携带接口类型）
  AiProfile _profileFromModel(AiModelEntity m) {
    return AiProfile(
      id: m.modelId,
      name: m.modelName,
      baseUrl: m.apiBase,
      apiKey: m.apiKey,
      model: m.modelId,
      apiPath: m.apiPath,
      useBearer: m.useBearer,
      interfaceType: m.interfaceType,
    );
  }

  String _buildMessagesString(List<Map<String, dynamic>> messages) {    final buf = StringBuffer();
    for (final m in messages) {
      final role = m['role'];
      if (role == 'system') continue; // system 单独传
      final content = m['content']?.toString();
      if (role == 'user') {
        if (content != null) buf.writeln(content);
      } else if (role == 'assistant') {
        if (content != null) buf.writeln(content);
      } else if (role == 'tool') {
        buf.writeln('[工具结果: ${content ?? ""}]');
      }
    }
    return buf.toString();
  }

  /// 带工具调用的分发（支持 Function Calling）
  /// 返回完整的 AI 回复文本（自动处理工具调用循环）
  Future<String> dispatchWithTools({
    required AppSettings settings,
    required String userMessage,
    AiModelEntity? preferredModel,
    double temperature = 0.7,
    int maxToolRounds = 5,
    void Function(String toolName, String status)? onToolStatus,
  }) async {
    addUserMessage(userMessage);

    AiProfile? profile;
    if (preferredModel != null) {
      profile = _profileFromModel(preferredModel);
    }

    final toolRegistry = ToolRegistry();
    final toolExecutor = ToolExecutor();
    final tools = toolRegistry.enabledTools.isNotEmpty
        ? toolRegistry.toOpenAiTools()
        : null;

    // 构建消息列表（使用 Map<String, dynamic> 以支持 tool_calls）
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt},
      ..._chatHistory.map((m) => Map<String, dynamic>.from(m)),
    ];

    var remainingRounds = maxToolRounds;
    var toolRound = 0;
    final fullContent = StringBuffer();

    while (remainingRounds > 0) {
      remainingRounds--;

      final response = await _aiService.completeWithTools(
        settings: settings,
        systemPrompt: _systemPrompt,
        messages: messages,
        profile: profile,
        tools: tools,
        temperature: temperature,
        toolRound: toolRound,
      );
      toolRound++;
      await _recordUsage(profile, response);

      // 如果有工具调用
      if (response.hasToolCalls) {
        for (final tc in response.toolCalls!) {
          onToolStatus?.call(tc.toolId, '执行中...');
        }

        // 添加到对话历史，确保上下文不丢失
        final assistantMsg = response.allMessages.isNotEmpty
            ? response.allMessages.last
            : null;
        if (assistantMsg != null &&
            assistantMsg['role'] == 'assistant' &&
            assistantMsg['tool_calls'] != null) {
          _chatHistory.add(Map<String, dynamic>.from(assistantMsg));
        }

        // 执行工具
        final results = await toolExecutor.executeAll(response.toolCalls!);

        // 格式化工具结果
        final toolResults = ToolExecutor.formatToolResultsForAi(
          response.toolCalls!,
          results,
        );

        // 工具结果也加入对话历史
        for (final tr in toolResults) {
          _chatHistory.add(Map<String, dynamic>.from(tr));
        }

        for (var i = 0; i < results.length && i < response.toolCalls!.length; i++) {
          final r = results[i];
          onToolStatus?.call(
            r.toolId,
            r.success ? '完成' : '失败: ${r.error}',
          );
        }

        // 更新消息列表
        messages.clear();
        messages.addAll(response.allMessages);
        messages.addAll(toolResults);

        continue;
      }

      // 没有工具调用，返回纯文本
      if (response.content != null && response.content!.isNotEmpty) {
        fullContent.write(response.content);
      }
      break;
    }

    final result = fullContent.toString();
    if (result.isNotEmpty) {
      addAssistantMessage(result);
    }
    return result;
  }
}

class DispatchResult {
  final String content;
  final String usedModel;
  final bool switched;
  final int attempts;
  final int durationMs;

  const DispatchResult({
    required this.content,
    required this.usedModel,
    this.switched = false,
    this.attempts = 1,
    this.durationMs = 0,
  });
}

class DispatchException implements Exception {
  final String message;
  final String? lastError;
  final int attempts;

  const DispatchException(this.message, {this.lastError, this.attempts = 0});

  @override
  String toString() => message;
}