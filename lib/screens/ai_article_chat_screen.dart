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

/// AI 博文/页面创作对话页面
class AiArticleChatScreen extends StatelessWidget {
  final AppSettings settings;
  final RepoConfig? activeRepo;
  final AiService aiService;
  final AiModelManager modelManager;
  final AiRequestDispatcher dispatcher;
  final AiSelfChecker selfChecker;
  final bool isPage; // true=页面, false=博文
  final Future<void> Function(AppSettings) onSettingsChanged;
  final GitHubService? gitHubService;
  final StorageService? storageService;

  const AiArticleChatScreen({
    super.key,
    required this.settings,
    this.activeRepo,
    required this.aiService,
    required this.modelManager,
    required this.dispatcher,
    required this.selfChecker,
    this.isPage = false,
    required this.onSettingsChanged,
    this.gitHubService,
    this.storageService,
  });

  @override
  Widget build(BuildContext context) {
    final sessionType = isPage ? AiSessionType.page : AiSessionType.article;
    final repo = activeRepo;
    final fw = repo?.frameworkId;

    return Scaffold(
      appBar: AppBar(
        title: Text(isPage ? 'AI 页面创作' : 'AI 博文创作'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空对话',
            onPressed: () {
              // Handled via GlobalKey
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
        sessionType: sessionType,
        blogFramework: fw,
        postsPath: repo?.postsPath,
        pagesPath: repo?.pagesPath,
        gitHubService: gitHubService,
        activeRepo: repo,
        storageService: storageService,
        initialMessage: isPage
            ? '欢迎使用 AI 页面创作助手！\n\n你可以直接告诉我：\n• 创建关于我页面\n• 创建友链页面\n• 修改页面文案\n• 调整排版布局\n\n我会根据仓库框架「${fw ?? "未指定"}」自动生成符合规范的页面源码。'
            : '欢迎使用 AI 博文创作助手！\n\n你可以直接告诉我：\n• 新建文章：标题xxx，内容方向xxx\n• 优化全文、精简文字\n• 补充标签、分类、摘要\n• SEO优化标题与描述\n\n我会根据仓库框架「${fw ?? "未指定"}」自动生成符合规范的博文。',
        onSettingsChanged: onSettingsChanged,
      ),
    );
  }
}