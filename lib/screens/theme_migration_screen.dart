import 'dart:io';

import 'package:flutter/material.dart';

import '../core/ai/ai_model_entity.dart';
import '../core/ai/ai_model_manager.dart';
import '../core/ai/ai_request_dispatcher.dart';
import '../core/ai/ai_self_checker.dart';
import '../core/ai/ai_session_manager.dart';
import '../core/ai/theme_migration_service.dart';
import '../models/app_settings.dart';
import '../models/blog_framework.dart';
import '../models/repo_config.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../widgets/ai_model_picker.dart';
import 'ai_model_manager_screen.dart';

/// AI 主题跨框架迁移页面
class ThemeMigrationScreen extends StatefulWidget {
  final AppSettings settings;
  final RepoConfig? activeRepo;
  final List<RepoConfig> repos;
  final AiService aiService;
  final GitHubService githubService;
  final AiModelManager modelManager;
  final AiRequestDispatcher dispatcher;
  final ThemeMigrationService migrationService;
  final AiSelfChecker selfChecker;
  final Future<void> Function(AppSettings) onSettingsChanged;

  const ThemeMigrationScreen({
    super.key,
    required this.settings,
    this.activeRepo,
    required this.repos,
    required this.aiService,
    required this.githubService,
    required this.modelManager,
    required this.dispatcher,
    required this.migrationService,
    required this.selfChecker,
    required this.onSettingsChanged,
  });

  @override
  State<ThemeMigrationScreen> createState() => _ThemeMigrationScreenState();
}

class _ThemeMigrationScreenState extends State<ThemeMigrationScreen> {
  final _urlCtrl = TextEditingController();
  final _themeNameCtrl = TextEditingController();
  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<AiModelEntity> _models = [];
  AiModelEntity? _selectedModel;
  List<ChatMessage> _messages = [];
  bool _busy = false;
  String? _status;
  String? _tempDir;
  ThemeAnalysis? _analysis;
  ThemeMigrationResult? _migrationResult;
  bool _selfCheckEnabled = true;
  int _currentStep = 0; // 0=输入, 1=分析, 2=迁移中, 3=交互式微调

  @override
  void initState() {
    super.initState();
    _loadModels();
    // 初始化会话
    final repo = widget.activeRepo ?? (widget.repos.isNotEmpty ? widget.repos.first : null);
    final fw = repo != null ? BlogFramework.byId(repo.frameworkId) : null;
    widget.dispatcher.setSystemPrompt(
      AiSessionManager.getSystemPrompt(
        AiSessionType.themeMigration,
        targetFramework: fw?.name ?? 'Hexo',
        themesPath: 'themes',
      ),
    );
    _addSystemMessage('欢迎使用 AI 主题跨框架迁移助手！\n\n请输入外部主题的 Git 地址或 ZIP 下载链接，我将帮你转换适配当前博客框架。\n\n⚠️ 请遵守主题开源协议，仅迁移拥有合法开源许可的源码。');
  }

  void _addSystemMessage(String text) {
    _messages.add(ChatMessage(role: 'system', content: text));
  }

  void _addUserMessage(String text) {
    _messages.add(ChatMessage(role: 'user', content: text));
    widget.dispatcher.addUserMessage(text);
  }

  void _addAssistantMessage(String text) {
    _messages.add(ChatMessage(role: 'assistant', content: text));
    widget.dispatcher.addAssistantMessage(text);
  }

  Future<void> _loadModels() async {
    _models = await widget.modelManager.getEnabled();
    if (_models.isNotEmpty) {
      _selectedModel = _models.first;
    }
    if (mounted) setState(() {});
  }

  Future<void> _startMigration() async {
    final url = _urlCtrl.text.trim();
    final themeName = _themeNameCtrl.text.trim();

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入主题源码地址')),
      );
      return;
    }
    if (themeName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入目标主题名称')),
      );
      return;
    }

    final repo = widget.activeRepo ?? (widget.repos.isNotEmpty ? widget.repos.first : null);
    if (repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置目标仓库')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在克隆主题源码...';
      _currentStep = 1;
    });

    _addUserMessage('拉取这个地址的主题 $url\n将它改造适配我当前仓库：${BlogFramework.byId(repo.frameworkId)?.name ?? repo.frameworkId}\n主题文件夹命名 $themeName');

    try {
      // Step 1: Clone/download source
      final tempDir = '${Directory.systemTemp.path}/hexo_theme_migrate_${DateTime.now().millisecondsSinceEpoch}';
      _tempDir = tempDir;

      if (url.startsWith('http')) {
        await widget.migrationService.cloneThemeRepo(url, tempDir);
      }

      setState(() => _status = '正在分析主题结构...');

      // Step 2: Analyze source
      final dirStructure = await widget.migrationService.readDirectoryStructure(tempDir);
      final sourceFiles = await widget.migrationService.readAllTextFiles(tempDir);

      final sourceCode = StringBuffer();
      sourceCode.writeln('=== 目录结构 ===');
      sourceCode.writeln(dirStructure);
      sourceCode.writeln('\n=== 文件内容 ===');
      for (final entry in sourceFiles.entries.take(20)) {
        // 限制大小，避免 token 超限
        final content = entry.value.length > 3000
            ? '${entry.value.substring(0, 3000)}\n... (截断)'
            : entry.value;
        sourceCode.writeln('\n--- ${entry.key} ---');
        sourceCode.writeln(content);
      }

      _analysis = await widget.migrationService.analyzeSource(
        settings: widget.settings,
        sourceCode: sourceCode.toString(),
      );

      setState(() {
        _status = '分析完成：源框架 ${_analysis!.sourceFrameworkName}';
        _currentStep = 2;
      });

      _addAssistantMessage(
        '✅ 主题源码分析完成\n'
        '• 源框架：${_analysis!.sourceFrameworkName}\n'
        '• 模板语法：${_analysis!.templateSyntax}\n'
        '• 配置格式：${_analysis!.configFormat}\n'
        '• 关键文件：${_analysis!.keyFiles.take(10).join(', ')}\n\n'
        '正在开始跨框架迁移转换...',
      );

      // Step 3: Migrate
      setState(() => _status = '正在 AI 跨框架迁移转换...');

      final allSourceCode = StringBuffer();
      for (final entry in sourceFiles.entries) {
        final content = entry.value.length > 5000
            ? '${entry.value.substring(0, 5000)}\n... (截断)'
            : entry.value;
        allSourceCode.writeln('\n=== ${entry.key} ===');
        allSourceCode.writeln(content);
      }

      _migrationResult = await widget.migrationService.migrate(
        settings: widget.settings,
        sourceFramework: _analysis!.sourceFramework,
        targetFramework: repo.frameworkId,
        sourceCode: allSourceCode.toString(),
        themeName: themeName,
      );

      setState(() {
        _status = '迁移完成！共 ${_migrationResult!.files.length} 个文件';
        _currentStep = 3;
      });

      _addAssistantMessage(
        '✅ 主题迁移完成！\n\n'
        '生成文件 ${_migrationResult!.files.length} 个：\n'
        '${_migrationResult!.files.map((f) => '• ${f.path}').join('\n')}\n\n'
        '现在可以继续交互式微调，例如：\n'
        '• 调整导航栏样式\n'
        '• 增加暗色模式\n'
        '• 移除不需要的模块\n'
        '• 修改配色方案\n\n'
        '输入「确认写入」将文件写入仓库 themes/$themeName/',
      );

      // Step 4: Self-check
      if (_selfCheckEnabled) {
        setState(() => _status = '正在自动检测代码...');
        final checkResult = await widget.selfChecker.check(
          settings: widget.settings,
          generatedContent: _migrationResult!.rawOutput,
          sessionType: AiSessionType.themeMigration,
          blogFramework: repo.frameworkId,
        );
        if (checkResult.hasError) {
          _addAssistantMessage('⚠️ 自检发现问题：\n${checkResult.issues.join('\n')}');
        } else {
          _addAssistantMessage('✅ ${checkResult.message}');
        }
      }
    } catch (e) {
      _addAssistantMessage('❌ 迁移过程出错: $e');
      setState(() => _status = '迁移失败: $e');
    } finally {
      _cleanupTemp();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    _chatCtrl.clear();

    _addUserMessage(text);

    setState(() {
      _busy = true;
      _status = 'AI 处理中...';
    });

    try {
      final result = await widget.dispatcher.dispatch(
        settings: widget.settings,
        userMessage: text,
        preferredModel: _selectedModel,
        maxRetries: 3,
        enableAutoSwitch: true,
      );

      _addAssistantMessage(result.content);

      if (result.switched) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已自动切换到备选模型: ${result.usedModel}')),
          );
        }
      }

      // Self-check
      if (_selfCheckEnabled) {
        final checkResult = await widget.selfChecker.check(
          settings: widget.settings,
          generatedContent: result.content,
          sessionType: AiSessionType.themeMigration,
          blogFramework: widget.activeRepo?.frameworkId,
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
    }
  }

  Future<void> _writeFiles() async {
    if (_migrationResult == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认写入主题文件'),
        content: Text(
          '即将写入 ${_migrationResult!.files.length} 个文件到 themes/${_migrationResult!.themeName}/，\n\n'
          '⚠️ 请确保已推送仓库最新代码，建议先创建 Git 快照备份。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认写入')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      _busy = true;
      _status = '正在写入文件...';
    });

    try {
      final repo = widget.activeRepo ?? widget.repos.first;
      for (final file in _migrationResult!.files) {
        await widget.githubService.putRawFile(
          repo,
          file.path,
          file.content,
          commitMessage: 'theme: migrate ${_migrationResult!.themeName} - ${file.path}',
        );
      }

      _addAssistantMessage(
        '✅ 已写入 ${_migrationResult!.files.length} 个文件到 themes/${_migrationResult!.themeName}/\n\n'
        '请推送仓库并在远端构建测试。如有异常，可使用「回滚主题快照」指令恢复。',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已写入 ${_migrationResult!.files.length} 个文件到主题目录')),
        );
      }
    } catch (e) {
      _addAssistantMessage('❌ 写入失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cleanupTemp() {
    if (_tempDir != null) {
      try {
        final dir = Directory(_tempDir!);
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      } catch (_) {}
      _tempDir = null;
    }
  }

  @override
  void dispose() {
    _cleanupTemp();
    _urlCtrl.dispose();
    _themeNameCtrl.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final repo = widget.activeRepo ?? (widget.repos.isNotEmpty ? widget.repos.first : null);
    final fw = repo != null ? BlogFramework.byId(repo.frameworkId) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 主题迁移'),
        actions: [
          IconButton(
            icon: Icon(
              _selfCheckEnabled ? Icons.verified : Icons.verified_outlined,
              color: _selfCheckEnabled ? cs.primary : cs.outline,
            ),
            tooltip: '自动自检: ${_selfCheckEnabled ? "开" : "关"}',
            onPressed: () => setState(() => _selfCheckEnabled = !_selfCheckEnabled),
          ),
          if (_currentStep >= 3 && _migrationResult != null)
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: '写入主题文件',
              onPressed: _busy ? null : _writeFiles,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_busy)
            LinearProgressIndicator(minHeight: 2, color: cs.primary),
          // Step 0: 输入区
          if (_currentStep == 0)
            _buildInputSection(cs, fw),
          // Step 1-3: 对话区
          if (_currentStep > 0)
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (ctx, i) => _buildMessageBubble(_messages[i], cs),
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
                    child: Text(
                      _status!,
                      style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          // 底部输入栏
          if (_currentStep > 0)
            _buildChatInput(cs),
          // 模型选择栏
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
      ),
    );
  }

  Widget _buildInputSection(ColorScheme cs, BlogFramework? fw) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 版权提示
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '请遵守主题开源协议，仅迁移拥有合法开源许可的源码，严禁商用侵权。',
                      style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 目标框架信息
            if (fw != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      '目标框架: ${fw.name} | 主题目录: themes/',
                      style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: '主题源码地址',
                hintText: 'https://github.com/xxx/demo-hugo-theme 或 ZIP 链接',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _themeNameCtrl,
              decoration: const InputDecoration(
                labelText: '目标主题名称',
                hintText: 'demo-hexo',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _startMigration,
              icon: _busy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.rocket_launch),
              label: Text(_busy ? '迁移中...' : '开始迁移'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 16),
            // 快捷指令
            Text('快捷指令示例', style: TextStyle(fontSize: 12, color: cs.outline)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _quickChip('只转换布局模板，不改CSS'),
                _quickChip('转换后移除评论模块'),
                _quickChip('分析这个主题的语法差异'),
                _quickChip('回滚主题快照'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 11)),
      onPressed: () {
        _chatCtrl.text = text;
      },
    );
  }

  Widget _buildChatInput(ColorScheme cs) {
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
                hintText: '输入微调指令...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              minLines: 1,
              maxLines: 3,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _busy ? null : _sendMessage,
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

  Widget _buildMessageBubble(ChatMessage msg, ColorScheme cs) {
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
              Text(
                msg.content,
                style: TextStyle(fontSize: 13, color: cs.outline),
              )
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
  final String role; // 'system', 'user', 'assistant'
  final String content;
  final DateTime time;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}

