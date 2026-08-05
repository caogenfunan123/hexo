import 'package:flutter/material.dart';

import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/ai/ai_session_manager.dart';
import '../models/app_settings.dart';
import '../models/design_config.dart';
import '../models/repo_config.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import '../widgets/ai_chat_panel.dart';

/// AI 应用 UI 设计对话页面
///
/// 独立会话，AI 通过 read_app_config / update_app_config 工具
/// 实时读取和修改应用界面的设计配置（颜色、布局、字号、密度等）。
class AiAppDesignScreen extends StatelessWidget {
  final AppSettings settings;
  final RepoConfig? activeRepo;
  final AiService aiService;
  final AiModelManager modelManager;
  final AiRequestDispatcher dispatcher;
  final AiSelfChecker selfChecker;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final GitHubService? gitHubService;
  final StorageService? storageService;

  const AiAppDesignScreen({
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
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AI 应用 UI 设计'),
          actions: [
            IconButton(
              icon: const Icon(Icons.palette_outlined),
              tooltip: '重置为默认',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('重置设计配置'),
                    content: const Text('将所有 UI 设计配置恢复为默认值，包括颜色、圆角、字号、密度等。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx, true);
                        },
                        child: const Text('确认重置'),
                      ),
                    ],
                  ),
                ).then((confirmed) {
                  if (confirmed == true) {
                    onSettingsChanged(
                      settings.copyWith(
                        ui: settings.ui.copyWith(
                          designConfig: const DesignConfig(),
                        ),
                      ),
                    );
                  }
                });
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
          sessionType: AiSessionType.appDesign,
          onSettingsChanged: onSettingsChanged,
          gitHubService: gitHubService,
          activeRepo: activeRepo,
          storageService: storageService,
          selfCheckEnabled: false,
          initialMessage: '欢迎使用 AI 应用 UI 设计助手！\n\n'
              '我可以帮你调整这个应用本身的界面外观，你可以直接告诉我：\n'
              '• 换成紫色主题\n'
              '• 界面紧凑一点\n'
              '• 圆角大一点，更有圆润感\n'
              '• 字号调大一些\n'
              '• 推荐一个护眼配色方案\n'
              '• 极简风格\n'
              '• 圆润可爱风\n'
              '• 查看当前配置\n'
              '• 重置为默认\n\n'
              '我会先读取当前配置，再给出调整建议并实时应用修改。',
        ),
      ),
    );
  }
}
