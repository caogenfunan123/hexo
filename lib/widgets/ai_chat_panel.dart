import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ai/ai_model_entity.dart';
import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/ai/ai_session_manager.dart';
import '../core/ai/ai_tool_manager.dart';
import '../core/ai/token_vault.dart';
import '../core/tools/instruction_parser.dart';
import '../core/tools/mcp_runtime.dart';
import '../core/tools/mcp_server.dart';
import '../core/tools/skill_manager.dart';
import '../core/tools/tool_entity.dart';
import '../core/tools/tool_registry.dart';
import '../core/tools/builtin_tools.dart';
import '../models/app_settings.dart';
import '../models/repo_config.dart';
import '../models/template_item.dart';
import '../models/wizard_models.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/site_wizard_service.dart';
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
  final String? defaultPostTemplateId;
  final String? defaultPageTemplateId;
  final String? fileNameRuleDesc;
  final String? initialMessage;
  final bool selfCheckEnabled;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final List<Widget> Function(BuildContext, AiChatPanelState)? headerBuilder;
  final void Function(String content)? onContentGenerated;
  final void Function(List<ToolCallRequest> requests, List<ToolCallResult> results)? onToolsExecuted;
  final void Function(List<ParsedFileOp> files)? onFileOpsParsed;
  final void Function(List<ParsedFileOp> files)? onFilesWritten;

  /// 附件入口回调：宿主在工作台对话页提供「添加附件」按钮（点击弹文件选择）
  final VoidCallback? onAttach;

  /// 👇 文件执行能力：Git 服务 + 仓库配置
  final GitHubService? gitHubService;
  final RepoConfig? activeRepo;

  /// 👇 对话持久化：本地存储
  final StorageService? storageService;
  final String? historyKey;

  /// 模板被 update_template 工具修改后的回调（宿主应用刷新模板列表）
  final Future<void> Function(List<TemplateItem> templates)? onTemplatesChanged;

  /// 一键建站成功后的站点持久化回调（宿主注册令牌 + 站点入站点管理）
  final Future<void> Function(WizardResult)? onSiteCreated;

  /// 建站持久化完成后刷新宿主站点列表（保存新站点后同步内存与 UI）
  final Future<void> Function(List<RepoConfig> repos)? onSiteSaved;

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
    this.defaultPostTemplateId,
    this.defaultPageTemplateId,
    this.fileNameRuleDesc,
    this.initialMessage,
    this.selfCheckEnabled = true,
    required this.onSettingsChanged,
    this.headerBuilder,
    this.onContentGenerated,
    this.onToolsExecuted,
    this.onFileOpsParsed,
    this.onFilesWritten,
    this.onAttach,
    this.gitHubService,
    this.activeRepo,
    this.storageService,
    this.historyKey,
    this.onTemplatesChanged,
    this.onSiteCreated,
    this.onSiteSaved,
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

  ParsedFileOp copy() => ParsedFileOp(
        path: path,
        content: content,
        language: language,
        written: written,
        writeError: writeError,
      );
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
  bool _showScrollButton = false;

  /// 每个 assistant 消息对应的解析文件列表（按消息索引）
  final Map<int, List<ParsedFileOp>> _parsedFiles = {};
  bool _writeBusy = false;

  /// 流式相关
  StreamSubscription<void>? _streamSub;
  StringBuffer _streamBuffer = StringBuffer();
  StringBuffer _reasoningBuffer = StringBuffer();
  int? _streamingMsgIndex;

  /// 工具调用卡片展开状态（按 callId）
  final Set<String> _expandedToolCalls = {};

  /// 工具调用执行状态（按 callId）：running / success / failure
  final Map<String, _ToolCallUiState> _toolCallStates = {};

  /// 工具执行结果摘要（按 callId）
  final Map<String, ToolCallResult> _toolCallResults = {};

  /// 工具系统
  late final SkillManager _skillManager;
  late final McpRuntime _mcpRuntime;
  late final AiToolManager _toolManager;
  bool _toolsInitialized = false;

  /// 模型切换事件（提示条）
  SwitchEvent? _lastSwitchEvent;

  /// 当前实际使用的模型（自动择优时可能切换）
  AiModelEntity? _activeModel;

  /// 技能选择：选中的技能 ID 集合。null/空 = 全部启用（保持向后兼容）
  Set<String>? _selectedSkillIds;

  /// 思考块手动折叠覆盖（按 reasoning 内容）：用户手动点击后的状态
  final Map<String, bool> _collapsedReasoning = {};

  List<ChatMessage> get messages => _messages;

  @override
  void initState() {
    super.initState();
    _skillManager = SkillManager();
    _toolManager = AiToolManager();
    _mcpRuntime = McpRuntime(
      _skillManager,
      ToolRegistry(),
      siteId: widget.activeRepo?.id ?? '',
      allowAutoSave: widget.settings.ai.aiAllowAutoSaveTools,
      onHighRiskConfirm: _mcpHighRiskConfirm,
    );
    _initTools();
    _loadModels();
    _initSession();
    _loadHistory();
    _scrollCtrl.addListener(_onScroll);
    _bindDispatcherCallbacks();
  }

  @override
  void didUpdateWidget(covariant AiChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final historyScopeChanged =
        oldWidget.historyKey != widget.historyKey ||
        oldWidget.sessionType != widget.sessionType ||
        oldWidget.settings.effectiveActiveSiteId !=
            widget.settings.effectiveActiveSiteId;
    final dispatcherChanged = oldWidget.dispatcher != widget.dispatcher;
    if (dispatcherChanged) {
      oldWidget.dispatcher.onModelSwitched = null;
      oldWidget.dispatcher.onToolsExecuted = null;
      oldWidget.dispatcher.onToolConfirm = null;
      _bindDispatcherCallbacks();
    }
    if (historyScopeChanged || dispatcherChanged) {
      _reloadHistoryScope();
    }
  }

  void _bindDispatcherCallbacks() {
    // 模型切换事件 → 提示条 + 更新实际模型
    widget.dispatcher.onModelSwitched = (event) {
      if (!mounted) return;
      setState(() {
        _lastSwitchEvent = event;
        if (_selectedModel != null) {
          _activeModel = _selectedModel;
        }
      });
      _addSystemMessage('🔄 ${event.reason}\n已自动切换至「${event.toModel}」继续处理');
    };
    widget.dispatcher.onToolsExecuted = (requests, results) {
      if (mounted) {
        setState(() {
          for (var i = 0; i < requests.length; i++) {
            final r = requests[i];
            final result = i < results.length ? results[i] : null;
            _toolCallStates[r.callId] = (result == null || result.success)
                ? _ToolCallUiState.success
                : _ToolCallUiState.failure;
            if (result != null) _toolCallResults[r.callId] = result;
          }
        });
      }
      widget.onToolsExecuted?.call(requests, results);
    };
    // 高风险工具执行前确认（对标 MonkeyCode ask_user_question）。
    // 由设置 aiConfirmHighRiskTools 控制：默认关闭 = AI 全权，直接执行
    widget.dispatcher.onToolConfirm = widget.settings.ai.aiConfirmHighRiskTools
        ? (request, toolName, argSummary) => _confirmToolExecution(
              request,
              toolName,
              argSummary,
            )
        : null;
  }

  /// MCP 指令执行高风险工具时复用同一确认框
  Future<bool> _mcpHighRiskConfirm(
    ToolCallRequest request,
    String toolName,
    String argSummary,
  ) {
    if (!widget.settings.ai.aiConfirmHighRiskTools) {
      return Future.value(true);
    }
    return _confirmToolExecution(request, toolName, argSummary);
  }

  /// 弹出高风险工具执行确认框；返回 true 允许执行
  Future<bool> _confirmToolExecution(
    ToolCallRequest request,
    String toolName,
    String argSummary,
  ) async {    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFF9A825), size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('确认执行该操作？',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('工具：$toolName',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (argSummary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    argSummary,
                    style: const TextStyle(
                        fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text('该操作影响较大（删除/回滚/克隆等），请确认后再继续。',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认执行'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _reloadHistoryScope() async {
    widget.dispatcher.clearHistory();
    _parsedFiles.clear();
    setState(() {
      _messages.clear();
      _streamBuffer = StringBuffer();
      _reasoningBuffer = StringBuffer();
      _streamingMsgIndex = null;
    });
    _initSession();
    await _loadHistory();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final atBottom = _scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 50;
    if (_showScrollButton == atBottom) {
      setState(() => _showScrollButton = !atBottom);
    }
  }

  Future<void> _initTools() async {
    final storage = widget.storageService;
    if (storage == null) return;
    try {
      await _skillManager.init(await storage.root);
      // 同步外部 MCP 服务器远端工具到 ToolRegistry（对标 MonkeyCode mcphub）
      final mcpManager = McpServerManager(root: await storage.root);
      await mcpManager.load();
      final errors = await mcpManager.syncAllTools();
      if (errors.isNotEmpty) {
        debugPrint('MCP 工具同步失败: $errors');
      }
      _toolsInitialized = true;
    } catch (e) { debugPrint('AiChat: message send failed: $e'); }
  }

  /// 对话历史文件键：按站点分区，避免多站点串场。
  /// 无站点时回退到旧的全局文件名（兼容迁移）。
  String get _historyScopeKey {
    final custom = widget.historyKey?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return widget.sessionType.name;
  }

  String get _chatFileKey {
    final siteId = widget.settings.effectiveActiveSiteId;
    if (siteId.isNotEmpty) {
      return 'ai_chat_${siteId}_$_historyScopeKey.json';
    }
    return 'ai_chat_$_historyScopeKey.json';
  }

  /// 旧版全局历史文件键（用于数据迁移）
  String get _legacyChatFileKey => 'ai_chat_${widget.sessionType.name}.json';

  bool get _enableLegacyMigration {
    final custom = widget.historyKey?.trim();
    return custom == null || custom.isEmpty;
  }

  /// 加载已保存的对话历史（含工具调用上下文）
  Future<void> _loadHistory() async {
    final storage = widget.storageService;
    if (storage == null) {
      if (widget.initialMessage != null) {
        _addSystemMessage(widget.initialMessage!);
      }
      return;
    }
    try {
      final root = (await storage.root).path;
      var file = File('$root/$_chatFileKey');
      // 旧文件迁移：当前存在站点分区文件时优先；否则若存在旧全局文件则读取并迁移
      if (_enableLegacyMigration &&
          !await file.exists() &&
          _chatFileKey != _legacyChatFileKey) {
        final legacy = File('$root/$_legacyChatFileKey');
        if (await legacy.exists()) {
          file = legacy;
        }
      }
      if (!await file.exists()) {
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
      final data = jsonDecode(text);
      // 兼容新旧格式：新格式为 {"context": [...]}，旧格式为 [...]
      List contextList;
      if (data is Map && data['context'] is List) {
        contextList = data['context'] as List;
      } else if (data is List) {
        contextList = data;
      } else {
        if (widget.initialMessage != null) {
          _addSystemMessage(widget.initialMessage!);
        }
        return;
      }

      final context = contextList
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (context.isEmpty) {
        if (widget.initialMessage != null) {
          _addSystemMessage(widget.initialMessage!);
        }
        return;
      }

      // 恢复 dispatcher 完整上下文（含 tool_calls / tool 消息）
      widget.dispatcher.restoreHistory(context);

      // 从上下文中派生 UI 消息（过滤掉 tool 角色，只显示 user / assistant / system）
      final uiMessages = context
          .map((m) => ChatMessage.fromContextMap(m))
          .where((m) => m.showInUi)
          .toList();
      setState(() => _messages.addAll(uiMessages));

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
    } catch (e) { debugPrint('AiChat: stream error: $e');
      if (widget.initialMessage != null && _messages.isEmpty) {
        _addSystemMessage(widget.initialMessage!);
      }
    }
  }

  /// 保存完整对话上下文到本地文件（含工具调用上下文）。
  /// 落盘前对工具参数中的敏感凭据（token/key/secret）脱敏，避免明文泄漏。
  Future<void> _saveHistory() async {
    final storage = widget.storageService;
    if (storage == null) return;
    try {
      final root = (await storage.root).path;
      final file = File('$root/$_chatFileKey');
      final context = widget.dispatcher.chatHistory;
      final sanitized = context.map(_sanitizeHistoryMessage).toList();
      final json = jsonEncode({'context': sanitized});
      await file.writeAsString(json);
    } catch (e) { debugPrint('AiChat: stream close failed: $e'); }
  }

  /// 对单条历史消息中的敏感凭据字段做脱敏（保留结构供上下文恢复）。
  Map<String, dynamic> _sanitizeHistoryMessage(Map<String, dynamic> msg) {
    final out = Map<String, dynamic>.from(msg);
    final calls = out['tool_calls'];
    if (calls is List) {
      out['tool_calls'] = calls.map((c) {
        if (c is! Map) return c;
        final cm = Map<String, dynamic>.from(c);
        final fn = cm['function'];
        if (fn is Map) {
          final fm = Map<String, dynamic>.from(fn);
          final rawArgs = fm['arguments'];
          if (rawArgs is String && rawArgs.isNotEmpty) {
            try {
              final args = jsonDecode(rawArgs);
              if (args is Map) {
                final scrubbed = Map<String, dynamic>.from(args);
                for (final key in scrubbed.keys.toList()) {
                  if (_isSecretKey(key)) scrubbed[key] = '******';
                }
                fm['arguments'] = jsonEncode(scrubbed);
              }
            } catch (_) {}
          }
          cm['function'] = fm;
        }
        return cm;
      }).toList();
    }
    return out;
  }

  bool _isSecretKey(String key) {
    final k = key.toLowerCase();
    return k.contains('token') ||
        k.contains('api_key') ||
        k.contains('apikey') ||
        k.contains('secret') ||
        k.contains('password') ||
        k.contains('credential');
  }

  void _initSession() {
    // 构建已保存工具清单
    String? savedToolsList;
    if (_toolsInitialized) {
      final tools = _skillManager.allTools;
      if (tools.isNotEmpty) {
        savedToolsList = tools.map((t) => '${t.name}(${t.id})').join(', ');
      }
    }
    widget.dispatcher.setSystemPrompt(
      AiSessionManager.getSystemPrompt(
        widget.sessionType,
        blogFramework: widget.blogFramework,
        postsPath: widget.postsPath,
        pagesPath: widget.pagesPath,
        themesPath: widget.themesPath,
        defaultPostTemplateId: widget.defaultPostTemplateId,
        defaultPageTemplateId: widget.defaultPageTemplateId,
        fileNameRuleDesc: widget.fileNameRuleDesc,
        targetFramework: widget.targetFramework,
        savedToolsList: savedToolsList,
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

  /// 解析当前站点的脱敏凭据（供工具系统感知存在性，不含明文）
  SiteCredentials _resolveCredentials(String siteId) {
    final repo = widget.activeRepo;
    if (repo != null && repo.id == siteId) {
      return _toolManager.credentialsFromRepo(repo);
    }
    final site = widget.settings.blogSiteConfigs.where((s) => s.id == siteId).firstOrNull;
    if (site != null) {
      return _toolManager.credentialsFromBlogSite(site);
    }
    return const SiteCredentials(kind: 'unknown');
  }

  void _addSystemMessage(String text) {
    setState(() => _messages.add(ChatMessage(role: 'system', content: text)));
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
    // 注意：_saveHistory() 不在此时调用，因为 dispatcher._chatHistory 尚未包含用户消息
    // 完整的上下文保存由 _finishStreaming 在流处理完成后统一执行
    setState(() => _messages.add(ChatMessage(role: 'user', content: msg)));
    widget.onContentGenerated?.call(msg);

    // 先添加一个空 assistant 消息，后续流式填充
    _streamBuffer = StringBuffer();
    _reasoningBuffer = StringBuffer();
    setState(() {
      _messages.add(ChatMessage(role: 'assistant', content: ''));
      _streamingMsgIndex = _messages.length - 1;
      _busy = true;
      _isThinking = true;
      _status = '思考中...';
    });

    _scrollToBottom();

    // 注入仓库引用到工具系统
    BuiltinTools.gitHubService = widget.gitHubService;
    BuiltinTools.activeRepo = widget.activeRepo;
    // 注入当前站点脱敏凭据（真实令牌只在服务层注入，不进入 AI 上下文明文）
    final siteId = widget.activeRepo?.id ?? widget.settings.effectiveActiveSiteId;
    BuiltinTools.siteId = siteId;
    BuiltinTools.siteCredentials = _resolveCredentials(siteId);
    _mcpRuntime.siteId = siteId;
    _mcpRuntime.allowAutoSave = widget.settings.ai.aiAllowAutoSaveTools;
    // 注入应用设置引用（供 appDesign 工具读写）
    BuiltinTools.appSettings = widget.settings;
    BuiltinTools.onSettingsChanged = widget.onSettingsChanged;
    // 注入 SkillManager 引用（供 skill 管理工具使用）
    BuiltinTools.skillManager = _skillManager;
    // 注入本地存储与模板变更回调（供模板/框架会话读写本地模板）
    BuiltinTools.storageService = widget.storageService;
    BuiltinTools.onTemplatesChanged = widget.onTemplatesChanged;
    // 注入一键建站服务与站点持久化回调（供 create_site 工具使用）
    BuiltinTools.siteWizardService = SiteWizardService();
    BuiltinTools.onSiteCreated = widget.onSiteCreated;
    BuiltinTools.onSiteSaved = widget.onSiteSaved;

    try {
      final stream = widget.dispatcher.dispatchStream(
        settings: widget.settings,
        userMessage: msg,
        preferredModel: _selectedModel,
        autoOptimal: widget.settings.ai.aiAutoOptimalModel,
        enabledSkillIds: _selectedSkillIds,
      );

      _streamSub = stream.listen(
        (chunk) {
          if (!mounted) return;
          if (chunk.isDone) {
            _finishStreaming();
            return;
          }
          // 断线重连标记：清空当前消息累积内容，重连后从头重新流式输出
          if (chunk.resetStream) {
            final idx = _streamingMsgIndex;
            if (idx != null && idx < _messages.length) {
              setState(() {
                _streamBuffer.clear();
                _reasoningBuffer.clear();
                _status = '连接中断，正在重连...';
                _messages[idx] = ChatMessage(
                  role: 'assistant',
                  content: '',
                  time: _messages[idx].time,
                );
              });
              _scrollToBottom();
            }
            return;
          }
          final reasoning = chunk.reasoningContent;
          if (reasoning != null && reasoning.isNotEmpty) {
            // 兼容两种流：增量（追加）或全量（以已累积内容为前缀则替换）
            final existing = _reasoningBuffer.toString();
            if (existing.isNotEmpty && reasoning.startsWith(existing)) {
              _reasoningBuffer = StringBuffer(reasoning);
            } else {
              _reasoningBuffer.write(reasoning);
            }
            final idx = _streamingMsgIndex;
            if (idx != null && idx < _messages.length) {
              setState(() {
                _messages[idx] = ChatMessage(
                  role: 'assistant',
                  content: _messages[idx].content,
                  time: _messages[idx].time,
                  reasoningContent: _reasoningBuffer.toString(),
                );
              });
              _scrollToBottom();
            }
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
                  reasoningContent: _messages[idx].reasoningContent,
                );
              });
              _scrollToBottom();
            }
          }
          if (chunk.toolCalls != null && chunk.toolCalls!.isNotEmpty) {
            final idx = _streamingMsgIndex;
            for (final tc in chunk.toolCalls!) {
              final callId = tc['id']?.toString() ??
                  tc['call_id']?.toString() ??
                  tc['name']?.toString() ??
                  'tool';
              _toolCallStates[callId] = _ToolCallUiState.running;
              _expandedToolCalls.add(callId);
            }
            if (idx != null && idx < _messages.length) {
              setState(() {
                final existing = _messages[idx].toolCalls ?? [];
                final merged = [...existing, ...chunk.toolCalls!];
                _messages[idx] = ChatMessage(
                  role: 'assistant',
                  content: _messages[idx].content,
                  time: _messages[idx].time,
                  reasoningContent: _messages[idx].reasoningContent,
                  toolCalls: merged,
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
    // 通知建站长任务立即中止（构建轮询检查此标志），避免取消后后台静默建站
    BuiltinTools.siteWizardService?.isCancelled = () => true;
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
        widget.onFileOpsParsed?.call(files.map((f) => f.copy()).toList());
      }
      // 解析指令（【NEW_MCP】【NEW_SKILL】【联网搜索】等）
      _handleInstructions(content, idx);
      // 持久化
      _saveHistory();
      // 自检：仅当 AI 回复包含文件操作内容时才触发（避免对纯对话内容自检）
      if (widget.selfCheckEnabled && widget.selfChecker != null && (files.isNotEmpty || content.contains('【文件路径】'))) {
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
    if (mounted)
    setState(() {
      _busy = false;
      _isThinking = false;
      _status = null;
      _streamingMsgIndex = null;
    });
    _streamBuffer = StringBuffer();
    _reasoningBuffer = StringBuffer();
    // 工具卡片状态只保留到本轮流结束，避免跨轮残留"运行中"
    for (final entry in _toolCallStates.entries) {
      if (entry.value == _ToolCallUiState.running) {
        _toolCallStates[entry.key] = _ToolCallUiState.success;
      }
    }
    _scrollToBottom();
  }

  /// 处理 AI 输出中的指令标记
  Future<void> _handleInstructions(String content, int msgIndex) async {
    if (!InstructionParser.hasInstructions(content)) return;

    final instructions = InstructionParser.parseAll(content);
    if (instructions.isEmpty) return;

    for (final inst in instructions) {
      switch (inst.type) {
        case InstructionType.webSearch:
          final result = await _mcpRuntime.executeInstruction(inst);
          if (result.success && result.data != null) {
            _addSystemMessage('🔍 [联网搜索] ${inst.queryText}\n\n${result.data!['result']}');
          } else {
            _addSystemMessage('🔍 [联网搜索] 失败: ${result.error ?? "未知错误"}');
          }
          break;

        case InstructionType.webFetch:
          final result = await _mcpRuntime.executeInstruction(inst);
          if (result.success && result.data != null) {
            final fetchResult = result.data!['result']?.toString() ?? '';
            final truncated = fetchResult.length > 2000
                ? '${fetchResult.substring(0, 2000)}\n\n...(内容已截断)'
                : fetchResult;
            _addSystemMessage('🌐 [网页抓取] ${inst.queryText}\n\n$truncated');
          } else {
            _addSystemMessage('🌐 [网页抓取] 失败: ${result.error ?? "未知错误"}');
          }
          break;

        case InstructionType.newMcp:
          final result = await _mcpRuntime.executeInstruction(inst);
          if (result.success) {
            _addSystemMessage('✅ ${result.message}');
          } else {
            _addSystemMessage('❌ ${result.message}: ${result.error}');
          }
          break;

        case InstructionType.newSkill:
          final result = await _mcpRuntime.executeInstruction(inst);
          if (result.success) {
            _addSystemMessage('✅ ${result.message}');
          } else {
            _addSystemMessage('❌ ${result.message}: ${result.error}');
          }
          break;

        case InstructionType.newAgent:
          final result = await _mcpRuntime.executeInstruction(inst);
          if (result.success) {
            _addSystemMessage('✅ ${result.message}');
          } else {
            _addSystemMessage('❌ ${result.message}: ${result.error}');
          }
          break;

        case InstructionType.mcpCall:
          final result = await _mcpRuntime.executeInstruction(inst);
          if (result.success) {
            _addSystemMessage('🔧 [MCP] ${result.message}');
          } else {
            _addSystemMessage('❌ [MCP] ${result.message}');
          }
          break;

        case InstructionType.skillRun:
          final result = await _mcpRuntime.executeInstruction(inst);
          if (result.success) {
            _addSystemMessage('🚀 [Skill] ${result.message}');
          } else {
            _addSystemMessage('❌ [Skill] ${result.message}');
          }
          break;

        default:
          break;
      }
    }
  }

  void _scrollToBottom() {
    // 双重 postFrame 回调：确保新消息及其按钮（复制/写入）完成布局后再滚动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
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

  /// 新建会话：清空当前对话，保留欢迎语和系统提示
  Future<void> newSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建会话'),
        content: const Text('将清空当前对话历史，开始全新会话。\n\n系统提示词和工具配置不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认新建'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    clearHistory();
    if (widget.initialMessage != null) {
      _addSystemMessage(widget.initialMessage!);
    }
  }

  Future<void> _deleteHistoryFile() async {
    final storage = widget.storageService;
    if (storage == null) return;
    try {
      final file = File('${(await storage.root).path}/$_chatFileKey');
      if (await file.exists()) await file.delete();
    } catch (e) { debugPrint('AiChat: model load failed: $e'); }
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
    widget.onFilesWritten?.call(files.map((f) => f.copy()).toList());
  }

  @override
  void dispose() {
    widget.dispatcher.onModelSwitched = null;
    widget.dispatcher.onToolsExecuted = null;
    widget.dispatcher.onToolConfirm = null;
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
        // ── 会话标题栏：显示类型 + 新建/清空按钮 ──
        _buildSessionHeader(cs),
        // 消息列表（含一键到底按钮）
        Expanded(
          child: Stack(
            children: [
              _messages.isEmpty
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
              // 👇 一键到底箭头按钮
              if (_showScrollButton)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'scroll_to_bottom_${widget.sessionType.name}',
                    onPressed: _scrollToBottom,
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.arrow_downward, color: cs.onPrimaryContainer),
                  ),
                ),
            ],
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
                  ai: widget.settings.ai.copyWith(
                    defaultModelId: m.modelId,
                    defaultModelBase: m.apiBase,
                  ),
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
        return 'AI 博文创作助手（支持仓库分析）';
      case AiSessionType.page:
        return 'AI 页面创作助手（支持仓库分析）';
      case AiSessionType.theme:
        return 'AI 主题开发助手';
      case AiSessionType.themeMigration:
        return 'AI 主题迁移助手';
      case AiSessionType.audit:
        return 'AI 站点巡检助手';
      case AiSessionType.appDesign:
        return 'AI 应用 UI 设计助手';
      case AiSessionType.template:
        return 'AI 模板与博客框架助手';
    }
  }

  String get _sessionTitle {
    switch (widget.sessionType) {
      case AiSessionType.article:
        return '博文编辑';
      case AiSessionType.page:
        return '页面编辑';
      case AiSessionType.theme:
        return '主题开发';
      case AiSessionType.themeMigration:
        return '主题迁移';
      case AiSessionType.audit:
        return '站点巡检';
      case AiSessionType.appDesign:
        return '应用 UI 设计';
      case AiSessionType.template:
        return '模板与框架';
    }
  }

  Widget _buildSessionHeader(ColorScheme cs) {
    final activeModel = _activeModel ?? _selectedModel;
    final modelLabel = activeModel != null
        ? activeModel.modelId
        : (widget.settings.effectiveAiModel.isNotEmpty
            ? widget.settings.effectiveAiModel
            : '未选择模型');
    final autoOptimal = widget.settings.ai.aiAutoOptimalModel;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.5),
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
          ),
          child: Row(
            children: [
              Icon(Icons.chat_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                _sessionTitle,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
              if (_messages.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  '(${_messages.length} 条消息)',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ],
              const Spacer(),
              // 当前模型 + 自动择优标记
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: autoOptimal
                      ? cs.primaryContainer.withOpacity(0.6)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.memory, size: 13, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(
                      modelLabel,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface),
                    ),
                    if (autoOptimal) ...[
                      const SizedBox(width: 4),
                      Text(
                        '自动择优',
                        style: TextStyle(fontSize: 10, color: cs.primary),
                      ),
                    ],
                  ],
                ),
              ),
              if (_messages.isNotEmpty) ...[
                const SizedBox(width: 4),
                _SessionHeaderButton(
                  icon: Icons.add_comment_outlined,
                  label: '新建',
                  tooltip: '新建会话（清空当前对话）',
                  onTap: _busy ? null : newSession,
                ),
              ],
            ],
          ),
        ),
        // 模型切换提示条
        if (_lastSwitchEvent != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            color: cs.tertiaryContainer.withOpacity(0.7),
            child: Row(
              children: [
                Icon(Icons.swap_horiz, size: 14, color: cs.onTertiaryContainer),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '「${_lastSwitchEvent!.fromModel}」${_lastSwitchEvent!.reason}，已自动切换至「${_lastSwitchEvent!.toModel}」',
                    style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _lastSwitchEvent = null),
                  child: Icon(Icons.close, size: 14, color: cs.onTertiaryContainer),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInput(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSkillSelector(cs),
          const SizedBox(height: 6),
          Row(
            children: [
              if (widget.onAttach != null)
                IconButton(
                  onPressed: widget.onAttach,
                  icon: const Icon(Icons.attach_file),
                  tooltip: '添加附件',
                ),
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
        ],
      ),
    );
  }

  /// 技能选择器：发送消息前选择启用哪些自定义技能（对标 MonkeyCode skill picker）
  Widget _buildSkillSelector(ColorScheme cs) {
    final skills = _skillManager.skills;
    if (skills.isEmpty) return const SizedBox.shrink();

    final selected = _selectedSkillIds;
    final selectedCount = selected?.length ?? skills.length;
    final allSelected = selected == null || selected.isEmpty;
    final label =
        allSelected ? '技能：全部' : '技能：$selectedCount/${skills.length}';
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: Icon(Icons.extension_outlined,
              size: 16, color: allSelected ? cs.primary : cs.tertiary),
          label: Text(
            label,
            style: TextStyle(
                fontSize: 12,
                color: allSelected ? cs.primary : cs.tertiary),
          ),
          side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
          backgroundColor: cs.surfaceContainerHighest.withOpacity(0.4),
          onPressed: _busy ? null : () => _openSkillPicker(cs),
        ),
      ),
    );
  }

  /// 弹出技能多选面板
  Future<void> _openSkillPicker(ColorScheme cs) async {
    final skills = _skillManager.skills;
    if (skills.isEmpty || !mounted) return;

    final current = _selectedSkillIds ?? skills.map((s) => s.id).toSet();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          var pending = Set<String>.from(current);
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.extension_outlined, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('选择本轮对话启用的技能',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.of(ctx).pop(pending),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => setSheetState(() {
                              pending = skills.map((s) => s.id).toSet();
                            }),
                            icon: const Icon(Icons.select_all, size: 16),
                            label: const Text('全部'),
                          ),
                          TextButton.icon(
                            onPressed: () => setSheetState(() {
                              pending = <String>{};
                            }),
                            icon: const Icon(Icons.deselect, size: 16),
                            label: const Text('不选'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: skills.length,
                    itemBuilder: (_, i) {
                      final s = skills[i];
                      final isSel = pending.contains(s.id);
                      return CheckboxListTile(
                        value: isSel,
                        title: Text(s.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          s.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: cs.outline),
                        ),
                        secondary: Icon(Icons.extension_outlined,
                            size: 18,
                            color: isSel ? cs.primary : cs.outlineVariant),
                        onChanged: (v) => setSheetState(() {
                          if (v == true) {
                            pending.add(s.id);
                          } else {
                            pending.remove(s.id);
                          }
                        }),
                      );
                    },
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(pending),
                    child: Text('应用（${pending.length} 个技能）'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _selectedSkillIds = result.isEmpty ? null : result;
    });
  }

  /// 思考动画：跳动的三个点
  Widget _buildThinkingAnimation(ColorScheme cs) {
    return _ThinkingDots(color: cs.primary);
  }

  /// 推理过程渲染：可折叠的思考区块（与正文视觉区分）
  /// 思考过程渲染：可折叠的思考区块。
  /// [autoCollapse] 为 true（历史消息）时默认折叠为单行，[isLatest] 最新消息默认展开。
  /// 对标 MonkeyCode ThoughtMessageItem（collapsed = !isLatest）。
  Widget _buildReasoningBlock(
    String reasoning,
    ColorScheme cs, {
    bool isLatest = false,
    bool isStreaming = false,
  }) {
    // 流式过程中始终展开（可见实时推理）；否则最新消息默认展开、历史默认折叠
    final autoCollapsed = !isStreaming && !isLatest;
    final collapsed = _collapsedReasoning[reasoning] ?? autoCollapsed;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, size: 14, color: cs.outline),
              const SizedBox(width: 6),
              Text('思考过程',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.outline)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() {
                  _collapsedReasoning[reasoning] = !collapsed;
                }),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      collapsed ? '展开' : '折叠',
                      style: TextStyle(fontSize: 11, color: cs.primary),
                    ),
                    Icon(
                      collapsed ? Icons.expand_more : Icons.expand_less,
                      size: 16,
                      color: cs.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reasoning,
            maxLines: collapsed ? 1 : null,
            overflow: collapsed ? TextOverflow.ellipsis : null,
            style: TextStyle(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: cs.outline,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
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

    // 消息时间戳：悬停气泡显示 MM-DD HH:mm:ss
    String ts() {
      final t = msg.time;
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    }

    return Tooltip(
      message: ts(),
      waitDuration: const Duration(milliseconds: 400),
      child: Align(
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
            else ...[
              // 👇 思考过程（推理内容独立渲染，与正文区分）
              if (isAssistant &&
                  msg.reasoningContent != null &&
                  msg.reasoningContent!.isNotEmpty) ...[
                _buildReasoningBlock(
                  msg.reasoningContent!,
                  cs,
                  isLatest: msgIndex == _messages.length - 1,
                  isStreaming: isStreaming,
                ),
                const SizedBox(height: 8),
              ],
              _buildMessageContent(msg, cs, isUser, isAssistant, isStreaming),
            ],
            // 👇 工具调用卡片（结构化展示 assistant 的工具调用）
            if (isAssistant && msg.toolCalls != null && msg.toolCalls!.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...msg.toolCalls!.map((tc) => _buildToolCallCard(tc, cs)),
            ],
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
      ),
    );
  }

  /// 工具调用卡片：状态 + 名称 + 参数摘要 + 执行结果（对标 MonkeyCode toolcalls 组件）
  Widget _buildToolCallCard(Map<String, dynamic> tc, ColorScheme cs) {
    final function = tc['function'] as Map<String, dynamic>? ?? {};
    final name = function['name']?.toString() ?? tc['name']?.toString() ?? 'unknown';
    final callId = tc['id']?.toString() ?? tc['call_id']?.toString() ?? name;
    final isExpanded = _expandedToolCalls.contains(callId);
    final state = _toolCallStates[callId] ?? _ToolCallUiState.running;
    final result = _toolCallResults[callId];

    String argSummary = '';
    final rawArgs = function['arguments'] ?? tc['arguments'] ?? tc['input'];
    if (rawArgs is String && rawArgs.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawArgs);
        if (decoded is Map) {
          argSummary = decoded.entries
              .map((e) => '${e.key}: ${_argValue(e.value)}')
              .join('\n');
        } else {
          argSummary = rawArgs;
        }
      } catch (_) {
        argSummary = rawArgs;
      }
    } else if (rawArgs is Map) {
      argSummary = rawArgs
          .entries
          .map((e) => '${e.key}: ${_argValue(e.value)}')
          .join('\n');
    }

    final icon = _toolIcon(name);
    final title = _toolDisplayTitle(name, argSummary);
    final borderColor = switch (state) {
      _ToolCallUiState.running => cs.primary,
      _ToolCallUiState.success => const Color(0xFF4CAF50),
      _ToolCallUiState.failure => const Color(0xFFE53935),
    };
    final statusIcon = switch (state) {
      _ToolCallUiState.running => const SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      _ToolCallUiState.success => const Icon(Icons.check_circle,
          size: 15, color: Color(0xFF4CAF50)),
      _ToolCallUiState.failure => const Icon(Icons.error,
          size: 15, color: Color(0xFFE53935)),
    };
    final statusLabel = switch (state) {
      _ToolCallUiState.running => '运行中',
      _ToolCallUiState.success => '成功',
      _ToolCallUiState.failure => '失败',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor.withOpacity(0.45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() {
          if (isExpanded) {
            _expandedToolCalls.remove(callId);
          } else {
            _expandedToolCalls.add(callId);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: borderColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  statusIcon,
                  const SizedBox(width: 4),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: borderColor,
                    ),
                  ),
                  if (result != null && result.durationMs > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${_fmtMs(result.durationMs)}',
                      style: TextStyle(fontSize: 10, color: cs.outline),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: cs.outline,
                  ),
                ],
              ),
              if (isExpanded && argSummary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    argSummary,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (isExpanded && result != null) ...[
                const SizedBox(height: 6),
                _buildToolResultDetail(name, result, state, cs),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 工具结果专属渲染（对标 MonkeyCode 各工具 renderDetail）：
  /// web_search 结果列表 / file_read 文件内容 / git_clone 仓库信息 / 其余纯文本
  Widget _buildToolResultDetail(
    String name,
    ToolCallResult result,
    _ToolCallUiState state,
    ColorScheme cs,
  ) {
    final isFailure = state == _ToolCallUiState.failure;
    final content = isFailure && result.error != null
        ? '❌ ${result.error}'
        : result.content;

    if (name.contains('search') && !isFailure) {
      final entries = _parseSearchResults(content);
      if (entries.isNotEmpty) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in entries)
                InkWell(
                  onTap: e.url.isNotEmpty
                      ? () => _openUrl(e.url)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: cs.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (e.url.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            e.url,
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: cs.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      }
    }

    if (name.contains('read') || name.contains('view')) {
      return _resultBlock(content, cs, isFailure,
          maxLines: null, fontSize: 11.5);
    }

    if (name.contains('git_clone') && !isFailure) {
      final info = _parseGitCloneSummary(content);
      if (info != null) {
        return _resultBlock(info, cs, false, maxLines: null, fontSize: 11);
      }
    }

    return _resultBlock(content, cs, isFailure,
        maxLines: 6, fontSize: 11);
  }

  Widget _resultBlock(
    String text,
    ColorScheme cs,
    bool isFailure, {
    int? maxLines,
    double fontSize = 11,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isFailure ? const Color(0x1AE53935) : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: 'monospace',
          height: 1.4,
          color: isFailure ? const Color(0xFFE53935) : cs.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 解析 web_search 输出「1. 标题\n   URL\n」为条目列表
  List<_SearchEntry> _parseSearchResults(String content) {
    final entries = <_SearchEntry>[];
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      final numbered = RegExp(r'^\d+\.\s+(.+)$').firstMatch(line);
      if (numbered == null) continue;
      final title = numbered.group(1)!.trim();
      var url = '';
      if (i + 1 < lines.length) {
        final next = lines[i + 1].trim();
        if (next.startsWith('http://') || next.startsWith('https://')) {
          url = next;
        }
      }
      if (title.isEmpty) continue;
      entries.add(_SearchEntry(title, url));
      i++; // 跳过已消费的 URL 行
    }
    return entries;
  }

  /// 从 git_clone 输出中提取仓库摘要（首行 + 文件计数）
  String? _parseGitCloneSummary(String content) {
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty);
    if (lines.isEmpty) return null;
    final first = lines.first.trim();
    final fileCount = RegExp(r'(\d+)\s*个?(文件|文件?)\b').firstMatch(content);
    final buf = StringBuffer()..writeln(first);
    if (fileCount != null) buf.writeln(fileCount.group(0));
    return buf.toString().trim();
  }

  void _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 毫秒 → 可读耗时
  String _fmtMs(int ms) {
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  /// 参数值摘要（长文本截断，避免撑爆卡片）
  String _argValue(dynamic v) {
    if (v == null) return 'null';
    final s = v.toString();
    if (s.length > 80) return '${s.substring(0, 77)}...';
    return s;
  }

  /// 按工具名返回图标
  IconData _toolIcon(String name) {    if (name.contains('search') || name.contains('search_web')) return Icons.search;
    if (name.contains('web') || name.contains('fetch') || name.contains('http')) return Icons.public;
    if (name.contains('read')) return Icons.menu_book;
    if (name.contains('write') || name.contains('edit') || name.contains('diff')) return Icons.edit_note;
    if (name.contains('mcp') || name.contains('remote')) return Icons.dns;
    if (name.contains('skill') || name.contains('load_skill')) return Icons.extension;
    if (name.contains('bash') || name.contains('shell') || name.contains('terminal')) return Icons.terminal;
    if (name.contains('site') || name.contains('health')) return Icons.monitor_heart;
    return Icons.code;
  }

  /// 生成工具卡片的自然语言标题（对标 MonkeyCode 各工具专属 renderTitle）
  String _toolDisplayTitle(String name, String argSummary) {
    final args = _parseArgMap(argSummary);
    String? path = _firstNonNull(args, ['path', 'file_path', 'filePath', 'cwd']);
    final pattern = _firstNonNull(args, ['pattern', 'query']);
    final command = _firstNonNull(args, ['command', 'cmd', 'message', 'prompt']);
    final url = _firstNonNull(args, ['url', 'repo']);

    if (name.contains('search')) {
      return pattern != null ? '搜索「$pattern」' : '搜索文件';
    }
    if (name.contains('git_clone')) {
      return url != null ? '克隆仓库 $url' : '克隆仓库';
    }
    if (name.contains('read') || name.contains('view')) {
      return path != null ? '读取文件 $path' : '读取内容';
    }
    if (name.contains('write') || name.contains('edit') || name.contains('diff')) {
      return path != null ? '修改文件 $path' : '编辑文件';
    }
    if (name.contains('bash') || name.contains('shell') || name.contains('terminal')) {
      return command != null ? '执行命令' : '执行命令';
    }
    if (name.contains('http') || name.contains('fetch') || name.contains('web')) {
      return url != null ? '访问 $url' : '访问网络';
    }
    if (name.contains('mcp') || name.contains('remote')) {
      return '调用远端服务';
    }
    if (name.contains('skill') || name.contains('load_skill')) {
      return '加载技能';
    }
    return name;
  }

  Map<String, dynamic> _parseArgMap(String argSummary) {
    final out = <String, dynamic>{};
    for (final line in argSummary.split('\n')) {
      final idx = line.indexOf(': ');
      if (idx <= 0) continue;
      out[line.substring(0, idx)] = line.substring(idx + 2);
    }
    return out;
  }

  String? _firstNonNull(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return null;
  }
}

/// 工具调用执行状态
enum _ToolCallUiState { running, success, failure }

/// web_search 结果条目
class _SearchEntry {
  final String title;
  final String url;
  const _SearchEntry(this.title, this.url);
}

class ChatMessage {
  final String role;
  final String content;
  final DateTime time;
  final List<Map<String, dynamic>>? toolCalls;   // assistant 消息携带的工具调用
  final String? toolCallId;                      // tool 消息携带的调用 ID
  final String? reasoningContent;                // assistant 消息的推理过程

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? time,
    this.toolCalls,
    this.toolCallId,
    this.reasoningContent,
  }) : time = time ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'time': time.toIso8601String(),
        if (toolCalls != null) 'toolCalls': toolCalls,
        if (toolCallId != null) 'toolCallId': toolCallId,
        if (reasoningContent != null) 'reasoningContent': reasoningContent,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j['role']?.toString() ?? 'system',
        content: j['content']?.toString() ?? '',
        time: DateTime.tryParse(j['time']?.toString() ?? '') ?? DateTime.now(),
        toolCalls: (j['toolCalls'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        toolCallId: j['toolCallId']?.toString(),
        reasoningContent: j['reasoningContent']?.toString(),
      );

  /// 是否能在 UI 中显示（system / user / assistant 可显示，tool 不可显示）
  bool get showInUi => role == 'system' || role == 'user' || role == 'assistant';

  /// 从 dispatcher 的 Map 格式创建
  factory ChatMessage.fromContextMap(Map<String, dynamic> m) => ChatMessage(
        role: m['role']?.toString() ?? 'system',
        content: m['content']?.toString() ?? '',
        toolCalls: (m['tool_calls'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        toolCallId: m['tool_call_id']?.toString(),
        reasoningContent: m['reasoning_content']?.toString() ??
            m['reasoningContent']?.toString(),
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

/// 会话标题栏按钮
class _SessionHeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  const _SessionHeaderButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: enabled ? cs.primary : cs.outline),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? cs.primary : cs.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
