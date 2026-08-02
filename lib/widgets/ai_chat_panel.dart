import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _isThinking = false;
  String? _status;

  /// 每个 assistant 消息对应的解析文件列表（按消息索引）
  final Map<int, List<ParsedFileOp>> _parsedFiles = {};
  bool _writeBusy = false;

  /// 流式相关
  StreamSubscription<void>? _streamSub;
  StringBuffer _streamBuffer = StringBuffer();
  int? _streamingMsgIndex;

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
      // 优先使用全局持久化的默认模型
      final savedId = widget.settings.defaultModelId;
      final savedBase = widget.settings.defaultModelBase;
      if (savedId.isNotEmpty && savedBase.isNotEmpty) {
        _selectedModel = _models.firstWhere(
          (m) => m.modelId == savedId && m.apiBase == savedBase,
          orElse: () => _models.first,
        );
      }
      _selectedModel ??= _models.first;
    }
    if (mounted) setState(() {});
  }

  void _addSystemMessage(String text) {
    setState(() => _messages.add(ChatMessage(role: 'system', content: text)));
    _saveHistory();
    _scrollToBottom();
  }

  void _addUserMessage(String text) {
    setState(() => _messages.add(ChatMessage(role: 'user', content: text)));
    widget.dispatcher.addUserMessage(text);
    _saveHistory();
    _scrollToBottom();
  }

  void _addAssistantMessage(String text) {
    setState(() => _messages.add(ChatMessage(role: 'assistant', content: text)));
    widget.dispatcher.addAssistantMessage(text);
    _saveHistory();
    _scrollToBottom();
  }

  void addMessage(String role, String text) {
    setState(() => _messages.add(ChatMessage(role: role, content: text)));
    if (role == 'user') {
      widget.dispatcher.addUserMessage(text);
    } else if (role == 'assistant') {
      widget.dispatcher.addAssistantMessage(text);
    }
    _saveHistory();
  }

  Future<void> sendMessage([String? text]) async {
    final msg = text ?? _chatCtrl.text.trim();
    if (msg.isEmpty || _busy) return;
    _chatCtrl.clear();

    // 添加用户消息到 UI（dispatcher 在 dispatchStream 内部也添加）
    setState(() => _messages.add(ChatMessage(role: 'user', content: msg)));
    widget.onContentGenerated?.call(msg);
    _saveHistory();

    // 先添加一个空 assistant 消息，后续流式填充
    _streamBuffer = StringBuffer();
    setState(() {
      _messages.add(ChatMessage(role: 'assistant', content: ''));
      _streamingMsgIndex = _messages.length - 1;
      _busy = true;
      _isThinking = true;
      _status = '思考中...';
    });

    _scrollToBottom();

    try {
      final stream = widget.dispatcher.dispatchStream(
        settings: widget.settings,
        userMessage: msg,
        preferredModel: _selectedModel,
      );

      _streamSub = stream.listen(
        (chunk) {
          if (!mounted) return;
          if (chunk.isDone) {
            _finishStreaming();
            return;
          }
          if (chunk.content.isNotEmpty) {
            _streamBuffer.write(chunk.content);
            final idx = _streamingMsgIndex;
            if (idx != null && idx < _messages.length) {
              setState(() {
                _isThinking = false;
                _status = '生成中...';
                _messages[idx] = ChatMessage(
                  role: 'assistant',
                  content: _streamBuffer.toString(),
                  time: _messages[idx].time,
                );
              });
              _scrollToBottom();
            }
          }
        },
        onError: (e) {
          if (!mounted) return;
          final idx = _streamingMsgIndex;
          if (idx != null && idx < _messages.length) {
            setState(() {
              _messages[idx] = ChatMessage(
                role: 'assistant',
                content: _streamBuffer.isNotEmpty
                    ? '${_streamBuffer.toString()}\n\n---\n❌ 请求失败: $e'
                    : '❌ 请求失败: $e',
                time: _messages[idx].time,
              );
            });
          }
          _finishStreaming(error: true);
          _saveHistory();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('请求失败: $e')),
            );
          }
        },
        onDone: () {
          if (!mounted) return;
          _finishStreaming();
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (!mounted) return;
      _addAssistantMessage('❌ 请求失败: $e');
      _finishStreaming(error: true);
    }
  }

  /// 取消当前流式请求
  void _cancelStream() {
    _streamSub?.cancel();
    _streamSub = null;
    widget.dispatcher.cancelCurrent();
    final idx = _streamingMsgIndex;
    if (idx != null && idx < _messages.length) {
      final hasContent = _streamBuffer.isNotEmpty;
      if (hasContent) {
        widget.dispatcher.addAssistantMessage(_streamBuffer.toString());
      }
      setState(() {
        _messages[idx] = ChatMessage(
          role: 'assistant',
          content: hasContent
              ? '${_streamBuffer.toString()}\n\n---\n⚠️ *已打断*'
              : '⚠️ *已打断*',
          time: _messages[idx].time,
        );
      });
    }
    _finishStreaming();
  }

  void _finishStreaming({bool error = false}) {
    _streamSub?.cancel();
    _streamSub = null;
    final idx = _streamingMsgIndex;
    if (idx != null && idx < _messages.length && !error) {
      final content = _streamBuffer.toString();
      // 解析文件操作
      final files = _parseFileOps(content);
      if (files.isNotEmpty) {
        _parsedFiles[idx] = files;
      }
      // 持久化
      _saveHistory();
      // 自检
      if (widget.selfCheckEnabled && widget.selfChecker != null) {
        widget.selfChecker!.check(
          settings: widget.settings,
          generatedContent: content,
          sessionType: widget.sessionType,
          blogFramework: widget.blogFramework,
        ).then((checkResult) {
          if (mounted && checkResult.hasError) {
            _addAssistantMessage('⚠️ 自检发现问题：\n${checkResult.issues.join('\n')}');
          }
        });
      }
    }
    setState(() {
      _busy = false;
      _isThinking = false;
      _status = null;
      _streamingMsgIndex = null;
    });
    _streamBuffer = StringBuffer();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    // 双重 postFrame 回调：确保新消息及其按钮（复制/写入）完成布局后再滚动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        final max = _scrollCtrl.position.maxScrollExtent;
        if (max > 0) {
          _scrollCtrl.animateTo(
            max,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
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
    _streamSub?.cancel();
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
          onChanged: (m) {
            setState(() => _selectedModel = m);
            // 持久化全局默认模型
            if (m != null) {
              widget.onSettingsChanged(
                widget.settings.copyWith(
                  defaultModelId: m.modelId,
                  defaultModelBase: m.apiBase,
                ),
              );
            }
          },
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
              enabled: !_busy,
              onSubmitted: _busy ? null : (_) => sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          if (_busy)
            IconButton.filled(
              onPressed: _cancelStream,
              style: IconButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.stop),
              tooltip: '打断对话',
            )
          else
            IconButton.filled(
              onPressed: () => sendMessage(),
              icon: const Icon(Icons.send),
            ),
        ],
      ),
    );
  }

  /// 思考动画：跳动的三个点
  Widget _buildThinkingAnimation(ColorScheme cs) {
    return _ThinkingDots(color: cs.primary);
  }

  /// 消息内容：支持流式光标
  Widget _buildMessageContent(ChatMessage msg, ColorScheme cs, bool isUser, bool isAssistant, bool isStreaming) {
    if (isStreaming && isAssistant) {
      return _StreamingText(
        text: msg.content,
        cs: cs,
        showCursor: true,
      );
    }
    return SelectableText(
      msg.content,
      style: TextStyle(
        fontSize: 14,
        color: isUser ? cs.onPrimaryContainer : cs.onSurface,
        fontFamily: isAssistant ? 'monospace' : null,
        height: 1.5,
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg, ColorScheme cs) {
    final isUser = msg.role == 'user';
    final isSystem = msg.role == 'system';
    final isAssistant = msg.role == 'assistant';
    final msgIndex = _messages.indexOf(msg);
    final isStreaming = msgIndex == _streamingMsgIndex && _busy;
    final isThinkingBubble = isStreaming && _isThinking && msg.content.isEmpty;
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
            else if (isThinkingBubble)
              _buildThinkingAnimation(cs)
            else
              _buildMessageContent(msg, cs, isUser, isAssistant, isStreaming),
            // 👇 复制按钮（仅 AI 回复，且有内容）
            if (isAssistant && msg.content.isNotEmpty && !isThinkingBubble) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: msg.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制到剪贴板'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy, size: 12, color: cs.outline),
                        const SizedBox(width: 4),
                        Text('复制', style: TextStyle(fontSize: 11, color: cs.outline)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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

/// 思考动画：三个跳动的点
class _ThinkingDots extends StatefulWidget {
  final Color color;
  const _ThinkingDots({required this.color});

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animations = List.generate(3, (i) {
      return Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(i * 0.2, 0.6 + i * 0.2, curve: Curves.easeInOut),
        ),
      );
    });
    _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('思考中', style: TextStyle(fontSize: 13, color: widget.color.withOpacity(0.7))),
        const SizedBox(width: 6),
        ...List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _animations[i],
            builder: (_, child) => Padding(
              padding: EdgeInsets.only(left: i > 0 ? 3 : 0),
              child: Opacity(
                opacity: _animations[i].value,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// 流式文本：带闪烁光标
class _StreamingText extends StatefulWidget {
  final String text;
  final ColorScheme cs;
  final bool showCursor;

  const _StreamingText({required this.text, required this.cs, required this.showCursor});

  @override
  State<_StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<_StreamingText> with SingleTickerProviderStateMixin {
  late AnimationController _cursorCtrl;

  @override
  void initState() {
    super.initState();
    _cursorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _cursorCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _cursorCtrl,
      builder: (_, child) {
        return RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 14,
              color: widget.cs.onSurface,
              fontFamily: 'monospace',
              height: 1.5,
            ),
            children: [
              TextSpan(text: widget.text),
              if (widget.showCursor)
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Opacity(
                    opacity: _cursorCtrl.value,
                    child: Container(
                      width: 2,
                      height: 16,
                      margin: const EdgeInsets.only(left: 1),
                      decoration: BoxDecoration(
                        color: widget.cs.primary,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}