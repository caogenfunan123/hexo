import 'package:flutter/material.dart';

import '../core/ai/ai_model_entity.dart';
import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/ai/ai_session_manager.dart';
import '../models/app_settings.dart';
import 'ai_model_picker.dart';
import '../screens/ai_model_manager_screen.dart';
import '../services/ai_service.dart';

/// 可复用的 AI 对话面板
/// 用于所有 AI 会话场景：文章、页面、主题、巡检、主题迁移
class AiChatPanel extends StatefulWidget {
  final AppSettings settings;
  final AiService aiService;
  final AiModelManager modelManager;
  final AiRequestDispatcher dispatcher;
  final AiSelfChecker? selfChecker;
  final AiSessionType sessionType;
  final String? blogFramework;
  final String? targetFramework;
  final String? postsPath;
  final String? pagesPath;
  final String? themesPath;
  final String? initialMessage;
  final bool selfCheckEnabled;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final List<Widget> Function(BuildContext, AiChatPanelState)? headerBuilder;
  final void Function(String content)? onContentGenerated;

  const AiChatPanel({
    super.key,
    required this.settings,
    required this.aiService,
    required this.modelManager,
    required this.dispatcher,
    this.selfChecker,
    required this.sessionType,
    this.blogFramework,
    this.targetFramework,
    this.postsPath,
    this.pagesPath,
    this.themesPath,
    this.initialMessage,
    this.selfCheckEnabled = true,
    required this.onSettingsChanged,
    this.headerBuilder,
    this.onContentGenerated,
  });

  @override
  State<AiChatPanel> createState() => AiChatPanelState();
}

class AiChatPanelState extends State<AiChatPanel> {
  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<ChatMessage> _messages = [];
  List<AiModelEntity> _models = [];
  AiModelEntity? _selectedModel;
  bool _busy = false;
  String? _status;

  List<ChatMessage> get messages => _messages;

  @override
  void initState() {
    super.initState();
    _loadModels();
    _initSession();
    if (widget.initialMessage != null) {
      _addSystemMessage(widget.initialMessage!);
    }
  }

  void _initSession() {
    widget.dispatcher.setSystemPrompt(
      AiSessionManager.getSystemPrompt(
        widget.sessionType,
        blogFramework: widget.blogFramework,
        postsPath: widget.postsPath,
        pagesPath: widget.pagesPath,
        themesPath: widget.themesPath,
        targetFramework: widget.targetFramework,
      ),
    );
  }

  Future<void> _loadModels() async {
    _models = await widget.modelManager.getEnabled();
    if (_models.isNotEmpty) {
      _selectedModel = _models.first;
    }
    if (mounted) setState(() {});
  }

  void _addSystemMessage(String text) {
    setState(() => _messages.add(ChatMessage(role: 'system', content: text)));
  }

  void _addUserMessage(String text) {
    setState(() => _messages.add(ChatMessage(role: 'user', content: text)));
    widget.dispatcher.addUserMessage(text);
  }

  void _addAssistantMessage(String text) {
    setState(() => _messages.add(ChatMessage(role: 'assistant', content: text)));
    widget.dispatcher.addAssistantMessage(text);
  }

  void addMessage(String role, String text) {
    setState(() => _messages.add(ChatMessage(role: role, content: text)));
  }

  Future<void> sendMessage([String? text]) async {
    final msg = text ?? _chatCtrl.text.trim();
    if (msg.isEmpty || _busy) return;
    _chatCtrl.clear();

    _addUserMessage(msg);
    widget.onContentGenerated?.call(msg);

    setState(() {
      _busy = true;
      _status = 'AI 思考中...';
    });

    _scrollToBottom();

    try {
      final result = await widget.dispatcher.dispatch(
        settings: widget.settings,
        userMessage: msg,
        preferredModel: _selectedModel,
        maxRetries: 3,
        enableAutoSwitch: true,
      );

      _addAssistantMessage(result.content);
      widget.onContentGenerated?.call(result.content);

      if (result.switched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已自动切换到备选模型: ${result.usedModel}')),
        );
      }

      // Self-check
      if (widget.selfCheckEnabled && widget.selfChecker != null) {
        final checkResult = await widget.selfChecker!.check(
          settings: widget.settings,
          generatedContent: result.content,
          sessionType: widget.sessionType,
          blogFramework: widget.blogFramework,
        );
        if (checkResult.hasError) {
          _addAssistantMessage('⚠️ 自检发现问题：\n${checkResult.issues.join('\n')}');
        }
      }
    } catch (e) {
      _addAssistantMessage('❌ 请求失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('所有模型请求失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void clearHistory() {
    widget.dispatcher.clearHistory();
    setState(() => _messages.clear());
  }

  @override
  void dispose() {
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (_busy)
          LinearProgressIndicator(minHeight: 2, color: cs.primary),
        // 自定义头部
        if (widget.headerBuilder != null)
          ...widget.headerBuilder!(context, this),
        // 消息列表
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 48, color: cs.outline.withOpacity(0.4)),
                      const SizedBox(height: 12),
                      Text(
                        _emptyHint,
                        style: TextStyle(fontSize: 14, color: cs.outline),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '输入你的需求开始对话',
                        style: TextStyle(fontSize: 12, color: cs.outline.withOpacity(0.6)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (ctx, i) => _buildBubble(_messages[i], cs),
                ),
        ),
        // 状态栏
        if (_status != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: cs.primaryContainer.withOpacity(0.5),
            child: Row(
              children: [
                if (_busy) ...[
                  SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(_status!, style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
                ),
              ],
            ),
          ),
        // 输入栏
        _buildInput(cs),
        // 模型选择器
        AiModelBottomBar(
          models: _models,
          selectedModel: _selectedModel,
          onChanged: (m) => setState(() => _selectedModel = m),
          onManageModels: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AiModelManagerScreen(
                  modelManager: widget.modelManager,
                  aiService: widget.aiService,
                  settings: widget.settings,
                  onSettingsChanged: widget.onSettingsChanged,
                ),
              ),
            ).then((_) => _loadModels());
          },
        ),
      ],
    );
  }

  String get _emptyHint {
    switch (widget.sessionType) {
      case AiSessionType.article:
        return 'AI 博文创作助手';
      case AiSessionType.page:
        return 'AI 页面编辑助手';
      case AiSessionType.theme:
        return 'AI 主题开发助手';
      case AiSessionType.themeMigration:
        return 'AI 主题迁移助手';
      case AiSessionType.audit:
        return 'AI 站点巡检助手';
    }
  }

  Widget _buildInput(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatCtrl,
              decoration: const InputDecoration(
                hintText: '输入指令...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _busy ? null : () => sendMessage(),
            icon: _busy
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg, ColorScheme cs) {
    final isUser = msg.role == 'user';
    final isSystem = msg.role == 'system';
    final isAssistant = msg.role == 'assistant';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? cs.primaryContainer
              : isSystem
                  ? cs.surfaceContainerHighest
                  : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isSystem)
              Text(msg.content, style: TextStyle(fontSize: 13, color: cs.outline))
            else
              SelectableText(
                msg.content,
                style: TextStyle(
                  fontSize: 14,
                  color: isUser ? cs.onPrimaryContainer : cs.onSurface,
                  fontFamily: isAssistant ? 'monospace' : null,
                  height: 1.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatMessage {
  final String role;
  final String content;
  final DateTime time;

  ChatMessage({required this.role, required this.content, DateTime? time})
      : time = time ?? DateTime.now();
}