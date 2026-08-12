import 'dart:async';
import 'dart:convert';

import '../../models/ai_profile.dart';
import '../../models/app_settings.dart';
import '../../services/ai_service.dart';
import '../../services/storage_service.dart';
import '../../services/usage_tracker.dart';
import '../../services/volcengine_adapter.dart';
import '../tools/tool_entity.dart';
import '../tools/tool_executor.dart';
import '../tools/tool_registry.dart';
import 'ai_model_entity.dart';
import 'ai_model_manager.dart';
import 'ai_model_probe_service.dart';
import 'ai_provider.dart';

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
  bool _cancelled = false;

  /// 模型切换事件回调（UI 展示提示条）
  void Function(SwitchEvent event)? onModelSwitched;

  /// 工具执行结果回调（工作台时间线/审计）
  void Function(List<ToolCallRequest> requests, List<ToolCallResult> results)?
      onToolsExecuted;

  /// 高风险工具确认回调：返回 true 允许执行，false 拒绝。
  /// 传入工具名与参数摘要，UI 弹确认框。为 null 时高风险工具自动执行。
  Future<bool> Function(
      ToolCallRequest request, String toolName, String argSummary)? onToolConfirm;

  AiRequestDispatcher(this._aiService, this._modelManager)
      : _probeService = AiModelProbeService(_modelManager);

  /// 取消当前正在进行的请求
  void cancelCurrent() {
    _cancelled = true;
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
    Set<String>? enabledSkillIds,
  }) {
    // 取消之前的请求
    cancelCurrent();
    _cancelled = false;

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
      enabledSkillIds: enabledSkillIds,
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
    Set<String>? enabledSkillIds,
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

    final effectiveTimeout = timeoutSeconds ?? settings.ai.aiRequestTimeoutSec;
    final effectiveMaxSwitch = maxSwitchCount ?? settings.ai.aiMaxSwitchCount;

    await _runStream(
      controller,
      settings: settings,
      preferredModel: preferredModel,
      temperature: temperature,
      fallbackModels: fallbacks,
      maxSwitchCount: effectiveMaxSwitch,
      timeoutSeconds: effectiveTimeout,
      enabledSkillIds: enabledSkillIds,
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
    Set<String>? enabledSkillIds,
  }) async {
    const maxToolRounds = 12;
    final fullContent = StringBuffer();

    try {
      // 发送前清洗历史，丢弃残缺的 tool_calls（防止 400）
      ensureHistoryConsistent();
      AiProfile? profile;
      if (preferredModel != null) {
        profile = _profileFromModel(preferredModel);
      } else {
        // 未指定具体模型时，从 settings 兜底构造临时 profile，
        // 避免 preferredModel 为 null（模型列表未加载/为空）时走入
        // "请先选择模型" 抛错路径
        final ai = settings.ai;
        if (ai.effectiveAiModel.isNotEmpty &&
            ai.effectiveAiApiKey.isNotEmpty) {
          profile = AiProfile(
            id: 'fallback',
            name: '默认配置',
            baseUrl: ai.effectiveAiBaseUrl,
            apiKey: ai.effectiveAiApiKey,
            model: ai.effectiveAiModel,
            interfaceType:
                ai.activeAiProfile?.interfaceType ?? InterfaceType.openaiChat,
            thinkingEnabled: ai.activeAiProfile?.thinkingEnabled ?? false,
            reasoningEffort:
                ai.activeAiProfile?.reasoningEffort ?? 'medium',
            reasoningBudgetTokens:
                ai.activeAiProfile?.reasoningBudgetTokens ?? 1024,
            useBearer: ai.activeAiProfile?.useBearer ?? true,
          );
        }
      }

      final messages = [
        {'role': 'system', 'content': _systemPrompt},
        ..._chatHistory,
      ];

      // 技能选择：内置 + MCP 始终可用；自定义技能按 enabledSkillIds 过滤
      // 未指定时（null/空）表示全部启用，保持向后兼容
      final registry = ToolRegistry();
      final skillIds = enabledSkillIds;
      final toolList = registry.enabledTools.where((t) {
        if (t.type != ToolType.skill) return true;
        if (skillIds == null || skillIds.isEmpty) return true;
        return skillIds.contains(t.id);
      }).toList();

      final tools = !disableTools && toolList.isNotEmpty
          ? toolList.map((t) => t.toOpenAiFunction()).toList()
          : null;

      final stopwatch = Stopwatch()..start();
      var streamedContent = false;
      var streamedReasoning = false;
      try {
        final response = await _aiService
            .completeWithToolsStreaming(
              settings: settings,
              systemPrompt: _systemPrompt,
              messages: messages,
              profile: profile,
              tools: tools,
              temperature: temperature,
              toolRound: toolRound,
              onChunk: (chunk) {
                if (controller.isClosed || _cancelled) return;
                if (chunk.content.isNotEmpty) streamedContent = true;
                if (chunk.reasoningContent != null &&
                    chunk.reasoningContent!.isNotEmpty) {
                  streamedReasoning = true;
                }
                controller.add(chunk);
              },
            )
            .timeout(
              Duration(seconds: (timeoutSeconds * 6) + 300),
            );

        stopwatch.stop();
        _recordStreamCall(preferredModel, stopwatch, true);
        await _recordUsage(profile, response);

        if (controller.isClosed) return;

        if (response.hasToolCalls && toolRound < maxToolRounds) {
          if (_cancelled) {
            if (!controller.isClosed) await controller.close();
            return;
          }
          final assistantMsg = response.allMessages.last;
          if (assistantMsg['role'] == 'assistant' &&
              assistantMsg['tool_calls'] != null) {
            _chatHistory.add(Map<String, dynamic>.from(assistantMsg));
          }

          if (response.reasoningContent != null &&
              response.reasoningContent!.isNotEmpty &&
              !streamedReasoning) {
            controller.add(StreamChunk(
                content: '',
                reasoningContent: response.reasoningContent));
          }

          // 先发出工具调用状态，UI 据此显示"运行中"卡片
          if (!controller.isClosed) {
            controller.add(StreamChunk(
              content: '',
              toolCalls: response.toolCalls!
                  .map((tc) => {
                        'id': tc.callId,
                        'type': 'function',
                        'function': {
                          'name': tc.toolId,
                          'arguments': jsonEncode(tc.arguments),
                        },
                      })
                  .toList(),
            ));
          }

          final toolExecutor = ToolExecutor();
          final results = await toolExecutor.executeAll(
            response.toolCalls!,
            confirmOverride: (request) => _confirmTool(request),
          );
          onToolsExecuted?.call(response.toolCalls!, results);

          if (_cancelled) {
            if (!controller.isClosed) await controller.close();
            return;
          }

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
            enabledSkillIds: enabledSkillIds,
          );
          return;
        }

        if (response.content != null && response.content!.isNotEmpty) {
          fullContent.write(response.content);
          if (!streamedContent) {
            controller.add(StreamChunk(
                content: response.content!,
                reasoningContent: response.reasoningContent));
          }
        } else if (response.hasToolCalls && toolRound >= maxToolRounds) {
          const tip = '已达最大工具调用轮次，未获得最终回复。';
          fullContent.write(tip);
          if (!streamedContent) {
            controller.add(StreamChunk(
                content: tip, reasoningContent: response.reasoningContent));
          }
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

      if (errorMsg.contains('HTTP 400') ||
          errorMsg.contains('InvalidParameter')) {
        final isVolcengine = preferredModel != null
            ? VolcengineAdapter.isVolcengineArk(preferredModel.apiBase)
            : false;
        // 仅在首次（未降级工具）时降级为无工具模式重试一次；
        // 已 disableTools 仍 400 说明参数本身不被支持，直接走模型切换/报错，
        // 避免无限递归
        if (isVolcengine && toolRound == 0 && !disableTools) {
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
            enabledSkillIds: enabledSkillIds,
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
            enabledSkillIds: enabledSkillIds,
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

  /// 高风险工具执行前确认：按 riskLevel 判断，回调 UI 弹确认框
  Future<bool> _confirmTool(ToolCallRequest request) async {
    final tool = ToolRegistry().get(request.toolId);
    if (tool == null || tool.riskLevel != 'high') return true;
    if (onToolConfirm == null) return true;
    final argSummary = request.arguments.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');
    return onToolConfirm!(request, tool.name, argSummary);
  }

  /// 清洗历史：删除"带 tool_calls 但缺少后续 tool 回执"的残缺 assistant 消息。
  /// 避免历史中断点/异常导致 400 "tool_calls must be followed by tool messages"。
  /// 规则：assistant 消息若声明了 tool_calls，其后必须紧跟覆盖全部 callId 的
  /// tool 回执；若不完整，则该 assistant 消息与其后孤立的 tool 消息整体丢弃。
  List<Map<String, dynamic>> _sanitizeHistory(
      List<Map<String, dynamic>> history) {
    final out = <Map<String, dynamic>>[];
    var i = 0;
    while (i < history.length) {
      final m = history[i];
      final role = m['role']?.toString();
      if (role == 'assistant') {
        final tc = m['tool_calls'];
        final hasCalls = tc is List && tc.isNotEmpty;
        if (!hasCalls) {
          // 纯文本 assistant 消息：直接保留
          out.add(m);
          i++;
          continue;
        }
        // 带 tool_calls：向后收集连续的 tool 回执，校验完整性
        final callIds = tc
            .whereType<Map>()
            .map((e) => e['id']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toSet();
        var j = i + 1;
        final toolMsgs = <Map<String, dynamic>>[];
        while (j < history.length &&
            history[j]['role']?.toString() == 'tool') {
          toolMsgs.add(history[j]);
          j++;
        }
        final repliedIds = toolMsgs
            .map((tm) => tm['tool_call_id']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toSet();
        final complete = callIds.isNotEmpty &&
            callIds.every(repliedIds.contains);
        if (complete) {
          out.add(m);
          out.addAll(toolMsgs);
        }
        // 残缺则整体跳过（assistant + 其后的孤立 tool 消息都不输出）
        i = j;
      } else if (role == 'tool') {
        // 孤立的 tool 消息（没有前面的 assistant tool_calls）：丢弃
        i++;
      } else {
        out.add(m);
        i++;
      }
    }
    return out;
  }

  /// 发送请求前确保历史中不带残缺的 tool_calls（防止 400）
  void ensureHistoryConsistent() {
    if (_chatHistory.isEmpty) return;
    final cleaned = _sanitizeHistory(_chatHistory);
    _chatHistory
      ..clear()
      ..addAll(cleaned);
  }

  /// 记录单次流式调用（成功/失败）到模型管理器，供择优评分
  void _recordStreamCall(
    AiModelEntity? model,
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
    // 密钥池：成功清零失败计数，失败累计（达到阈值自动轮换）
    if (success) {
      unawaited(_modelManager.recordKeySuccess(model));
    } else {
      unawaited(_modelManager.recordKeyFailure(model));
    }
  }

  /// 记录 token 用量（对标 MonkeyCode usage_capture）
  Future<void> _recordUsage(
      AiProfile? profile, ToolCallResponse response) async {
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
        cacheCreationTokens:
            (usage['cacheCreationTokens'] as num?)?.toInt() ?? 0,
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
    // 发送前清洗历史，丢弃残缺的 tool_calls（防止 400）
    ensureHistoryConsistent();
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
          unawaited(_modelManager.recordKeySuccess(currentModel));
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
          unawaited(_modelManager.recordKeyFailure(currentModel));
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
              (m) =>
                  m.modelId == currentModel!.modelId &&
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
      apiKey: m.effectiveKey,
      model: m.modelId,
      apiPath: m.apiPath,
      useBearer: m.useBearer,
      interfaceType: m.interfaceType,
      thinkingEnabled: m.thinkingEnabled,
      reasoningEffort: m.reasoningEffort,
      reasoningBudgetTokens: m.reasoningBudgetTokens,
    );
  }

  String _buildMessagesString(List<Map<String, dynamic>> messages) {
    final buf = StringBuffer();
    for (final m in messages) {
      final role = m['role'];
      if (role == 'system') continue; // system 单独传
      final raw = m['content'];
      final content = raw is String
          ? raw
          : (raw is List
              ? raw
                  .whereType<Map>()
                  .map((b) => b['text']?.toString() ?? '')
                  .join()
              : '');
      if (role == 'user') {
        if (content.isNotEmpty) buf.writeln(content);
      } else if (role == 'assistant') {
        if (content.isNotEmpty) buf.writeln(content);
      } else if (role == 'tool') {
        buf.writeln('[工具结果: ${content.isEmpty ? "" : content}]');
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
    ensureHistoryConsistent();
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
        final assistantMsg =
            response.allMessages.isNotEmpty ? response.allMessages.last : null;
        if (assistantMsg != null &&
            assistantMsg['role'] == 'assistant' &&
            assistantMsg['tool_calls'] != null) {
          _chatHistory.add(Map<String, dynamic>.from(assistantMsg));
        }

        // 执行工具
        final results = await toolExecutor.executeAll(
          response.toolCalls!,
          confirmOverride: (request) => _confirmTool(request),
        );
        onToolsExecuted?.call(response.toolCalls!, results);

        // 格式化工具结果
        final toolResults = ToolExecutor.formatToolResultsForAi(
          response.toolCalls!,
          results,
        );

        // 工具结果也加入对话历史
        for (final tr in toolResults) {
          _chatHistory.add(Map<String, dynamic>.from(tr));
        }

        for (var i = 0;
            i < results.length && i < response.toolCalls!.length;
            i++) {
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
