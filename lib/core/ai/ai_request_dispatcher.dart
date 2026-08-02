import 'dart:async';

import '../../models/ai_profile.dart';
import '../../models/app_settings.dart';
import '../../services/ai_service.dart';
import 'ai_model_entity.dart';
import 'ai_model_manager.dart';

/// 请求调度器：超时监听、故障自动切换备选模型、完整上下文继承
class AiRequestDispatcher {
  final AiService _aiService;
  final AiModelManager _modelManager;

  AiRequestDispatcher(this._aiService, this._modelManager);

  /// 上下文持有器：保存完整会话历史，保证切换模型时上下文不丢失
  final List<Map<String, String>> _chatHistory = [];
  String _systemPrompt = '';

  List<Map<String, String>> get chatHistory => List.unmodifiable(_chatHistory);

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

        final stopwatch = Stopwatch()..start();
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

        // 记录失败
        if (currentModel != null) {
          _modelManager.recordCall(
            currentModel.modelId,
            currentModel.apiBase,
            currentModel.timeoutSecond * 1000,
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

  String _buildMessagesString(List<Map<String, String>> messages) {
    final buf = StringBuffer();
    for (final m in messages) {
      if (m['role'] == 'system') continue; // system 单独传
      if (m['role'] == 'user') {
        buf.writeln(m['content']);
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