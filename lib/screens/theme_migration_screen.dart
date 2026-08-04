import 'dart:io';

import 'package:flutter/material.dart';

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
import '../services/storage_service.dart';
import '../services/version_snapshot_service.dart';
import '../widgets/ai_chat_panel.dart';

/// AI 主题跨框架迁移页面 — 始终对话模式
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
  final StorageService? storageService;
  final VersionSnapshotService? snapshotService;

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
    this.storageService,
    this.snapshotService,
  });

  @override
  State<ThemeMigrationScreen> createState() => _ThemeMigrationScreenState();
}

class _ThemeMigrationScreenState extends State<ThemeMigrationScreen> {
  final _urlCtrl = TextEditingController();
  final _themeNameCtrl = TextEditingController();
  final GlobalKey<AiChatPanelState> _chatKey = GlobalKey();

  bool _busy = false;
  String? _status;
  String? _tempDir;
  ThemeAnalysis? _analysis;
  ThemeMigrationResult? _migrationResult;
  bool _selfCheckEnabled = true;
  bool _showInputForm = true;

  // 文件差异预览
  Set<String> _selectedFilePaths = {};
  int? _previewFileIndex;

  @override
  void dispose() {
    _cleanupTemp();
    _urlCtrl.dispose();
    _themeNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _startMigration() async {
    final url = _urlCtrl.text.trim();
    final themeName = _themeNameCtrl.text.trim();

    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入主题源码地址')),
        );
      }
      return;
    }
    if (themeName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入目标主题名称')),
        );
      }
      return;
    }

    final repo = widget.activeRepo ?? (widget.repos.isNotEmpty ? widget.repos.first : null);
    if (repo == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先配置目标仓库')),
        );
      }
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在克隆主题源码...';
      _showInputForm = false;
    });

    final fwName = BlogFramework.byId(repo.frameworkId)?.name ?? repo.frameworkId;
    _chatKey.currentState?.addMessage('user', '拉取这个地址的主题 $url\n将它改造适配我当前仓库：$fwName\n主题文件夹命名 $themeName');

    try {
      final tempDir = '${Directory.systemTemp.path}/hexo_theme_migrate_${DateTime.now().millisecondsSinceEpoch}';
      _tempDir = tempDir;

      if (url.startsWith('http')) {
        await widget.migrationService.cloneThemeRepo(url, tempDir);
      }

      setState(() => _status = '正在分析主题结构...');

      final dirStructure = await widget.migrationService.readDirectoryStructure(tempDir);
      final sourceFiles = await widget.migrationService.readAllTextFiles(tempDir);

      final sourceCode = StringBuffer();
      sourceCode.writeln('=== 目录结构 ===');
      sourceCode.writeln(dirStructure);
      sourceCode.writeln('\n=== 文件内容 ===');
      for (final entry in sourceFiles.entries.take(20)) {
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

      setState(() => _status = '分析完成：源框架 ${_analysis!.sourceFrameworkName}');

      _chatKey.currentState?.addMessage('assistant',
        '✅ 主题源码分析完成\n'
        '• 源框架：${_analysis!.sourceFrameworkName}\n'
        '• 模板语法：${_analysis!.templateSyntax}\n'
        '• 配置格式：${_analysis!.configFormat}\n'
        '• 关键文件：${_analysis!.keyFiles.take(10).join(', ')}\n\n'
        '正在开始跨框架迁移转换...',
      );

      setState(() => _status = '正在 AI 跨框架迁移转换...');

      final allSourceCode = StringBuffer();
      for (final entry in sourceFiles.entries) {
        final content = entry.value.length > 5000
            ? '${entry.value.substring(0, 5000)}\n... (截断)'
            : entry.value;
        allSourceCode.writeln('\n=== ${entry.key} ===');
        allSourceCode.writeln(content);
      }

      // 迁移前创建快照，以便回滚
      if (widget.snapshotService != null) {
        try {
          await widget.snapshotService!.createSnapshot(
            'theme_migration_${DateTime.now().millisecondsSinceEpoch}',
            '迁移前快照：${_analysis!.sourceFrameworkName} → ${repo.frameworkId}',
            allSourceCode.toString(),
          );
        } catch (e) {
          // 快照失败不阻断迁移主流程
          debugPrint('Migration snapshot error: $e');
        }
      }

      _migrationResult = await widget.migrationService.migrate(
        settings: widget.settings,
        sourceFramework: _analysis!.sourceFramework,
        targetFramework: repo.frameworkId,
        sourceCode: allSourceCode.toString(),
        themeName: themeName,
      );

      _selectedFilePaths = _migrationResult!.files.map((f) => f.path).toSet();

      setState(() => _status = '迁移完成！共 ${_migrationResult!.files.length} 个文件');

      _chatKey.currentState?.addMessage('assistant',
        '✅ 主题迁移完成！\n\n'
        '生成文件 ${_migrationResult!.files.length} 个（已全选）：\n'
        '${_migrationResult!.files.map((f) => '• ${f.path}').join('\n')}\n\n'
        '点击右上角 📋 按钮预览文件差异并选择性迁移，\n'
        '或继续对话微调后写入。',
      );

      if (_selfCheckEnabled) {
        setState(() => _status = '正在自动检测代码...');
        final checkResult = await widget.selfChecker.check(
          settings: widget.settings,
          generatedContent: _migrationResult!.rawOutput,
          sessionType: AiSessionType.themeMigration,
          blogFramework: repo.frameworkId,
        );
        if (checkResult.hasError) {
          _chatKey.currentState?.addMessage('assistant', '⚠️ 自检发现问题：\n${checkResult.issues.join('\n')}');
        } else {
          _chatKey.currentState?.addMessage('assistant', '✅ ${checkResult.message}');
        }
      }
    } catch (e) {
      _chatKey.currentState?.addMessage('assistant', '❌ 迁移过程出错: $e');
      setState(() => _status = '迁移失败: $e');
    } finally {
      _cleanupTemp();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showDiffPreview() {
    if (_migrationResult == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final cs = Theme.of(ctx).colorScheme;
          final files = _migrationResult!.files;
          final selectedCount = _selectedFilePaths.length;
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, scrollCtrl) => Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.difference_outlined, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '文件差异预览 ($selectedCount/${files.length})',
                          style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setSheet(() {
                            if (selectedCount == files.length) {
                              _selectedFilePaths.clear();
                            } else {
                              _selectedFilePaths = files.map((f) => f.path).toSet();
                            }
                          });
                          setState(() {});
                        },
                        child: Text(selectedCount == files.length ? '取消全选' : '全选'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: files.length,
                    itemBuilder: (ctx, i) {
                      final file = files[i];
                      final isSelected = _selectedFilePaths.contains(file.path);
                      final isPreview = _previewFileIndex == i;
                      return Column(
                        children: [
                          InkWell(
                            onTap: () {
                              setSheet(() => _previewFileIndex = _previewFileIndex == i ? null : i);
                              setState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (v) {
                                      setSheet(() {
                                        if (v == true) {
                                          _selectedFilePaths.add(file.path);
                                        } else {
                                          _selectedFilePaths.remove(file.path);
                                        }
                                      });
                                      setState(() {});
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(_fileIcon(file.path), size: 18, color: cs.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(file.path, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isSelected ? cs.onSurface : cs.outline), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        Text('${file.language} · ${file.content.length} 字符', style: TextStyle(fontSize: 11, color: cs.outline)),
                                      ],
                                    ),
                                  ),
                                  Icon(isPreview ? Icons.expand_less : Icons.expand_more, size: 20, color: cs.outline),
                                ],
                              ),
                            ),
                          ),
                          if (isPreview)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                              ),
                              constraints: const BoxConstraints(maxHeight: 300),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  file.content,
                                  style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface, height: 1.5),
                                ),
                              ),
                            ),
                          Divider(height: 1, color: cs.outlineVariant.withOpacity(0.2)),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _fileIcon(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'ejs': case 'html': case 'njk': case 'liquid': return Icons.code;
      case 'css': case 'scss': case 'less': return Icons.palette_outlined;
      case 'js': case 'ts': case 'jsx': case 'tsx': return Icons.javascript;
      case 'yml': case 'yaml': case 'toml': case 'json': return Icons.settings;
      case 'md': return Icons.article_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  Future<void> _writeFiles() async {
    if (_migrationResult == null) return;

    final selectedFiles = _migrationResult!.files
        .where((f) => _selectedFilePaths.contains(f.path))
        .toList();

    if (selectedFiles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有选中任何文件')),
        );
      }
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认写入主题文件'),
        content: Text(
          '即将写入 ${selectedFiles.length} 个文件到 themes/${_migrationResult!.themeName}/，\n\n'
          '${_selectedFilePaths.length < _migrationResult!.files.length ? '⚠️ 已取消选中 ${_migrationResult!.files.length - _selectedFilePaths.length} 个文件\n\n' : ''}'
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
      _status = '正在写入 ${selectedFiles.length} 个文件...';
    });

    try {
      final repo = widget.activeRepo ??
            (widget.repos.isNotEmpty ? widget.repos.first : null);
      if (repo == null) {
        _chatKey.currentState?.addMessage('assistant',
          '❌ 未找到可用仓库，请先在设置中配置仓库。',
        );
        return;
      }
      for (final file in selectedFiles) {
        await widget.githubService.putRawFile(
          repo,
          file.path,
          file.content,
          commitMessage: 'theme: migrate ${_migrationResult!.themeName} - ${file.path}',
        );
      }

      _chatKey.currentState?.addMessage('assistant',
        '✅ 已写入 ${selectedFiles.length} 个文件到 themes/${_migrationResult!.themeName}/\n\n'
        '请推送仓库并在远端构建测试。如有异常，可使用「回滚主题快照」指令恢复。',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已写入 $selectedFiles.length 个文件到主题目录')),
        );
      }
    } catch (e) {
      _chatKey.currentState?.addMessage('assistant', '❌ 写入失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cleanupTemp() {
    if (_tempDir != null) {
      try {
        final dir = Directory(_tempDir!);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (e) { debugPrint('ThemeMigration: write files failed: $e'); }
      _tempDir = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final repo = widget.activeRepo ?? (widget.repos.isNotEmpty ? widget.repos.first : null);
    final fw = repo != null ? BlogFramework.byId(repo.frameworkId) : null;

    return PopScope(
      canPop: true,
      child: Scaffold(
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
          if (_migrationResult != null)
            IconButton(
              icon: const Icon(Icons.difference_outlined),
              tooltip: '文件差异预览',
              onPressed: _busy ? null : _showDiffPreview,
            ),
          if (_migrationResult != null)
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: '写入主题文件',
              onPressed: _busy ? null : _writeFiles,
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
        sessionType: AiSessionType.themeMigration,
        blogFramework: repo?.frameworkId,
        targetFramework: fw?.name,
        themesPath: 'themes',
        gitHubService: widget.githubService,
        activeRepo: repo,
        storageService: widget.storageService,
        initialMessage: '欢迎使用 AI 主题跨框架迁移助手！\n\n'
            '你可以直接输入主题 Git 地址开始迁移，例如：\n'
            '「拉取 https://github.com/xxx/theme 转换到 Hexo，命名为 my-theme」\n\n'
            '⚠️ 请遵守主题开源协议，仅迁移拥有合法开源许可的源码。',
        onSettingsChanged: widget.onSettingsChanged,
        headerBuilder: (ctx, chatState) {
          if (!_showInputForm) return [];
          return [
            Container(
              padding: const EdgeInsets.all(12),
              color: cs.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber, size: 16, color: Colors.amber),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          '请遵守主题开源协议，仅迁移拥有合法开源许可的源码，严禁商用侵权。',
                          style: TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (fw != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 14, color: cs.primary),
                          const SizedBox(width: 6),
                          Text('目标框架: ${fw.name} | 主题目录: themes/', style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _urlCtrl,
                          decoration: const InputDecoration(
                            labelText: '源码地址',
                            hintText: 'Git URL 或 ZIP 链接',
                            prefixIcon: Icon(Icons.link, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _themeNameCtrl,
                          decoration: const InputDecoration(
                            labelText: '主题名称',
                            hintText: 'my-theme',
                            prefixIcon: Icon(Icons.folder_outlined, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _busy ? null : () => _startMigration(),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('迁移'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
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
            if (_busy)
              LinearProgressIndicator(minHeight: 2, color: cs.primary),
            if (_status != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: cs.primaryContainer.withOpacity(0.5),
                child: Row(
                  children: [
                    if (_busy) ...[
                      SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: Text(_status!, style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer))),
                  ],
                ),
              ),
          ];
        },
      ),
      ),
    );
  }

  Widget _quickChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 11)),
      onPressed: () {
        _chatKey.currentState?.sendMessage(text);
      },
    );
  }
}