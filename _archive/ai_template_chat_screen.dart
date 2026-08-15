import 'package:flutter/material.dart';

import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/ai/ai_session_manager.dart';
import '../models/app_settings.dart';
import '../models/repo_config.dart';
import '../models/template_item.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import '../widgets/ai_chat_panel.dart';

/// AI 文章模板与博客框架对话页面
class AiTemplateChatScreen extends StatefulWidget {
  final AppSettings settings;
  final RepoConfig? activeRepo;
  final AiService aiService;
  final AiModelManager modelManager;
  final AiRequestDispatcher dispatcher;
  final AiSelfChecker selfChecker;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final GitHubService? gitHubService;
  final StorageService? storageService;

  /// 模板被 update_template 修改后的回调（宿主应用刷新模板列表）
  final Future<void> Function(List<TemplateItem> templates)? onTemplatesChanged;

  const AiTemplateChatScreen({
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
    this.onTemplatesChanged,
  });

  @override
  State<AiTemplateChatScreen> createState() => _AiTemplateChatScreenState();
}

class _AiTemplateChatScreenState extends State<AiTemplateChatScreen> {
  final GlobalKey<AiChatPanelState> _chatKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final repo = widget.activeRepo;
    final fw = repo?.frameworkId;
    final fileNameRuleDesc = repo == null
        ? null
        : '博文文件名${repo.fileNameRule.postDatePrefix ? '需要' : '不需要'} YYYY-MM-DD 日期前缀 (${repo.fileNameRule.dateFormat})';

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AI 模板与博客框架'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空对话',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空聊天记录'),
                    content: const Text('确认清空所有聊天记录？此操作不可撤销。'),
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
                );
                if (confirmed == true) {
                  _chatKey.currentState?.clearHistory();
                }
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
          sessionType: AiSessionType.template,
          blogFramework: fw,
          postsPath: repo?.postsPath,
          pagesPath: repo?.pagesPath,
          themesPath: 'themes',
          defaultPostTemplateId: repo?.defaultPostTemplateId,
          defaultPageTemplateId: repo?.defaultPageTemplateId,
          fileNameRuleDesc: fileNameRuleDesc,
          gitHubService: widget.gitHubService,
          activeRepo: repo,
          storageService: widget.storageService,
          onTemplatesChanged: widget.onTemplatesChanged,
          initialMessage: '欢迎使用 AI 模板与博客框架助手！\n\n'
              '我可以读取您绑定的博客仓库代码，诊断「文章发布后博客上不显示」的根因，并直接修复文章模板与博客框架。\n\n'
              '你可以直接告诉我：\n'
              '• 分析为什么我的文章发布后不显示\n'
              '• 查看当前仓库的框架配置和文章 FrontMatter\n'
              '• 修复文章模板以适配 ${fw ?? "当前框架"}\n'
              '• 修改仓库中的博客框架/主题文件\n'
              '• 按主题要求补全模板字段（cover、layout 等）\n\n'
              '当前框架：${fw ?? "未指定"} | 文章目录：${repo?.postsPath ?? "未指定"}',
          onSettingsChanged: widget.onSettingsChanged,
        ),
      ),
    );
  }
}
