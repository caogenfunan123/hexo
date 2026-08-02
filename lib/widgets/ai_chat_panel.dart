import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/ai/ai_model_entity.dart';
import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/ai/ai_session_manager.dart';
import '../models/app_settings.dart';
import '../models/repo_config.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import 'ai_model_picker.dart';
import '../screens/ai_model_manager_screen.dart';

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

  /// 👇 文件执行能力：Git 服务 + 仓库配置
  final GitHubService? gitHubService;
  final RepoConfig? activeRepo;

  /// 👇 对话持久化：本地存储
  final StorageService? storageService;

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
    this.gitHubService,
    this.activeRepo,
    this.storageService,
  });

  @override
  State<AiChatPanel> createState() => AiChatPanelState();
}

/// 解析出的文件操作
class ParsedFileOp {
  final String path;
  final String content;
  final String language;
  bool written;
  String? writeError;

  ParsedFileOp({
    required this.path,
    required this.content,
    this.language = 'text',
    this.written = false,
    this.writeError,
  });
}

class AiChatPanelState extends State<AiChatPanel> {
  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<ChatMessage> _messages = [];
  List<AiModelEntity> _models = [];
  AiModelEntity? _selectedModel;
  bool _busy = false;
  String? _status;

  /// 每个 assistant 消息对应的解析文件列表（按消息索引）
  final Map<int, List<ParsedFileOp>> _parsedFiles = {};
  bool _writeBusy = false;

  List<ChatMessage> get messages => _messages;

  @override
  void initState() {
    super.initState();
    _loadModels();
    _initSession();
    _loadHistory();
  }

  String get _chatFileKey => 'ai_chat_${widget.sessionType.name}.json';

  /// 加载已保存的对话历史
  Future<void> _loadHistory() async {
    final storage = widget.storageService;
    if (storage == null) return;
    try {
      final file = File('${(await storage.root).path}/$_chatFileKey');
      if (!await file.exists()) {
        // 首次打开，显示欢迎语
        if (widget.initialMessage != null) {
          _addSystemMessage(widget.initialMessage!);
        }
        return;
      }
      final text = await file.readAsString();
      if (text.trim().isEmpty) {
        if (widget.initialMessage != null) {
          _addSystemMessage(widget.initialMessage!);
        }
        return;
      }
      final list = jsonDecode(text);
      if (list is! List) return;
      final messages = list
          .whereType<Map>()
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (messages.isEmpty) {
        if (widget.initialMessage != null) {
          _addSystemMessage(widget.initialMessage!);
        }
        return;
      }
      setState(() => _messages.addAll(messages));
      // 恢复 dispatcher 上下文
      for (final m in messages) {
        if (m.role == 'user') {
          widget.dispatcher.addUserMessage(m.content);
        } else if (m.role == 'assistant') {
          widget.dispatcher.addAssistantMessage(m.content);
        }
      }
      // 重新解析已有 assistant 消息中的文件操作
      for (int i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        if (m.role == 'assistant') {
          final files = _parseFileOps(m.content);
          if (files.isNotEmpty) {
            _parsedFiles[i] = files;
          }
        }
      }
    } catch (_) {
      if (widget.initialMessage != null && _messages.isEmpty) {
        _addSystemMessage(widget.initialMessage!);
      }
    }
  }

  /// 保存对话历史到本地文件
  Future<void> _saveHistory() async {
    final storage = widget.storageService;
    if (storage == null) return;
    try {
      final file = File('${(await storage.root).path}/$_chatFileKey');
      final json = jsonEncode(_messages.map((m) => m.toJson()).toList());
      await file.writeAsString(json);
    } catch (_) {}
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
    _saveHistory();
  }

  void _addUserMessage(String text) {
    setState(() => _messages.add(ChatMessage(role: 'user', content: text)));
    widget.dispatcher.addUserMessage(text);
    _saveHistory();
  }

  void _addAssistantMessage(String text) {
    setState(() => _messages.add(ChatMessage(role: 'assistant', content: text)));
    widget.dispatcher.addAssistantMessage(text);
    _saveHistory();
  }

  void addMessage(String role, String text) {
    setState(() => _messages.add(ChatMessage(role: role, content: text)));
    _saveHistory();
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

      // 解析 AI 回复中的文件操作
      final files = _parseFileOps(result.content);
      if (files.isNotEmpty) {
        _parsedFiles[_messages.length - 1] = files;
        setState(() {}); // 刷新以显示写入按钮
      }

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
    _parsedFiles.clear();
    setState(() => _messages.clear());
    // 删除本地持久化文件
    _deleteHistoryFile();
  }

  Future<void> _deleteHistoryFile() async {
    final storage = widget.storageService;
    if (storage == null) return;
    try {
      final file = File('${(await storage.root).path}/$_chatFileKey');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 解析 AI 回复中的【文件路径】标记，提取文件操作
  List<ParsedFileOp> _parseFileOps(String content) {
    final files = <ParsedFileOp>[];
    final lines = content.split('\n');
    String? currentPath;
    StringBuffer? currentContent;
    String? currentLang;

    for (final line in lines) {
      // 匹配 【文件路径】themes/xxx/file.ext
      final pathMatch = RegExp(r'【文件路径】\s*(.+)').firstMatch(line);
      if (pathMatch != null) {
        if (currentPath != null && currentContent != null) {
          files.add(ParsedFileOp(
            path: currentPath,
            content: currentContent.toString().trim(),
            language: currentLang ?? 'text',
          ));
        }
        currentPath = pathMatch.group(1)!.trim();
        currentContent = StringBuffer();
        currentLang = 'text';
        continue;
      }

      // 代码块开始
      final codeStart = RegExp(r'^```(\w+)?').firstMatch(line);
      if (codeStart != null && currentPath != null) {
        currentLang = codeStart.group(1) ?? 'text';
        continue;
      }

      // 代码块结束
      if (line.trim() == '```' && currentPath != null) {
        continue;
      }

      if (currentPath != null && currentContent != null) {
        currentContent.writeln(line);
      }
    }

    // 保存最后一个文件
    if (currentPath != null && currentContent != null) {
      files.add(ParsedFileOp(
        path: currentPath,
        content: currentContent.toString().trim(),
        language: currentLang ?? 'text',
      ));
    }

    return files;
  }

  /// 写入单个文件到 Git 仓库
  Future<void> _writeSingleFile(ParsedFileOp file) async {
    final repo = widget.activeRepo;
    final git = widget.gitHubService;
    if (repo == null || git == null) {
      throw Exception('未配置 Git 仓库');
    }
    await git.putRawFile(
      repo,
      file.path,
      file.content,
      commitMessage: 'ai: create ${file.path}',
    );
    file.written = true;
  }

  /// 写入所有已解析文件到 Git 仓库
  Future<void> _writeAllFiles(int msgIndex) async {
    final files = _parsedFiles[msgIndex];
    if (files == null || files.isEmpty) return;
    if (_writeBusy) return;

    final repo = widget.activeRepo;
    final git = widget.gitHubService;
    if (repo == null || git == null) {
      _addAssistantMessage('❌ 未配置 Git 仓库，无法写入文件。请先在设置中关联仓库。');
      return;
    }

    setState(() {
      _writeBusy = true;
      _status = '正在写入 ${files.length} 个文件...';
    });

    int success = 0;
    int fail = 0;
    final errors = <String>[];

    for (final file in files) {
      if (file.written) {
        success++;
        continue;
      }
      try {
        await git.putRawFile(
          repo,
          file.path,
          file.content,
          commitMessage: 'ai: create ${file.path}',
        );
        file.written = true;
        success++;
      } catch (e) {
        file.writeError = e.toString();
        fail++;
        errors.add('${file.path}: $e');
      }
    }

    setState(() {
      _writeBusy = false;
      _status = null;
    });

    if (fail == 0) {
      _addAssistantMessage('✅ 已成功写入 $success 个文件到仓库。\n\n请推送远端构建测试。');
    } else {
      _addAssistantMessage('⚠️ 写入完成：$success 成功 / $fail 失败\n\n${errors.map((e) => '• $e').join('\n')}');
    }
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
    final msgIndex = _messages.indexOf(msg);
    final fileOps = _parsedFiles[msgIndex];
    final hasFiles = fileOps != null && fileOps.isNotEmpty;
    final allWritten = hasFiles && fileOps.every((f) => f.written);
    final canWrite = widget.gitHubService != null && widget.activeRepo != null;

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
            // 👇 文件操作按钮
            if (hasFiles && isAssistant) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
              const SizedBox(height: 8),
              // 文件列表摘要
              ...fileOps.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Icon(
                      f.written ? Icons.check_circle : Icons.insert_drive_file_outlined,
                      size: 14,
                      color: f.written ? Colors.green : cs.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        f.path,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: f.written ? Colors.green : cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${f.content.length} 字符',
                      style: TextStyle(fontSize: 10, color: cs.outline),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 8),
              // 写入按钮
              if (!allWritten && canWrite)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _writeBusy ? null : () => _writeAllFiles(msgIndex),
                    icon: _writeBusy
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cloud_upload_outlined, size: 16),
                    label: Text('写入 ${fileOps.where((f) => !f.written).length} 个文件到仓库'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              if (allWritten)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: Colors.green),
                      SizedBox(width: 6),
                      Text('已写入仓库', style: TextStyle(fontSize: 12, color: Colors.green)),
                    ],
                  ),
                ),
              if (!canWrite && hasFiles)
                Text(
                  '⚠️ 未关联 Git 仓库，无法写入',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
            ],
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

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'time': time.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j['role']?.toString() ?? 'system',
        content: j['content']?.toString() ?? '',
        time: DateTime.tryParse(j['time']?.toString() ?? '') ?? DateTime.now(),
      );
}