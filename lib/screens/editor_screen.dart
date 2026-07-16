import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/article.dart';
import '../models/repo_config.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/image_service.dart';
import '../services/storage_service.dart';

class EditorScreen extends StatefulWidget {
  final Article article;
  final List<RepoConfig> repos;
  final RepoConfig? activeRepo;
  final AppSettings settings;
  final StorageService storage;
  final GitHubService github;
  final ImageService imageService;
  final AiService aiService;
  final Future<void> Function(Article) onSaveLocal;
  final Future<void> Function(Article) onPublished;
  final Future<void> Function(Article)? onDeletedRemote;

  const EditorScreen({
    super.key,
    required this.article,
    required this.repos,
    required this.activeRepo,
    required this.settings,
    required this.storage,
    required this.github,
    required this.imageService,
    required this.aiService,
    required this.onSaveLocal,
    required this.onPublished,
    this.onDeletedRemote,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}



class _EditorScreenState extends State<EditorScreen> {
  late TextEditingController _title;
  late TextEditingController _content;
  late TextEditingController _tags;
  late TextEditingController _categories;
  late TextEditingController _cover;
  late Article _article;
  RepoConfig? _repo;
  bool _busy = false;
  String? _status;
  final FocusNode _contentFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _repo = widget.activeRepo ??
        (widget.repos.isNotEmpty ? widget.repos.first : null);
    if (_article.repoId != null) {
      for (final r in widget.repos) {
        if (r.id == _article.repoId) _repo = r;
      }


    }


    _title = TextEditingController(text: _article.title);
    _content = TextEditingController(text: _article.content);
    _tags = TextEditingController(text: _article.tags.join(', '));
    _categories = TextEditingController(text: _article.categories.join(', '));
    _cover = TextEditingController(text: _article.cover ?? '');
  }



  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _tags.dispose();
    _categories.dispose();
    _cover.dispose();
    _contentFocus.dispose();
    super.dispose();
  }



  Article _collect({bool draft = true}) {
    final cover = _cover.text.trim();
    final title = _title.text.trim();
    return _article.copyWith(
      title: title.isEmpty ? '未命名' : title,
      content: _content.text,
      tags: _tags.text
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      categories: _categories.text
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      cover: cover.isEmpty ? null : cover,
      updatedAt: DateTime.now(),
      isDraft: draft,
      published: draft ? false : true,
      repoId: _repo?.id ?? _article.repoId,
    );
  }



  RepoConfig? get _resolvedRepo {
    final r = _repo;
    if (r == null) return null;
    if (r.token.isNotEmpty) return r;
    final t = widget.settings.effectiveGithubToken;
    if (t.isEmpty) return r;
    return r.copyWith(token: t);
  }



  Future<void> _saveLocal() async {
    final a = _collect(draft: true);
    setState(() {
      _article = a;
      _status = '本地已保存';
    });
    await widget.onSaveLocal(a);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('草稿已保存到本地')),
      );
    }


  }



  Future<void> _exportMarkdown() async {
    try {
      final a = _collect(draft: _article.isDraft && !_article.published);
      await widget.storage.exportDraftMarkdown(a);
      final dir = await widget.storage.draftsDir();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出到 ${dir.path}')),
        );
      }


      setState(() => _status = '已导出 Markdown');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }


    }


  }



  Future<void> _publish() async {
    final repo = _resolvedRepo;
    if (repo == null || repo.token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置仓库与 GitHub Token')),
      );
      return;
    }


    setState(() {
      _busy = true;
      _status = '正在上传...';
    });
    try {
      final a = _collect(draft: false);
      final published = await widget.github.upsertArticle(repo, a);
      setState(() {
        _article = published;
        _status = '发布成功';
      });
      await widget.onPublished(published);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已发布到 ${repo.fullName}/${published.remotePath}')),
        );
      }


    } catch (e) {
      setState(() => _status = '发布失败');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发布失败: $e')),
        );
      }


    } finally {
      if (mounted) setState(() => _busy = false);
    }


  }



  Future<void> _deleteRemote() async {
    final repo = _resolvedRepo;
    if (repo == null || repo.token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置仓库与 GitHub Token')),
      );
      return;
    }


    if (_article.remotePath == null || _article.remoteSha == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前不是远程已发布文章，无法删除')),
      );
      return;
    }


    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除已发布文章'),
        content: Text('确认从 GitHub 删除「${_article.title}」？\n${_article.remotePath}'),
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
    setState(() {
      _busy = true;
      _status = '正在删除远程文章...';
    });
    try {
      await widget.github.deleteArticle(repo, _article);
      final local = _collect(draft: true).copyWith(
        published: false,
        isDraft: true,
        remotePath: null,
        remoteSha: null,
      );
      setState(() {
        _article = local;
        _status = '远程已删除';
      });
      if (widget.onDeletedRemote != null) {
        await widget.onDeletedRemote!(local);
      } else {
        await widget.onSaveLocal(local);
      }


      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除远程文章')),
        );
        Navigator.pop(context);
      }


    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }


    } finally {
      if (mounted) setState(() => _busy = false);
    }


  }



  Future<void> _insertImage() async {
    setState(() {
      _busy = true;
      _status = '选择/压缩/上传图片...';
    });
    try {
      final bytes = await widget.imageService.pickImageBytes();
      if (bytes == null) {
        setState(() => _status = '已取消');
        return;
      }


      final url = await widget.imageService.uploadToImageBed(
        bytes,
        widget.settings,
      );
      final md = widget.imageService.markdownImage(url);
      _insertText(md);
      setState(() => _status = '图片已插入');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片上传失败: $e')),
        );
      }


    } finally {
      if (mounted) setState(() => _busy = false);
    }


  }



  Future<void> _aiContinue() async {
    if (widget.settings.activeAiProfile == null) {
      setState(() => _status = '请先在设置中配置 AI');
      return;
    }


    final before = _content.text.split('\n').take(8).join('\n');
    if (before.trim().isEmpty) {
      setState(() => _status = '先写一点内容，我会按上下文续写');
      return;
    }


    setState(() => _status = 'AI 正在续写...');
    try {
      final reply = await widget.aiService.complete(
        settings: widget.settings,
        userPrompt: before.trim(),
        systemPrompt: '你是中文 Markdown 写作助手，请自然续写以下内容，保持原文语气和格式，只输出续写部分。',
      );
      if (reply.isEmpty) return;
      _insertText('\n\n${reply.trim()}');
      setState(() => _status = 'AI 已续写');
    } catch (e) {
      setState(() => _status = 'AI 续写失败: $e');
    }


  }



  Future<void> _ai(String action) async {
    setState(() {
      _busy = true;
      _status = 'AI 处理中...';
    });
    try {
      String result;
      final text = _content.text;
      final sel = _content.selection;
      final selected = sel.isValid && sel.start != sel.end
          ? text.substring(sel.start, sel.end)
          : '';
      switch (action) {
        case 'polish':
          result = await widget.aiService.polish(widget.settings, text);
          _content.text = result;
          break;
        case 'continue':
          result = await widget.aiService.continueWrite(widget.settings, text);
          _insertText('\n\n$result');
          break;
        case 'summary':
          result = await widget.aiService.summarize(widget.settings, text);
          if (mounted) {
            await showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('AI 摘要'),
                content: SingleChildScrollView(child: Text(result)),
                actions: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: result));
                      Navigator.pop(context);
                    },
                    child: const Text('复制'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            );
          }


          break;
        case 'outline':
          final topic = _title.text.isEmpty ? text : _title.text;
          result = await widget.aiService.generateOutline(widget.settings, topic);
          _content.text = result;
          break;
        case 'code':
          final promptCtrl = TextEditingController(
            text: selected.isEmpty ? '' : selected,
          );
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('AI 生成代码'),
              content: TextField(
                controller: promptCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: '描述需要的代码，例如：Python 读取 CSV 并画图',
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('生成')),
              ],
            ),
          );
          if (ok != true) break;
          result = await widget.aiService.generateCode(
            widget.settings,
            promptCtrl.text.trim().isEmpty ? '写一段示例代码' : promptCtrl.text.trim(),
          );
          if (selected.isNotEmpty) {
            _wrapOrReplace(result);
          } else {
            _insertText('\n\n$result\n');
          }


          break;
        case 'rewrite':
          if (selected.isEmpty) {
            throw Exception('请先选中要改写的文字');
          }


          final instr = TextEditingController(text: '更简洁专业');
          final ok2 = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('AI 改写选中'),
              content: TextField(
                controller: instr,
                decoration: const InputDecoration(hintText: '改写指令'),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('改写')),
              ],
            ),
          );
          if (ok2 != true) break;
          result = await widget.aiService.rewriteSelection(
            widget.settings,
            selected,
            instr.text.trim(),
          );
          _wrapOrReplace(result);
          break;
      }


      setState(() => _status = 'AI 完成');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 失败: $e')),
        );
      }


    } finally {
      if (mounted) setState(() => _busy = false);
    }


  }



  void _insertText(String insert) {
    final sel = _content.selection;
    final text = _content.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, insert);
    _content.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    _contentFocus.requestFocus();
  }



  void _wrapOrReplace(String replacement) {
    final sel = _content.selection;
    final text = _content.text;
    if (!sel.isValid) {
      _insertText(replacement);
      return;
    }


    _content.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, replacement),
      selection: TextSelection.collapsed(offset: sel.start + replacement.length),
    );
    _contentFocus.requestFocus();
  }



  void _wrapSelection(String left, String right, {String placeholder = ''}) {
    final sel = _content.selection;
    final text = _content.text;
    if (!sel.isValid || sel.start == sel.end) {
      final body = placeholder.isEmpty ? '' : placeholder;
      final insert = '$left$body$right';
      final start = sel.isValid ? sel.start : text.length;
      final newText = text.replaceRange(start, start, insert);
      final cursor = start + left.length + body.length;
      _content.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursor),
      );
      _contentFocus.requestFocus();
      return;
    }


    final selected = text.substring(sel.start, sel.end);
    final replacement = '$left$selected$right';
    _content.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, replacement),
      selection: TextSelection(
        baseOffset: sel.start + left.length,
        extentOffset: sel.start + left.length + selected.length,
      ),
    );
    _contentFocus.requestFocus();
  }



  void _insertCodeBlock({String language = ''}) {
    final sel = _content.selection;
    final text = _content.text;
    final selected = (sel.isValid && sel.start != sel.end)
        ? text.substring(sel.start, sel.end)
        : '';
    final body = selected.isEmpty ? '' : selected;
    final fence = '```$language\n$body\n```\n';
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, fence);
    // 光标放到代码块内部行首
    final cursor = start + 3 + language.length + 1;
    _content.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _contentFocus.requestFocus();
  }



  void _indentSelection() {
    final sel = _content.selection;
    final text = _content.text;
    if (!sel.isValid) return;
    final lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    final lineEnd = text.indexOf('\n', sel.end);
    final end = lineEnd < 0 ? text.length : lineEnd;
    final block = text.substring(lineStart, end);
    final indented = block.split('\n').map((l) => '  $l').join('\n');
    final newText = text.replaceRange(lineStart, end, indented);
    _content.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + indented.length,
      ),
    );
    _contentFocus.requestFocus();
  }



  void _outdentSelection() {
    final sel = _content.selection;
    final text = _content.text;
    if (!sel.isValid) return;
    final lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    final lineEnd = text.indexOf('\n', sel.end);
    final end = lineEnd < 0 ? text.length : lineEnd;
    final block = text.substring(lineStart, end);
    final out = block.split('\n').map((l) {
      if (l.startsWith('  ')) return l.substring(2);
      if (l.startsWith('\t')) return l.substring(1);
      return l;
    }).join('\n');
    final newText = text.replaceRange(lineStart, end, out);
    _content.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + out.length,
      ),
    );
    _contentFocus.requestFocus();
  }



  Future<void> _pickCodeLang() async {
    const langs = [
      'dart',
      'js',
      'ts',
      'python',
      'java',
      'kotlin',
      'go',
      'rust',
      'bash',
      'json',
      'yaml',
      'html',
      'css',
      'sql',
      'c',
      'cpp',
      'md',
      '',
    ];
    final lang = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('插入代码块', style: TextStyle(fontWeight: FontWeight.w700))),
            ...langs.map(
              (l) => ListTile(
                title: Text(l.isEmpty ? '无语言标记' : l),
                onTap: () => Navigator.pop(ctx, l),
              ),
            ),
          ],
        ),
      ),
    );
    if (lang != null) _insertCodeBlock(language: lang);
  }



  void _insertHeading(int level) {
    final prefix = '${'#' * level} ';
    final sel = _content.selection;
    final text = _content.text;
    final start = sel.isValid ? sel.start : text.length;
    // 找当前行首
    final lineStart = text.lastIndexOf('\n', start - 1) + 1;
    final newText = text.replaceRange(lineStart, lineStart, prefix);
    _content.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + prefix.length),
    );
    _contentFocus.requestFocus();
  }



  void _insertList(String marker) {
    final sel = _content.selection;
    final text = _content.text;
    if (sel.isValid && sel.start != sel.end) {
      final selected = text.substring(sel.start, sel.end);
      final lines = selected.split('\n').map((l) => l.isEmpty ? l : '$marker$l').join('\n');
      _wrapOrReplace(lines);
      return;
    }


    _insertText('\n$marker');
  }



  String get _aiLabel {
    final p = widget.settings.activeAiProfile;
    if (p == null) return '未配置 AI';
    return p.displayLabel;
  }



  @override
  Widget build(BuildContext context) {
    final isRemote = _article.remotePath != null && _article.remoteSha != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_article.published || isRemote ? '编辑文章' : '写文章'),
        actions: [
          IconButton(
            tooltip: '预览',
            onPressed: _busy ? null : () {
              final md = _content.text.isEmpty ? '*（暂无内容）*' : _content.text;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => _PreviewPage(markdown: md)),
              );
            },
            icon: const Icon(Icons.visibility_outlined),
          ),
          IconButton(
            tooltip: '保存草稿',
            onPressed: _busy ? null : _saveLocal,
            icon: const Icon(Icons.save_outlined),
          ),
          IconButton(
            tooltip: '导出 Markdown 文件',
            onPressed: _busy ? null : _exportMarkdown,
            icon: const Icon(Icons.ios_share_outlined),
          ),
          if (isRemote)
            IconButton(
              tooltip: '删除远程文章',
              onPressed: _busy ? null : _deleteRemote,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
          IconButton(
            tooltip: '发布到 GitHub',
            onPressed: _busy ? null : _publish,
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                if (widget.repos.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _repo?.id,
                    decoration: const InputDecoration(
                      labelText: '目标仓库',
                      prefixIcon: Icon(Icons.storage_outlined),
                    ),
                    items: widget.repos
                        .map(
                          (r) => DropdownMenuItem(
                            value: r.id,
                            child: Text('${r.name} (${r.fullName})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _repo = widget.repos.firstWhere((e) => e.id == v);
                      });
                    },
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    prefixIcon: Icon(Icons.title),
                  ),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: '标签（逗号分隔）',
                    prefixIcon: Icon(Icons.tag),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _categories,
                  decoration: const InputDecoration(
                    labelText: '分类（逗号分隔）',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cover,
                  decoration: const InputDecoration(
                    labelText: '封面图 URL（可选）',
                    prefixIcon: Icon(Icons.image_outlined),
                    hintText: '可先用图床上传后粘贴链接',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '当前 AI: $_aiLabel',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ToolChip(
                        icon: Icons.format_bold,
                        label: '粗体',
                        onTap: () => _wrapSelection('**', '**', placeholder: '粗体'),
                      ),
                      _ToolChip(
                        icon: Icons.format_italic,
                        label: '斜体',
                        onTap: () => _wrapSelection('*', '*', placeholder: '斜体'),
                      ),
                      _ToolChip(
                        icon: Icons.format_strikethrough,
                        label: '删除线',
                        onTap: () => _wrapSelection('~~', '~~', placeholder: '删除线'),
                      ),
                      _ToolChip(
                        icon: Icons.code,
                        label: '行内码',
                        onTap: () => _wrapSelection('`', '`', placeholder: 'code'),
                      ),
                      _ToolChip(
                        icon: Icons.code_off,
                        label: '代码块',
                        onTap: _pickCodeLang,
                      ),
                      _ToolChip(
                        icon: Icons.bolt,
                        label: 'AI+',
                        onTap: _busy ? null : _aiContinue,
                      ),
                      _ToolChip(
                        icon: Icons.title,
                        label: 'H1',
                        onTap: () => _insertHeading(1),
                      ),
                      _ToolChip(
                        icon: Icons.title,
                        label: 'H2',
                        onTap: () => _insertHeading(2),
                      ),
                      _ToolChip(
                        icon: Icons.title,
                        label: 'H3',
                        onTap: () => _insertHeading(3),
                      ),
                      _ToolChip(
                        icon: Icons.format_list_bulleted,
                        label: '列表',
                        onTap: () => _insertList('- '),
                      ),
                      _ToolChip(
                        icon: Icons.format_list_numbered,
                        label: '有序',
                        onTap: () => _insertList('1. '),
                      ),
                      _ToolChip(
                        icon: Icons.check_box_outlined,
                        label: '任务',
                        onTap: () => _insertList('- [ ] '),
                      ),
                      _ToolChip(
                        icon: Icons.format_quote,
                        label: '引用',
                        onTap: () => _insertList('> '),
                      ),
                      _ToolChip(
                        icon: Icons.horizontal_rule,
                        label: '分割线',
                        onTap: () => _insertText('\n\n---\n\n'),
                      ),
                      _ToolChip(
                        icon: Icons.data_object,
                        label: '缩进',
                        onTap: _indentSelection,
                      ),
                      _ToolChip(
                        icon: Icons.format_indent_decrease,
                        label: '取消缩进',
                        onTap: _outdentSelection,
                      ),
                      _ToolChip(
                        icon: Icons.link,
                        label: '链接',
                        onTap: () => _wrapSelection('[', '](https://)', placeholder: '链接文字'),
                      ),
                      _ToolChip(
                        icon: Icons.grid_on,
                        label: '表格',
                        onTap: () => _insertText(
                          '\n| 列1 | 列2 |\n| --- | --- |\n| 值1 | 值2 |\n',
                        ),
                      ),
                      _ToolChip(
                        icon: Icons.image_outlined,
                        label: '图床',
                        onTap: _busy ? null : _insertImage,
                      ),
                      _ToolChip(
                        icon: Icons.auto_awesome,
                        label: '润色',
                        onTap: _busy ? null : () => _ai('polish'),
                      ),
                      _ToolChip(
                        icon: Icons.edit_note,
                        label: '续写',
                        onTap: _busy ? null : () => _ai('continue'),
                      ),
                      _ToolChip(
                        icon: Icons.summarize_outlined,
                        label: '摘要',
                        onTap: _busy ? null : () => _ai('summary'),
                      ),
                      _ToolChip(
                        icon: Icons.account_tree_outlined,
                        label: '大纲',
                        onTap: _busy ? null : () => _ai('outline'),
                      ),
                      _ToolChip(
                        icon: Icons.developer_mode,
                        label: 'AI代码',
                        onTap: _busy ? null : () => _ai('code'),
                      ),
                      _ToolChip(
                        icon: Icons.sync_alt,
                        label: '改写',
                        onTap: _busy ? null : () => _ai('rewrite'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                  TextField(
                    controller: _content,
                    focusNode: _contentFocus,
                    minLines: 16,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      labelText: 'Markdown 正文',
                      alignLabelWithHint: true,
                      hintText:
                          '支持 # 标题、**粗体**、`行内代码`、```代码块```、列表、引用、表格、图片...\n编辑完可存草稿或直接发布',
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      height: 1.5,
                      fontSize: 14.5,
                    ),
                  ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _status!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
                if (_article.remotePath != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '远程: ${_article.remotePath}',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _saveLocal,
                  icon: const Icon(Icons.drafts_outlined),
                  label: const Text('存草稿'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _publish,
                  icon: const Icon(Icons.publish_outlined),
                  label: Text(isRemote ? '更新发布' : '发布'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


}



class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ToolChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 16),
        label: Text(label),
        onPressed: onTap,
      ),
    );
  }


}

class _PreviewPage extends StatelessWidget {
  final String markdown;
  const _PreviewPage({required this.markdown});

  @override
  Widget build(BuildContext context) {
    // 预处理：每行结尾加两个空格实现软换行，让编辑器的换行在预览中也换行
    final processed = markdown
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) {
          final t = line.trimRight();
          if (t.isEmpty) return '';
          return t + '  ';
        })
        .join('\n');

    final style = MarkdownStyleSheet(
      h1: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, height: 1.6, color: Color(0xFF1a1a2e)),
      h2: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.6, color: Color(0xFF1a1a2e)),
      h3: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.6, color: Color(0xFF1a1a2e)),
      p: const TextStyle(fontSize: 17, height: 1.8, color: Color(0xFF333333), letterSpacing: 0.3),
      listBullet: const TextStyle(fontSize: 17, height: 1.8, color: Color(0xFF333333)),
      code: TextStyle(fontSize: 14, backgroundColor: const Color(0xFFF0F0F0), color: const Color(0xFFE53935), fontFamily: 'monospace'),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      blockquoteDecoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        border: const Border(left: BorderSide(color: Color(0xFF4A90D9), width: 4)),
        borderRadius: BorderRadius.circular(4),
      ),
      blockquote: const TextStyle(fontSize: 16, height: 1.7, color: Color(0xFF555555), fontStyle: FontStyle.italic),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: const Color(0xFFE0E0E0), width: 1)),
      ),
      strong: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1a1a2e)),
      em: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF555555)),
      del: const TextStyle(decoration: TextDecoration.lineThrough, color: Color(0xFF999999)),
      a: const TextStyle(color: Color(0xFF4A90D9), decoration: TextDecoration.underline),
      tableHead: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF333333)),
      tableBody: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
      tableBorder: TableBorder.all(color: const Color(0xFFE0E0E0), width: 1),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      codeblockPadding: const EdgeInsets.all(16),
      listIndent: 24,
      listBulletPadding: const EdgeInsets.only(right: 8),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: const Text('预览'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1a1a2e),
        elevation: 0.5,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      body: Container(
        color: const Color(0xFFF2F4F7),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: MarkdownBody(
              data: processed,
              selectable: true,
              styleSheet: style,
            ),
          ),
        ),
      ),
    );
  }
}
