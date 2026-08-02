import 'dart:async';
import 'dart:convert';

import '../../models/ai_profile.dart';
import '../../models/app_settings.dart';
import '../../services/ai_service.dart';
import '../tools/tool_entity.dart';
import '../tools/tool_executor.dart';
import '../tools/tool_registry.dart';
import 'ai_model_entity.dart';
import 'ai_model_manager.dart';

/// 请求调度器：超时监听、故障自动切换备选模型、完整上下文继承
class AiRequestDispatcher {
  final AiService _aiService;
  final AiModelManager _modelManager;
  StreamController<StreamChunk>? _activeStreamController;

  AiRequestDispatcher(this._aiService, this._modelManager);

  /// 取消当前正在进行的流式请求
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

  /// 流式分发：逐字返回 AI 回复，支持取消
  Stream<StreamChunk> dispatchStream({
    required AppSettings settings,
    required String userMessage,
    AiModelEntity? preferredModel,
    double temperature = 0.7,
  }) {
    // 取消之前的请求
    cancelCurrent();

    addUserMessage(userMessage);

    final controller = StreamController<StreamChunk>();
    _activeStreamController = controller;

    // 启动异步流式处理（不保存返回值，通过 controller 控制取消）
    _runStream(
      controller,
      settings: settings,
      preferredModel: preferredModel,
      temperature: temperature,
    );

    return controller.stream;
  }

  Future<void> _runStream(
    StreamController<StreamChunk> controller, {
    required AppSettings settings,
    AiModelEntity? preferredModel,
    double temperature = 0.7,
    int toolRound = 0,
  }) async {
    const maxToolRounds = 5;
    final stopwatch = Stopwatch()..start();
    final fullContent = StringBuffer();

    try {
      AiProfile? profile;
      if (preferredModel != null) {
        profile = AiProfile(
          id: preferredModel.modelId,
          name: preferredModel.modelName,
          baseUrl: preferredModel.apiBase,
          apiKey: preferredModel.apiKey,
          model: preferredModel.modelId,
          apiPath: preferredModel.apiPath,
          useBearer: preferredModel.useBearer,
        );
      }

      final messages = [
        {'role': 'system', 'content': _systemPrompt},
        ..._chatHistory,
      ];

      final tools = ToolRegistry().enabledTools.isNotEmpty
          ? ToolRegistry().toOpenAiTools()
          : null;

      final stream = _aiService.completeStream(
        settings: settings,
        systemPrompt: _systemPrompt,
        userPrompt: _buildMessagesString(messages),
        profile: profile,
        temperature: temperature,
        messages: messages,
        tools: tools,
      );

      List<Map<String, dynamic>>? pendingToolCalls;

      await for (final chunk in stream) {
        if (controller.isClosed) break;
        if (chunk.content.isNotEmpty) {
          fullContent.write(chunk.content);
          controller.add(chunk);
        }
        if (chunk.isDone) {
          pendingToolCalls = chunk.toolCalls;
          break;
        }
      }

      // 处理工具调用（兼容多种 finish_reason，部分厂商返回 "stop" 而非 "tool_calls"）
      if (pendingToolCalls != null &&
          pendingToolCalls.isNotEmpty &&
          toolRound < maxToolRounds) {
        // 添加 assistant 消息（含 tool_calls，确保 API 能正确匹配工具调用上下文）
        _chatHistory.add({
          'role': 'assistant',
          'content': fullContent.isNotEmpty ? fullContent.toString() : '',
          'tool_calls': pendingToolCalls,
        });

        // 执行工具
        final toolExecutor = ToolExecutor();
        for (final tc in pendingToolCalls) {
          final func = tc['function'] as Map<String, dynamic>?;
          if (func == null) continue;
          final toolName = func['name']?.toString() ?? '';
          final argsStr = func['arguments']?.toString() ?? '{}';
          Map<String, dynamic> args;
          try {
            args = jsonDecode(argsStr) as Map<String, dynamic>;
          } catch (_) {
            args = {};
          }

          final request = ToolCallRequest(
            toolId: toolName,
            callId: tc['id']?.toString() ?? '',
            arguments: args,
          );

          final result = await toolExecutor.execute(request);
          final toolResultMsg = {
            'role': 'tool',
            'tool_call_id': request.callId,
            'content': result.success ? result.content : 'Error: ${result.error}',
          };
          _chatHistory.add(toolResultMsg);
        }

        // 如果 fullContent 为空，显示工具执行摘要
        if (fullContent.isEmpty) {
          final toolNames = pendingToolCalls
              .map((tc) => (tc['function'] as Map?)?['name']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .join(', ');
          controller.add(StreamChunk(content: '正在使用工具: $toolNames...\n'));
        }

        stopwatch.stop();
        // 递归调用，让 AI 处理工具结果
        await _runStream(
          controller,
          settings: settings,
          preferredModel: preferredModel,
          temperature: temperature,
          toolRound: toolRound + 1,
        );
        return;
      }

      // 正常结束
      stopwatch.stop();
      if (preferredModel != null) {
        _modelManager.recordCall(
          preferredModel.modelId,
          preferredModel.apiBase,
          stopwatch.elapsedMilliseconds,
          true,
        );
      }
      if (fullContent.isNotEmpty) {
        addAssistantMessage(fullContent.toString());
      }
      if (!controller.isClosed) {
        controller.add(const StreamChunk(content: '', isDone: true));
        await controller.close();
      }
    } catch (e) {
      stopwatch.stop();
      if (preferredModel != null) {
        _modelManager.recordCall(
          preferredModel.modelId,
          preferredModel.apiBase,
          stopwatch.elapsedMilliseconds,
          false,
        );
      }
      if (!controller.isClosed) {
        controller.addError(e);
        await controller.close();
      }
    }
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
    bool Function(String)? isRetryableError,
  }) async {
    addUserMessage(userMessage);

    // 构建备选模型队列
    final fallbackModels = enableAutoSwitch
        ? await _modelManager.getEnabled()
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
          profile = AiProfile(
            id: currentModel.modelId,
            name: currentModel.modelName,
            baseUrl: currentModel.apiBase,
            apiKey: currentModel.apiKey,
            model: currentModel.modelId,
            apiPath: currentModel.apiPath,
            useBearer: currentModel.useBearer,
          );
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
              Duration(seconds: currentModel?.timeoutSecond ?? 30),
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
        if (isRetryableError != null && !isRetryableError(lastError!)) {
          break;
        }

        // 自动选取下一个备选模型
        if (enableAutoSwitch && fallbackModels.isNotEmpty) {
          // 移除当前模型
          if (currentModel != null) {
            fallbackModels.removeWhere(
              (m) => m.modelId == currentModel!.modelId &&
                  m.apiBase == currentModel!.apiBase,
            );
          }
          if (fallbackModels.isEmpty) break;
          // 找优先级最高的
          currentModel = fallbackModels.first;
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

  String _buildMessagesString(List<Map<String, dynamic>> messages) {
    final buf = StringBuffer();
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
      profile = AiProfile(
        id: preferredModel.modelId,
        name: preferredModel.modelName,
        baseUrl: preferredModel.apiBase,
        apiKey: preferredModel.apiKey,
        model: preferredModel.modelId,
        apiPath: preferredModel.apiPath,
        useBearer: preferredModel.useBearer,
      );
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
      );

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