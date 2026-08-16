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
import 'ai_message_cleaner.dart';
import 'ai_model_entity.dart';
import 'ai_model_manager.dart';
import 'ai_model_probe_service.dart';
import 'ai_provider.dart';
import 'ai_session_manager.dart';
import 'ai_session_tools.dart';
import 'ai_tool_catalog_prompt.dart';

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

  /// 请求代际：每次新请求（含取消）自增，旧异步任务据此识别自己已被取代而静默退出
  int _requestGeneration = 0;

  /// 上下文增量摘要（移植 Operit AIMessageManager）：
  /// - 触发阈值：上下文字符占比 >= [_kSummaryRatioThreshold]，
  ///   或上次摘要之后用户消息数 >= [_kSummaryUserMessageThreshold]。
  /// - 摘要只覆盖上次摘要之后的新对话，继承旧摘要生成新摘要，
  ///   发送视图用摘要替换其之前的原始历史，根治长会话失忆。
  static const bool _kSummaryEnabled = true;
  static const double _kSummaryRatioThreshold = 0.7;
  static const int _kSummaryUserMessageThreshold = 16;

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
    _requestGeneration++; // 使旧请求的所有恢复点失效
    _cancelled = true;
    _activeStreamController?.close();
    _activeStreamController = null;
  }

  /// 当前代际是否已过期（被更新的请求取代）
  bool _isStale(int generation) => _requestGeneration != generation;

  /// 上下文持有器：保存完整会话历史（含 tool_calls），保证切换模型时上下文不丢失
  final List<Map<String, dynamic>> _chatHistory = [];
  String _systemPrompt = '';

  /// 工具能力地图后缀：每次请求基于会话过滤后的实际可用工具动态生成，
  /// 让模型开局掌握全局工具，避免盲目探测 list_tools。
  String _toolCatalogSuffix = '';

  /// 发送给模型的实际 System Prompt = 内核 + 工具能力地图
  String get _effectiveSystemPrompt => _systemPrompt + _toolCatalogSuffix;

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

  bool _isSummaryMsg(Map<String, dynamic> m) => m['is_summary'] == true;

  /// 最后一次摘要消息的下标，无则 null
  int? _lastSummaryIndex() {
    for (var i = _chatHistory.length - 1; i >= 0; i--) {
      if (_isSummaryMsg(_chatHistory[i])) return i;
    }
    return null;
  }

  /// 是否应生成增量摘要（仿 Operit shouldGenerateSummary）：
  /// 字符占比达到阈值（接近滑动窗口上限，摘要可提前压缩防失忆），
  /// 或上次摘要之后用户消息达到数量阈值。
  bool _shouldGenerateSummary(AppSettings settings) {
    if (!_kSummaryEnabled) return false;
    if (settings.ai.aiMaxContextChars <= 0) return false;
    final lastIdx = _lastSummaryIndex();
    final relevant = lastIdx == null
        ? _chatHistory
        : _chatHistory.sublist(lastIdx + 1);
    if (relevant.isEmpty) return false;
    var chars = 0;
    var userCount = 0;
    for (final m in relevant) {
      final role = m['role']?.toString();
      if (role == 'user') {
        userCount++;
        chars += _messageChars(m);
      } else if (role == 'assistant' || role == 'tool') {
        // tool 结果也计入：大工具结果占预算大头，漏计会让摘要触发偏晚
        chars += _messageChars(m);
      }
    }
    if (chars / settings.ai.aiMaxContextChars >= _kSummaryRatioThreshold) {
      return true;
    }
    if (userCount >= _kSummaryUserMessageThreshold) return true;
    return false;
  }

  /// 生成增量摘要：只取上次摘要之后的 user/ai 消息，继承旧摘要生成新摘要。
  /// 失败或空结果返回 null（调用方静默降级，不影响主流程）。
  Future<String?> _summarizeConversation(
    AppSettings settings,
    AiProfile? profile,
  ) async {
    final lastIdx = _lastSummaryIndex();
    final previous = lastIdx == null
        ? null
        : (_chatHistory[lastIdx]['content'] as String?)?.trim();
    final relevant = lastIdx == null
        ? _chatHistory
        : _chatHistory.sublist(lastIdx + 1);
    final entries = <String>[];
    var seq = 1;
    for (final m in relevant) {
      final role = m['role']?.toString();
      if (role != 'user' && role != 'assistant') continue;
      var content = m['content']?.toString() ?? '';
      if (role == 'assistant' && content.isEmpty) {
        // 纯工具调用轮：content 常为空，附上工具名留痕
        final tc = m['tool_calls'];
        if (tc is List && tc.isNotEmpty) {
          final names = tc
              .whereType<Map>()
              .map((e) => e['function']?['name']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .join(', ');
          if (names.isNotEmpty) content = '[调用工具: $names]';
        }
      }
      // 剥除思考块与 Gemini 签名，避免污染摘要
      if (role == 'assistant') {
        content = AiMessageCleaner.cleanForModel(content);
      }
      final cleaned = content.trim();
      if (cleaned.isEmpty) continue;
      entries.add('#$seq: $cleaned');
      seq++;
    }
    if (entries.isEmpty) return null;

    final result = await _aiService
        .complete(
          settings: settings,
          systemPrompt: _buildSummarySystemPrompt(previous),
          userPrompt: entries.join('\n\n'),
          profile: profile,
          temperature: 0.3,
        )
        .timeout(const Duration(seconds: 90));
    final text = result.trim();
    if (text.isEmpty) return null;
    return text;
  }

  /// 摘要系统提示词（四段式固定格式，移植 Operit FunctionalPrompts.SUMMARY_PROMPT）。
  /// 若存在旧摘要，追加继承指令，让新摘要与其融合。
  String _buildSummarySystemPrompt(String? previousSummary) {
    var prompt = '''
你是负责生成对话摘要的AI助手。你的任务是根据"上一次的摘要"（如果提供）和"最近的对话内容"，生成一份全新的、独立的、全面的摘要。这份新摘要将完全取代之前的摘要，成为后续对话的唯一历史参考。

**必须严格遵循以下固定格式输出，不得更改格式结构：**

==========对话摘要==========

【核心任务状态】
[先交代用户最新需求的内容与情境类型（真实执行/角色扮演/故事/假设等），再说明当前所处步骤、已完成的动作、正在处理的事项以及下一步。]
[明确任务状态（已完成/进行中/等待中），列出未完成的依赖或所需信息；如在等待用户输入，说明原因与所需材料。]
[显式覆盖信息搜集、任务执行、代码编写或其他关键环节的状态，哪怕某环节尚未启动也要说明原因。]
[最后补充最近一次任务的进度拆解：哪些已完成、哪些进行中、哪些待处理。]

【互动情节与设定】
[如存在虚构或场景设定，概述名称、角色身份、背景约束及其来源，避免把剧情当成现实。]
[用1-2段概括近期关键互动：谁提出了什么、目的为何、采用何种表达方式、对任务或剧情的影响，以及仍需确认的事项。]
[若用户给出剧本/业务/策略等非技术内容，提炼要点并说明它们如何指导后续输出。]

【对话历程与概要】
[用不少于3段描述整体演进，每段包含"行动+目的+结果"，可涵盖技术、业务、剧情或策略等不同主题，需特别点名信息搜集、任务执行、代码编写等阶段的衔接；如涉及具体代码，可引用关键片段以辅助说明。]
[突出转折、已解决的问题和形成的共识，引用必要的路径、命令、场景节点或原话，确保读者能看懂上下文和因果关系。]

【关键信息与上下文】
- [信息点1：用户需求、限制、背景或引用的文件/接口/角色等，说明其具体内容及作用。]
- [信息点2：技术或剧本结构中的关键元素（函数、配置、日志、人物动机等）及其意义。]
- [信息点3：问题或创意的探索路径、验证结果与当前状态。]
- [信息点4：影响后续决策的因素，如优先级、情绪基调、角色约束、外部依赖、时间节点。]
- [信息点5+：补充其他必要细节，覆盖现实与虚构信息。每条至少两句：先述事实，再讲影响或后续计划。]

============================

**格式要求：**
1. 必须使用上述固定格式，包括分隔线、标题标识符【】、列表符号等，不得更改。
2. 标题"对话摘要"必须放在第一行，前后用等号分隔。
3. 每个部分必须使用【】标识符作为标题，标题后换行。
4. "核心任务状态"、"互动情节与设定"、"对话历程与概要"使用段落形式；方括号只为示例，实际输出不需保留。
5. "关键信息与上下文"使用列表格式，每个信息点以"- "开头。
6. 结尾使用等号分隔线。

**内容要求：**
1. 语言风格：专业、清晰、客观。
2. 内容长度：不要限制字数，根据对话内容的复杂程度和重要性，自行决定合适的长度。可以写得详细一些，确保重要信息不丢失。宁可内容多一点，也不要因为过度精简导致关键信息丢失或失真。每个部分都要具备充分篇幅，绝不能以一句话敷衍。
3. 信息完整性：优先保证信息的完整性和准确性，技术与非技术内容都需提供必要证据或引用。
4. 内容还原：摘要既要说明"过程如何推进"，也要写清"实际产出/讨论内容是什么"，必要时引用结果文本、结论、代码片段或参数，确保在没有原始对话的情况下依然能完全还原信息本身。
5. 目标：生成的摘要必须是自包含的。即使AI完全忘记了之前的对话，仅凭这份摘要也能够准确理解历史背景、当前状态、具体进度和下一步行动。
6. 时序重点：请先聚焦于最新一段对话（约占输入的最后30%），明确最新指令、问题和进展，再回顾更早的内容。若新消息与旧内容冲突或更新，应以最新对话为准，并解释差异。
''';
    final prev = previousSummary;
    if (prev != null && prev.isNotEmpty) {
      prompt += '''

上一次的摘要（用于继承上下文）：
$prev
请将以上摘要中的关键信息，与本次新的对话内容相融合，生成一份全新的、更完整的摘要。
''';
    }
    return prompt;
  }

  /// 写入新摘要：移除旧摘要及摘要之前的全部原始历史（其信息已由新摘要
  /// 承载），只保留摘要之后的完整历史，供下次增量摘要继续使用。
  /// 由此 [_chatHistory] 始终紧凑，_shouldGenerateSummary 的字符占比
  /// 只统计摘要之后的新增内容，避免每次请求重复触发。
  void _upsertSummary(String text) {
    final lastIdx = _lastSummaryIndex();
    final rest = lastIdx == null
        ? const <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(_chatHistory.sublist(lastIdx + 1));
    _chatHistory.clear();
    _chatHistory.add({
      'role': 'system',
      'content': text,
      'is_summary': true,
    });
    _chatHistory.addAll(rest);
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
    AiSessionType? sessionType,
  }) {
    // 取消之前的请求
    cancelCurrent();
    _cancelled = false;
    final generation = _requestGeneration;

    addUserMessage(userMessage);

    final controller = StreamController<StreamChunk>();
    _activeStreamController = controller;

    // 异步构建备选队列并启动处理
    _prepareAndRunStream(
      controller,
      generation: generation,
      settings: settings,
      preferredModel: preferredModel,
      temperature: temperature,
      autoOptimal: autoOptimal,
      timeoutSeconds: timeoutSeconds,
      maxSwitchCount: maxSwitchCount,
      enabledSkillIds: enabledSkillIds,
      sessionType: sessionType,
    );

    return controller.stream;
  }

  Future<void> _prepareAndRunStream(
    StreamController<StreamChunk> controller, {
    required int generation,
    required AppSettings settings,
    AiModelEntity? preferredModel,
    double temperature = 0.7,
    bool autoOptimal = true,
    int? timeoutSeconds,
    int? maxSwitchCount,
    Set<String>? enabledSkillIds,
    AiSessionType? sessionType,
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
    if (_isStale(generation)) return; // 已被新请求取代

    final effectiveTimeout = timeoutSeconds ?? settings.ai.aiRequestTimeoutSec;
    final effectiveMaxSwitch = maxSwitchCount ?? settings.ai.aiMaxSwitchCount;

    await _runStream(
      controller,
      generation: generation,
      settings: settings,
      preferredModel: preferredModel,
      temperature: temperature,
      fallbackModels: fallbacks,
      maxSwitchCount: effectiveMaxSwitch,
      timeoutSeconds: effectiveTimeout,
      enabledSkillIds: enabledSkillIds,
      sessionType: sessionType,
    );
  }

  Future<void> _runStream(
    StreamController<StreamChunk> controller, {
    required int generation,
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
    AiSessionType? sessionType,
    Set<String>? injectedToolIds,
  }) async {
    const maxToolRounds = 12;
    final fullContent = StringBuffer();

    try {
      // 发送前清洗历史，丢弃残缺的 tool_calls（防止 400）
      ensureHistoryConsistent();
      if (_isStale(generation)) return;
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

      // 上下文增量摘要：触发时先异步生成摘要并写入历史，再构建发送视图。
      // 摘要失败静默降级（继续走对称滑动窗口），不阻塞主流程。
      if (_shouldGenerateSummary(settings)) {
        try {
          final summary = await _summarizeConversation(settings, profile);
          if (summary != null) {
            _upsertSummary(summary);
          }
        } catch (_) {
          // 摘要生成失败：忽略，主流程继续
        }
        if (_isStale(generation)) return;
      }

      // 全量工具暴露：开局直接把所有启用工具（内置/技能/MCP）交给模型，
      // 避免"按需注入"让模型反复 list_tools 探测却不执行任务。
      final registry = ToolRegistry();
      final skillIds = enabledSkillIds;
      final List<ToolEntity> exposedTools = [];

      for (final t in registry.enabledTools) {
        // 自定义技能按 enabledSkillIds 过滤
        if (t.type == ToolType.skill &&
            skillIds != null &&
            skillIds.isNotEmpty &&
            !skillIds.contains(t.id)) {
          continue;
        }
        exposedTools.add(t);
      }

      // 会话注入边界：audit 只读会话等禁止注入写工具（用白名单兜底）
      final toolList = filterToolsForSession(exposedTools, sessionType);

      // 注入工具能力地图：让模型开局掌握全局工具，选型更有针对性
      _toolCatalogSuffix = buildToolCatalogPrompt(toolList);

      final messages = _buildContextMessages(settings.ai.aiMaxContextChars);

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
              systemPrompt: _effectiveSystemPrompt,
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
        if (controller.isClosed || _cancelled || _isStale(generation)) return;
        _recordStreamCall(preferredModel, stopwatch, true);
        await _recordUsage(profile, response);
        if (_isStale(generation)) return;

        if (controller.isClosed) return;

        if (response.hasToolCalls && toolRound < maxToolRounds) {
          if (_cancelled || _isStale(generation)) {
            if (!controller.isClosed) await controller.close();
            return;
          }
          final assistantMsg = response.allMessages.last;

          // 按需注入：模型调用 list_tools(tool_name=xxx) 后，把目标工具加入
          // 注入集合，下一轮 tools 自动带上其完整定义。
          final nextInjected = <String>{...?injectedToolIds};
          for (final tc in response.toolCalls!) {
            if (tc.toolId != 'list_tools') continue;
            final name = tc.arguments['tool_name']?.toString().trim() ?? '';
            final target = name.isNotEmpty ? registry.get(name) : null;
            if (target != null && target.enabled) {
              nextInjected.add(name);
            }
          }
          final effectiveInjected =
              nextInjected.isEmpty ? injectedToolIds : nextInjected;

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
            isCancelled: () => _cancelled || _isStale(generation),
          );
          if (_isStale(generation)) return;
          onToolsExecuted?.call(response.toolCalls!, results);

          if (_cancelled || _isStale(generation)) {
            if (!controller.isClosed) await controller.close();
            return;
          }

          // 工具执行成功后才将 assistant 消息与 tool 回执成对入史，
          // 避免取消/失败时留下残缺 tool_calls 污染历史（_sanitizeHistory 兜底）。
          if (assistantMsg['role'] == 'assistant' &&
              assistantMsg['tool_calls'] != null) {
            _chatHistory.add(Map<String, dynamic>.from(assistantMsg));
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
            generation: generation,
            settings: settings,
            preferredModel: preferredModel,
            temperature: temperature,
            toolRound: toolRound + 1,
            fallbackModels: fallbackModels,
            maxSwitchCount: maxSwitchCount,
            timeoutSeconds: timeoutSeconds,
            switchCount: switchCount,
            enabledSkillIds: enabledSkillIds,
            sessionType: sessionType,
            injectedToolIds: effectiveInjected,
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
            generation: generation,
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
            sessionType: sessionType,
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
            generation: generation,
            settings: settings,
            preferredModel: next,
            temperature: temperature,
            toolRound: toolRound,
            fallbackModels: fallbackModels,
            maxSwitchCount: maxSwitchCount,
            timeoutSeconds: timeoutSeconds,
            switchCount: switchCount + 1,
            enabledSkillIds: enabledSkillIds,
            sessionType: sessionType,
            injectedToolIds: injectedToolIds,
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
    // 敏感参数（token / key / secret 等）脱敏，避免在确认框明文展示凭据
    final argSummary = request.arguments.entries
        .map((e) {
          final key = e.key.toLowerCase();
          final isSecret = key.contains('token') ||
              key.contains('key') ||
              key.contains('secret') ||
              key.contains('password') ||
              key.contains('credential');
          final value = e.value.toString();
          final shown =
              isSecret && value.isNotEmpty ? '******' : value;
          return '${e.key}: $shown';
        })
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

  /// 构建发送给模型的完整消息列表（system + 压缩后的历史）。
  ///
  /// 上下文压缩策略（对称滑动窗口）：若历史未超限，原样保留；若超限，
  /// 则保留「开头任务锚点 + 最近对话窗口」两段，只丢弃中间部分：
  /// - 开头锚点：对话早期的纯文本消息（用户的目标指令、早期的上下文），
  ///   避免模型丢失"本次会话要做什么"。只取文本轮次，跳过工具消息。
  /// - 最近窗口：从最新消息往前累积的完整轮次（含工具调用对偶），
  ///   保证最近的对话和工具执行状态仍然可见。
  /// 窗口截断可能把一对 assistant(tool_calls) 与 tool 回执拦腰截断，产生
  /// "带 tool_calls 无回执"或"孤立 tool"的残缺消息，触发服务端 400。
  /// 因此累积后必须再次走 [_sanitizeHistory] 清洗，保证对偶完整。
  /// 该压缩只影响本次发送视图，不破坏 [_chatHistory] 的完整继承。
  ///
  /// 增量摘要替换：若存在摘要消息，其之前的原始历史由摘要承载，不再
  /// 发送；发送视图变为 [system, 摘要, 摘要之后的完整历史]（再进行上述
  /// 对称压缩兜底），从根本上避免长会话因丢中段而失忆。
  List<Map<String, dynamic>> _buildContextMessages(int maxChars) {
    // 摘要替换视图：有摘要时丢弃摘要之前的原始历史
    var history = _chatHistory;
    final summaryIdx = _lastSummaryIndex();
    if (summaryIdx != null && summaryIdx > 0) {
      history = [
        _chatHistory[summaryIdx],
        ..._chatHistory.sublist(summaryIdx + 1),
      ];
    }
    if (maxChars <= 0 || history.isEmpty) {
      return [
        {'role': 'system', 'content': _effectiveSystemPrompt},
        ...history,
      ];
    }

    final systemLen = _effectiveSystemPrompt.length;
    final budget = maxChars > systemLen ? maxChars - systemLen : 0;
    if (budget <= 0) {
      return [
        {'role': 'system', 'content': _effectiveSystemPrompt},
      ];
    }

    // 未超限时原样返回，避免打乱历史顺序
    var totalChars = 0;
    for (final m in history) {
      totalChars += _messageChars(m);
    }
    if (totalChars <= budget) {
      return [
        {'role': 'system', 'content': _effectiveSystemPrompt},
        ...history,
      ];
    }

    // 对称分配：开头锚点占约 25%，最近窗口占约 75%
    final anchorBudget = (budget * 0.25).round();
    final tailBudget = budget - anchorBudget;

    // 1) 开头锚点：从前往后累积纯文本消息（跳过工具消息）
    final anchors = <Map<String, dynamic>>[];
    final anchorIdx = <int>{};
    var usedAnchor = 0;
    for (var i = 0; i < history.length; i++) {
      final m = history[i];
      if (m['role'] == 'tool') continue;
      if (m['tool_calls'] is List && (m['tool_calls'] as List).isNotEmpty) {
        continue;
      }
      final len = _messageChars(m);
      if (usedAnchor + len > anchorBudget && anchors.isNotEmpty) break;
      anchors.add(m);
      anchorIdx.add(i);
      usedAnchor += len;
      if (usedAnchor >= anchorBudget) break;
    }

    // 2) 最近窗口：从后往前累积完整轮次（含工具对偶），跳过锚点已覆盖的
    final tail = <Map<String, dynamic>>[];
    var usedTail = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      if (anchorIdx.contains(i)) continue;
      final m = history[i];
      final len = _messageChars(m);
      if (usedTail + len > tailBudget && tail.isNotEmpty) break;
      tail.insert(0, m);
      usedTail += len;
      if (usedTail >= tailBudget) break;
    }

    // 3) 清洗窗口残缺 tool_calls/tool 对偶，防止服务端 400
    final cleanedTail = _sanitizeHistory(tail);

    final dropped = history.length - anchors.length - tail.length;
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _effectiveSystemPrompt},
    ];
    if (dropped > 0) {
      messages.add({
        'role': 'system',
        'content': '[对话中段因上下文长度限制已被省略，共 $dropped 条消息。'
            '已保留开头任务上下文与最近对话，请基于现有信息继续执行当前任务。]',
      });
    }
    messages.addAll(anchors);
    messages.addAll(cleanedTail);
    return messages;
  }

  /// 估算一条消息占用的字符数（content 文本 + tool_calls 序列化）
  int _messageChars(Map<String, dynamic> m) {
    var len = 0;
    final content = m['content'];
    if (content is String) {
      len += content.length;
    } else if (content is List) {
      len += content.fold<int>(0, (sum, b) {
        if (b is Map) {
          return sum + (b['text']?.toString().length ?? 0);
        }
        return sum + (b?.toString().length ?? 0);
      });
    }
    final tc = m['tool_calls'];
    if (tc is List) {
      try {
        len += jsonEncode(tc).length;
      } catch (_) {}
    }
    return len;
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
          {'role': 'system', 'content': _effectiveSystemPrompt},
          ..._chatHistory,
        ];

        stopwatch.reset();
        stopwatch.start();
        final result = await _aiService
            .complete(
              settings: settings,
              systemPrompt: _effectiveSystemPrompt,
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
