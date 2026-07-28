import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/app_settings.dart';
import '../models/article.dart';
import '../models/article_template.dart';
import '../models/repo_config.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/image_service.dart';
import '../services/storage_service.dart';
import '../widgets/common_widgets.dart';

class EditorPageInline extends StatefulWidget {
  final List<RepoConfig> repos;
  final RepoConfig? activeRepo;
  final AppSettings settings;
  final StorageService storage;
  final GitHubService github;
  final ImageService imageService;
  final AiService aiService;
  final Future<void> Function(Article) onSaveLocal;
  final Future<void> Function(Article) onPublished;
  final List<ArticleTemplate> templates;
  final Future<void> Function(List<ArticleTemplate>) onTemplatesChanged;

  const EditorPageInline({
    super.key,
    required this.repos,
    required this.activeRepo,
    required this.settings,
    required this.storage,
    required this.github,
    required this.imageService,
    required this.aiService,
    required this.onSaveLocal,
    required this.onPublished,
    required this.templates,
    required this.onTemplatesChanged,
  });

  @override
  State<EditorPageInline> createState() => _EditorPageInlineState();
}

class _EditorPageInlineState extends State<EditorPageInline> {
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
    _article = Article(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: '',
      content: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDraft: true,
      repoId: widget.activeRepo?.id,
    );
    _repo = widget.activeRepo ?? (widget.repos.isNotEmpty ? widget.repos.first : null);
    _title = TextEditingController();
    _content = TextEditingController();
    _tags = TextEditingController();
    _categories = TextEditingController();
    _cover = TextEditingController();
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
      tags: _tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      categories: _categories.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
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
    setState(() { _article = a; _status = '本地已保存'; });
    await widget.onSaveLocal(a);
    if (mounted) showToast(context, '草稿已保存');
  }

  Future<void> _publish() async {
    final repo = _resolvedRepo;
    if (repo == null || repo.token.isEmpty) { showToast(context, '请先配置仓库与 Token'); return; }
    setState(() { _busy = true; _status = '正在发布...'; });
    try {
      final a = _collect(draft: false);
      final pub = await widget.github.upsertArticle(repo, a);
      setState(() { _article = pub; _status = '已发布'; });
      await widget.onPublished(pub);
      if (mounted) showToast(context, '已发布到 ${repo.fullName}');
    } catch (e) {
      setState(() => _status = '发布失败');
      if (mounted) showToast(context, '发布失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _insertImage() async {
    setState(() { _busy = true; _status = '上传图片...'; });
    try {
      final bytes = await widget.imageService.pickImageBytes();
      if (bytes == null) { setState(() => _status = '已取消'); return; }
      final url = await widget.imageService.uploadToImageBed(bytes, widget.settings);
      _insertText(widget.imageService.markdownImage(url));
      setState(() => _status = '图片已插入');
    } catch (e) {
      if (mounted) showToast(context, '上传失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _aiAction(String action) async {
    setState(() { _busy = true; _status = 'AI 处理中...'; });
    try {
      String result;
      final text = _content.text;
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
          if (mounted) await showDialog(context: context, builder: (_) => AlertDialog(title: const Text('AI 摘要'), content: Text(result), actions: [
            TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: result)); Navigator.pop(context); }, child: const Text('复制')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ]));
          break;
        case 'outline':
          result = await widget.aiService.generateOutline(widget.settings, _title.text.isEmpty ? text : _title.text);
          _content.text = result;
          break;
        case 'code':
          final ctrl = TextEditingController();
          final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('AI 生成代码'), content: TextField(controller: ctrl, maxLines: 5, decoration: const InputDecoration(hintText: '描述需要的代码')), actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('生成')),
          ]));
          if (ok != true) break;
          result = await widget.aiService.generateCode(widget.settings, ctrl.text.trim().isEmpty ? '写一段示例代码' : ctrl.text.trim());
          _insertText('\n\n$result\n');
          break;
        case 'rewrite':
          final sel = _content.selection;
          if (!sel.isValid || sel.start == sel.end) { throw Exception('请先选中要改写的文字'); }
          final selected = text.substring(sel.start, sel.end);
          final instrCtrl = TextEditingController(text: '更简洁专业');
          final ok2 = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('AI 改写'), content: TextField(controller: instrCtrl), actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('改写')),
          ]));
          if (ok2 != true) break;
          result = await widget.aiService.rewriteSelection(widget.settings, selected, instrCtrl.text.trim());
          _wrapReplace(result);
          break;
      }
      setState(() => _status = 'AI 完成');
    } catch (e) {
      if (mounted) showToast(context, 'AI 失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _insertText(String t) {
    final sel = _content.selection;
    final txt = _content.text;
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _content.value = TextEditingValue(text: txt.replaceRange(s, e, t), selection: TextSelection.collapsed(offset: s + t.length));
    _contentFocus.requestFocus();
  }

  void _wrapReplace(String r) {
    final sel = _content.selection;
    final txt = _content.text;
    if (!sel.isValid) { _insertText(r); return; }
    _content.value = TextEditingValue(text: txt.replaceRange(sel.start, sel.end, r), selection: TextSelection.collapsed(offset: sel.start + r.length));
    _contentFocus.requestFocus();
  }

  void _wrap(String l, String r, {String p = ''}) {
    final sel = _content.selection;
    final txt = _content.text;
    if (!sel.isValid || sel.start == sel.end) {
      final body = p.isEmpty ? '' : p;
      final ins = '$l$body$r';
      final s = sel.isValid ? sel.start : txt.length;
      _content.value = TextEditingValue(text: txt.replaceRange(s, s, ins), selection: TextSelection.collapsed(offset: s + l.length + body.length));
      _contentFocus.requestFocus();
      return;
    }
    final sel2 = txt.substring(sel.start, sel.end);
    _content.value = TextEditingValue(text: txt.replaceRange(sel.start, sel.end, '$l$sel2$r'), selection: TextSelection.collapsed(offset: sel.start + l.length + sel2.length));
    _contentFocus.requestFocus();
  }

  void _insertHeading(int level) {
    final prefix = '${'#' * level} ';
    final txt = _content.text;
    final s = _content.selection.isValid ? _content.selection.start : txt.length;
    final lineStart = txt.lastIndexOf('\n', s - 1) + 1;
    _content.value = TextEditingValue(text: txt.replaceRange(lineStart, lineStart, prefix), selection: TextSelection.collapsed(offset: s + prefix.length));
    _contentFocus.requestFocus();
  }

  void _insertList(String marker) {
    final sel = _content.selection;
    if (sel.isValid && sel.start != sel.end) {
      final selected = _content.text.substring(sel.start, sel.end);
      _wrapReplace(selected.split('\n').map((l) => l.isEmpty ? l : '$marker$l').join('\n'));
      return;
    }
    _insertText('\n$marker');
  }

  void _insertCodeBlock() {
    final sel = _content.selection;
    final txt = _content.text;
    final selected = (sel.isValid && sel.start != sel.end) ? txt.substring(sel.start, sel.end) : '';
    final fence = '```\n$selected\n```\n';
    final s = sel.isValid ? sel.start : txt.length;
    final e = sel.isValid ? sel.end : txt.length;
    _content.value = TextEditingValue(text: txt.replaceRange(s, e, fence), selection: TextSelection.collapsed(offset: s + 4));
    _contentFocus.requestFocus();
  }

  void _applyTemplate(ArticleTemplate tpl) {
    final tags = tpl.defaultTags.join(', ');
    final cats = tpl.defaultCategories.join(', ');
    _tags.text = (_tags.text.isEmpty ? '' : '${_tags.text}, ')$tags';
    _categories.text = (_categories.text.isEmpty ? '' : '${_categories.text}, ')$cats;
    _content.text = tpl.content;
    _status = '已应用模板: ${tpl.name}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          _buildToolbar(colorScheme),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                if (widget.repos.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _repo?.id,
                    decoration: const InputDecoration(labelText: '目标仓库', prefixIcon: Icon(Icons.storage_outlined)),
                    items: widget.repos.map((r) => DropdownMenuItem(value: r.id, child: Text('${r.name} (${r.fullName})'))).toList(),
                    onChanged: (v) => setState(() => _repo = widget.repos.firstWhere((e) => e.id == v)),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: '标题', prefixIcon: Icon(Icons.title)),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: _tags, decoration: const InputDecoration(labelText: '标签 (逗号分隔)', prefixIcon: Icon(Icons.tag), isDense: true))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _categories, decoration: const InputDecoration(labelText: '分类', prefixIcon: Icon(Icons.folder_outlined), isDense: true))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: _cover, decoration: const InputDecoration(labelText: '封面图 URL', prefixIcon: Icon(Icons.image_outlined), isDense: true)),
                const SizedBox(height: 12),
                SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                  ToolChip(icon: Icons.format_bold, label: '粗体', onTap: () => _wrap('**', '**', p: '粗体')),
                  ToolChip(icon: Icons.format_italic, label: '斜体', onTap: () => _wrap('*', '*', p: '斜体')),
                  ToolChip(icon: Icons.code, label: '行内码', onTap: () => _wrap('`', '`', p: 'code')),
                  ToolChip(icon: Icons.code_off, label: '代码块', onTap: _insertCodeBlock),
                  ToolChip(icon: Icons.title, label: 'H1', onTap: () => _insertHeading(1)),
                  ToolChip(icon: Icons.title, label: 'H2', onTap: () => _insertHeading(2)),
                  ToolChip(icon: Icons.format_list_bulleted, label: '列表', onTap: () => _insertList('- ')),
                  ToolChip(icon: Icons.format_quote, label: '引用', onTap: () => _insertList('> ')),
                  ToolChip(icon: Icons.link, label: '链接', onTap: () => _wrap('[', '](https://)', p: '链接文字')),
                  ToolChip(icon: Icons.grid_on, label: '表格', onTap: () => _insertText('\n| 列1 | 列2 |\n| --- | --- |\n| 值1 | 值2 |\n')),
                  ToolChip(icon: Icons.image_outlined, label: '图床', onTap: _busy ? null : _insertImage),
                  ToolChip(icon: Icons.auto_awesome, label: 'AI润色', onTap: _busy ? null : () => _aiAction('polish'), color: Colors.purple),
                  ToolChip(icon: Icons.edit_note, label: 'AI续写', onTap: _busy ? null : () => _aiAction('continue'), color: Colors.purple),
                  ToolChip(icon: Icons.summarize_outlined, label: 'AI摘要', onTap: _busy ? null : () => _aiAction('summary'), color: Colors.purple),
                  ToolChip(icon: Icons.developer_mode, label: 'AI代码', onTap: _busy ? null : () => _aiAction('code'), color: Colors.purple),
                  ToolChip(icon: Icons.sync_alt, label: 'AI改写', onTap: _busy ? null : () => _aiAction('rewrite'), color: Colors.purple),
                ])),
                const SizedBox(height: 12),
                TextField(
                  controller: _content,
                  focusNode: _contentFocus,
                  minLines: 20, maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'Markdown 正文', alignLabelWithHint: true,
                    hintText: '支持 # 标题、**粗体**、代码块、列表...编辑完可存草稿或直接发布',
                  ),
                  style: const TextStyle(fontFamily: 'monospace', height: 1.6, fontSize: 14.5),
                ),
                if (_status != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_status!, style: TextStyle(color: colorScheme.primary)),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _saveLocal, icon: const Icon(Icons.drafts_outlined, size: 18), label: const Text('存草稿'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.icon(onPressed: _busy ? null : _publish, icon: const Icon(Icons.cloud_upload_outlined, size: 18), label: const Text('发布'))),
          ]),
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _showTemplateSheet(),
        tooltip: '使用模板',
        child: const Icon(Icons.file_copy_outlined),
      ),
    );
  }

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: cs.surface, border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.5)))),
      child: Row(children: [
        Icon(Icons.edit_note, color: cs.primary, size: 22),
        const SizedBox(width: 8),
        const Text('写文章', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const Spacer(),
        IconButton(tooltip: '预览', onPressed: _busy ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(
          appBar: AppBar(title: Text(_title.text.isEmpty ? '预览' : _title.text)),
          body: Markdown(data: _content.text.isEmpty ? '*暂无内容*' : _content.text, selectable: true),
        ))), icon: const Icon(Icons.visibility_outlined)),
      ]),
    );
  }

  void _showTemplateSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('选择模板', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          const Divider(height: 1),
          SizedBox(
            height: 300,
            child: ListView.builder(
              itemCount: widget.templates.length,
              itemBuilder: (_, i) {
                final t = widget.templates[i];
                return ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(t.name),
                  subtitle: Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () { Navigator.pop(ctx); _applyTemplate(t); },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
