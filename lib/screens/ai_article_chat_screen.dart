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
class AiArticleChatScreen extends StatefulWidget {
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
  State<AiArticleChatScreen> createState() => _AiArticleChatScreenState();
}

class _AiArticleChatScreenState extends State<AiArticleChatScreen> {
  final GlobalKey<AiChatPanelState> _chatKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final sessionType = widget.isPage ? AiSessionType.page : AiSessionType.article;
    final repo = widget.activeRepo;
    final fw = repo?.frameworkId;

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isPage ? 'AI 页面创作' : 'AI 博文创作'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空对话',
              onPressed: () {
                showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空对话'),
                    content: const Text('确定要清空当前对话历史吗？此操作不可撤销。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                ).then((confirmed) {
                  if (confirmed == true) {
                    _chatKey.currentState?.clearHistory();
                  }
                });
              },
            ),
          ],
        ),
        body: AiChatPanel(
          key: _chatKey,
          settings: widget.settings,
          aiService: widget.aiService,
          modelManager: widget.modelManager,
          dispatcher: widget.dispatcher,
          selfChecker: widget.selfChecker,
          sessionType: sessionType,
          blogFramework: fw,
          postsPath: repo?.postsPath,
          pagesPath: repo?.pagesPath,
          gitHubService: widget.gitHubService,
          activeRepo: repo,
          storageService: widget.storageService,
          initialMessage: widget.isPage
              ? '欢迎使用 AI 页面创作助手！\n\n你可以直接告诉我：\n• 创建关于我页面\n• 创建友链页面\n• 修改页面文案\n• 调整排版布局\n\n我会根据仓库框架「${fw ?? "未指定"}」自动生成符合规范的页面源码。'
              : '欢迎使用 AI 博文创作助手！\n\n你可以直接告诉我：\n• 新建文章：标题xxx，内容方向xxx\n• 优化全文、精简文字\n• 补充标签、分类、摘要\n• SEO优化标题与描述\n\n我会根据仓库框架「${fw ?? "未指定"}」自动生成符合规范的博文。',
          onSettingsChanged: widget.onSettingsChanged,
        ),
      ),
    );
  }
}