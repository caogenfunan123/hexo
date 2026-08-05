import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/repo_config.dart';
import '../models/template_item.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';

/// 模板管理页面：内置预设 + 自定义模板 + AI 生成 + AI 仓库适配
class TemplateManagerScreen extends StatefulWidget {
  final StorageService storage;
  final AiService aiService;
  final AppSettings settings;
  final List<RepoConfig> repos;
  final GitHubService? githubService;

  const TemplateManagerScreen({
    super.key,
    required this.storage,
    required this.aiService,
    required this.settings,
    this.repos = const [],
    this.githubService,
  });

  @override
  State<TemplateManagerScreen> createState() => _TemplateManagerScreenState();
}

class _TemplateManagerScreenState extends State<TemplateManagerScreen> {
  List<TemplateItem> _templates = [];
  bool _loading = true;
  String _filter = 'all'; // all, post, page, custom, builtin

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await widget.storage.loadAllTemplates();
    if (mounted) setState(() {
      _templates = all;
      _loading = false;
    });
  }

  List<TemplateItem> get _filtered {
    var list = _templates;
    if (_filter == 'post') list = list.where((t) => t.isPost).toList();
    if (_filter == 'page') list = list.where((t) => !t.isPost).toList();
    if (_filter == 'custom') list = list.where((t) => !t.isBuiltin).toList();
    if (_filter == 'builtin') list = list.where((t) => t.isBuiltin).toList();
    return list;
  }

  Future<void> _addCustom() async {
    final nameCtrl = TextEditingController();
    final fmCtrl = TextEditingController();
    final isPost = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建自定义模板'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '模板名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: fmCtrl,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'FrontMatter 模板',
                hintText: '---\ntitle: {{title}}\ndate: {{date}}\ntags: {{tags}}\n---',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('博文模板')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('页面模板')),
        ],
      ),
    );
    if (isPost == null) return;
    if (nameCtrl.text.trim().isEmpty) return;
    final now = DateTime.now();
    final t = TemplateItem(
      id: 'custom_${now.millisecondsSinceEpoch}',
      name: nameCtrl.text.trim(),
      frontMatter: fmCtrl.text.trim().isEmpty
          ? '---\ntitle: {{title}}\ndate: {{date}}\ntags: {{tags}}\n---'
          : fmCtrl.text.trim(),
      isPost: isPost,
      isBuiltin: false,
      createdAt: now,
    );
    final saved = await widget.storage.loadTemplates();
    saved.add(t);
    await widget.storage.saveTemplates(saved);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已创建模板: ${t.name}')),
      );
    }
  }

  Future<void> _aiGenerate() async {
    final promptCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 生成模板'),
        content: TextField(
          controller: promptCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '描述你需要的模板',
            hintText: '例如：生成 Butterfly 主题友链页面模板\n或：生成 Hugo 归档页面模板',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('AI 生成')),
        ],
      ),
    );
    if (ok != true || promptCtrl.text.trim().isEmpty) return;

    setState(() => _loading = true);
    try {
      final result = await widget.aiService.generateTemplate(
        settings: widget.settings,
        userPrompt: promptCtrl.text.trim(),
      );
      if (mounted) {
        final nameCtrl = TextEditingController(text: 'AI: ${promptCtrl.text.trim().substring(0, 20)}');
        final ok2 = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('AI 生成的模板'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '模板名称'),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      result,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('放弃')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存模板')),
            ],
          ),
        );
        if (ok2 == true) {
          final now = DateTime.now();
          final t = TemplateItem(
            id: 'ai_${now.millisecondsSinceEpoch}',
            name: nameCtrl.text.trim().isEmpty ? 'AI 模板' : nameCtrl.text.trim(),
            frontMatter: result,
            isPost: !result.contains('page') && !result.contains('layout: page'),
            isBuiltin: false,
            createdAt: now,
          );
          final saved = await widget.storage.loadTemplates();
          saved.add(t);
          await widget.storage.saveTemplates(saved);
          await _load();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('AI 模板已保存: ${t.name}')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 生成失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editTemplate(TemplateItem t) async {
    TemplateItem target = t;
    if (t.isBuiltin) {
      // 内置模板：自动复制为自定义模板后再编辑
      final now = DateTime.now();
      final copy = t.copyWith(
        id: 'edit_${now.millisecondsSinceEpoch}',
        name: '${t.name} (自定义)',
        isBuiltin: false,
        createdAt: now,
      );
      final saved = await widget.storage.loadTemplates();
      saved.add(copy);
      await widget.storage.saveTemplates(saved);
      target = copy;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已复制内置模板为可编辑: ${copy.name}')),
        );
      }
    }
    final nameCtrl = TextEditingController(text: target.name);
    final fmCtrl = TextEditingController(text: target.frontMatter);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑模板'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fmCtrl,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'FrontMatter',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final saved = await widget.storage.loadTemplates();
    final idx = saved.indexWhere((e) => e.id == target.id);
    if (idx >= 0) {
      saved[idx] = target.copyWith(
        name: nameCtrl.text.trim(),
        frontMatter: fmCtrl.text.trim(),
      );
      await widget.storage.saveTemplates(saved);
      await _load();
    }
  }

  Future<void> _duplicate(TemplateItem t) async {
    final now = DateTime.now();
    final copy = t.copyWith(
      id: 'copy_${now.millisecondsSinceEpoch}',
      name: '${t.name} (副本)',
      isBuiltin: false,
      createdAt: now,
    );
    final saved = await widget.storage.loadTemplates();
    saved.add(copy);
    await widget.storage.saveTemplates(saved);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制: ${copy.name}')),
      );
    }
  }

  Future<void> _delete(TemplateItem t) async {
    if (t.isBuiltin) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('确认删除「${t.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final saved = await widget.storage.loadTemplates();
    saved.removeWhere((e) => e.id == t.id);
    await widget.storage.saveTemplates(saved);
    await _load();
  }

  Future<void> _export(TemplateItem t) async {
    final json = t.exportString();
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模板已复制到剪贴板，可分享给他人')),
      );
    }
  }

  Future<void> _import() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空，请先复制他人分享的模板 JSON')),
        );
      }
      return;
    }
    try {
      final t = TemplateItem.importFrom(data.text!);
      final saved = await widget.storage.loadTemplates();
      saved.add(t);
      await widget.storage.saveTemplates(saved);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入模板: ${t.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  /// AI 适配：分析仓库，自动检测框架并生成模板
  Future<void> _aiAnalyzeRepo() async {
    if (widget.githubService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置 GitHub 仓库')),
      );
      return;
    }
    if (widget.repos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的仓库，请先添加仓库')),
      );
      return;
    }

    // 选择要分析的仓库
    RepoConfig? selectedRepo = widget.repos.first;
    if (widget.repos.length > 1) {
      final chosen = await showDialog<RepoConfig>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择要分析的仓库'),
          children: widget.repos.map((r) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, r),
            child: Text('${r.owner}/${r.repo} (${r.frameworkId})'),
          )).toList(),
        ),
      );
      if (chosen == null) return;
      selectedRepo = chosen;
    }

    setState(() => _loading = true);
    try {
      // 读取仓库文件
      final files = await widget.githubService!.readRepoAnalysisFiles(selectedRepo);
      if (files.isEmpty) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('仓库中没有找到配置文件或文章，请确认仓库类型')),
          );
        }
        return;
      }

      // 构建分析信息
      final buf = StringBuffer();
      buf.writeln('仓库: ${selectedRepo.owner}/${selectedRepo.repo}');
      buf.writeln('当前框架: ${selectedRepo.frameworkId}');
      buf.writeln();
      buf.writeln('=== 仓库文件内容 ===');
      for (final entry in files.entries) {
        buf.writeln('--- ${entry.key} ---');
        // 限制每个文件内容长度，避免超出 token 限制
        final content = entry.value.length > 2000
            ? '${entry.value.substring(0, 2000)}...'
            : entry.value;
        buf.writeln(content);
        buf.writeln();
      }

      // 调用 AI 分析
      final result = await widget.aiService.analyzeRepoForTemplate(
        settings: widget.settings,
        repoInfo: buf.toString(),
      );

      if (mounted) {
        setState(() => _loading = false);

        if (result.containsKey('error')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('AI 分析失败: ${result['error']}')),
          );
          return;
        }

        // 显示 AI 分析结果
        final framework = result['framework']?.toString() ?? '未知';
        final frameworkName = result['frameworkName']?.toString() ?? framework;
        final theme = result['theme']?.toString() ?? '未知';
        final explanation = result['explanation']?.toString() ?? '';
        final postTemplate = result['postTemplate']?.toString() ?? '';
        final pageTemplate = result['pageTemplate']?.toString() ?? '';

        await _showAiResultDialog(framework, frameworkName, theme, explanation, postTemplate, pageTemplate);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 分析失败: $e')),
        );
      }
    }
  }

  Future<void> _showAiResultDialog(
    String framework, String frameworkName, String theme, String explanation,
    String postTemplate, String pageTemplate,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 22),
            const SizedBox(width: 8),
            const Text('AI 仓库分析结果'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _resultRow('框架', frameworkName),
              _resultRow('主题', theme),
              _resultRow('说明', explanation),
              const SizedBox(height: 12),
              const Text('📝 博文模板:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(postTemplate, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
              if (pageTemplate.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('📄 页面模板:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(pageTemplate, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('放弃'),
          ),
          if (postTemplate.isNotEmpty)
            FilledButton.icon(
              icon: const Icon(Icons.save, size: 16),
              label: const Text('保存博文模板'),
              onPressed: () async {
                final now = DateTime.now();
                final t = TemplateItem(
                  id: 'ai_repo_${now.millisecondsSinceEpoch}',
                  name: 'AI适配: $frameworkName${theme != '未知' ? ' $theme' : ''}',
                  frontMatter: postTemplate,
                  frameworkId: framework,
                  isPost: true,
                  isBuiltin: false,
                  createdAt: now,
                );
                final saved = await widget.storage.loadTemplates();
                saved.add(t);
                await widget.storage.saveTemplates(saved);
                await _load();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已保存模板: ${t.name}')),
                  );
                }
              },
            ),
          if (pageTemplate.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.save, size: 16),
              label: const Text('保存页面模板'),
              onPressed: () async {
                final now = DateTime.now();
                final t = TemplateItem(
                  id: 'ai_repo_${now.millisecondsSinceEpoch}_page',
                  name: 'AI适配: $frameworkName${theme != '未知' ? ' $theme' : ''} 页面',
                  frontMatter: pageTemplate,
                  frameworkId: framework,
                  isPost: false,
                  isBuiltin: false,
                  createdAt: now,
                );
                final saved = await widget.storage.loadTemplates();
                saved.add(t);
                await widget.storage.saveTemplates(saved);
                await _load();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已保存模板: ${t.name}')),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text('$label:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  AppSettings get settings => widget.settings;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('模板管理'),
        actions: [
          IconButton(
            tooltip: '导入模板',
            onPressed: _import,
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'AI 生成',
            onPressed: _aiGenerate,
            icon: const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: 'AI 适配仓库',
            onPressed: widget.githubService != null ? _aiAnalyzeRepo : null,
            icon: const Icon(Icons.analytics_outlined),
          ),
          IconButton(
            tooltip: '新建自定义',
            onPressed: _addCustom,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          // 筛选栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('全部', 'all'),
                  _filterChip('博文', 'post'),
                  _filterChip('页面', 'page'),
                  _filterChip('自定义', 'custom'),
                  _filterChip('内置', 'builtin'),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('暂无模板'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) {
                          final t = _filtered[i];
                          return _templateCard(t);
                        },
                      ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _filterChip(String label, String value) {
    final active = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => setState(() => _filter = value),
        backgroundColor: Colors.white,
        selectedColor: Theme.of(context).colorScheme.primaryContainer,
      ),
    );
  }

  Widget _templateCard(TemplateItem t) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  t.isPost ? Icons.article_outlined : Icons.web_outlined,
                  size: 18,
                  color: t.isPost ? const Color(0xFF0EA5E9) : const Color(0xFF10B981),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                if (t.isBuiltin)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '内置',
                      style: TextStyle(fontSize: 11, color: cs.primary),
                    ),
                  ),
                if (!t.isBuiltin)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '自定义',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8B5CF6)),
                    ),
                  ),
                const SizedBox(width: 4),
                Text(
                  t.frameworkId == 'custom' ? '通用' : t.frameworkId,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                t.frontMatter.length > 200
                    ? '${t.frontMatter.substring(0, 200)}...'
                    : t.frontMatter,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF334155),
                  height: 1.4,
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '导出分享',
                  onPressed: () => _export(t),
                  icon: const Icon(Icons.ios_share, size: 18),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '复制',
                  onPressed: () => _duplicate(t),
                  icon: const Icon(Icons.copy, size: 18),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '编辑',
                  onPressed: () => _editTemplate(t),
                  icon: const Icon(Icons.edit, size: 18),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
                if (!t.isBuiltin) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '删除',
                    onPressed: () => _delete(t),
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}