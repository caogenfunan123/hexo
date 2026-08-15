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

/// AI 站点巡检对话页面
class AiAuditScreen extends StatelessWidget {
  final AppSettings settings;
  final RepoConfig? activeRepo;
  final AiService aiService;
  final AiModelManager modelManager;
  final AiRequestDispatcher dispatcher;
  final AiSelfChecker selfChecker;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final GitHubService? gitHubService;
  final StorageService? storageService;

  const AiAuditScreen({
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
        title: const Text('AI 站点巡检'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新巡检',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('请在下方对话框中输入「开始巡检」或具体检查项指令，AI 将自动执行巡检'),
                  duration: Duration(seconds: 3),
                ),
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
        sessionType: AiSessionType.audit,
        blogFramework: fw,
        postsPath: repo?.postsPath,
        pagesPath: repo?.pagesPath,
        themesPath: 'themes',
        gitHubService: gitHubService,
        activeRepo: repo,
        storageService: storageService,
        initialMessage: '欢迎使用 AI 站点巡检助手！\n\n你可以直接告诉我：\n'
            '• 开始全面巡检\n'
            '• 检查配置文件语法\n'
            '• 检查文章 FrontMatter 完整性\n'
            '• 检查模板文件闭合标签\n'
            '• 分析目录结构是否规范\n'
            '• 给出优化建议\n\n'
            '当前框架：${fw ?? "未指定"}',
        onSettingsChanged: onSettingsChanged,
      ),
      ),
    );
  }
}