import 'package:flutter/material.dart';

import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/ai/ai_session_manager.dart';
import '../models/app_settings.dart';
import '../models/repo_config.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import '../widgets/ai_chat_panel.dart';

/// AI 主题开发对话页面
class AiThemeChatScreen extends StatelessWidget {
  final AppSettings settings;
  final RepoConfig? activeRepo;
  final AiService aiService;
  final AiModelManager modelManager;
  final AiRequestDispatcher dispatcher;
  final AiSelfChecker selfChecker;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final GitHubService? gitHubService;
  final StorageService? storageService;

  const AiThemeChatScreen({
    super.key,
    required this.settings,
    this.activeRepo,
    required this.aiService,
    required this.modelManager,
    required this.dispatcher,
    required this.selfChecker,
    required this.onSettingsChanged,
    this.gitHubService,
    this.storageService,
  });

  @override
  Widget build(BuildContext context) {
    final repo = activeRepo;
    final fw = repo?.frameworkId;

    return PopScope(
      canPop: true,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('AI 主题开发'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '快照管理',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('输入「创建主题备份快照」或「回滚主题」指令')),
              );
            },
          ),
        ],
      ),
      body: AiChatPanel(
        settings: settings,
        aiService: aiService,
        modelManager: modelManager,
        dispatcher: dispatcher,
        selfChecker: selfChecker,
        sessionType: AiSessionType.theme,
        blogFramework: fw,
        themesPath: 'themes',
        gitHubService: gitHubService,
        activeRepo: repo,
        storageService: storageService,
        initialMessage: '欢迎使用 AI 主题开发助手！\n\n你可以直接告诉我：\n'
            '• 新建主题 [名称]\n'
            '• 修改文件 [路径]，实现 [功能]\n'
            '• 优化样式、适配暗色模式\n'
            '• 创建主题备份快照\n'
            '• 回滚主题至上一个可用快照\n'
            '• 分析当前代码构建风险\n\n'
            '当前框架：${fw ?? "未指定"} | 主题目录：themes',
        onSettingsChanged: onSettingsChanged,
      ),
      ),
    );
  }
}