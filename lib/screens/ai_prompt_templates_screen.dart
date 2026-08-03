import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AiPromptTemplate {
  final String id;
  final String name;
  final String category;
  final String promptContent;
  final bool isBuiltin;
  final DateTime createdAt;

  const AiPromptTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.promptContent,
    required this.isBuiltin,
    required this.createdAt,
  });

  AiPromptTemplate copyWith({
    String? id,
    String? name,
    String? category,
    String? promptContent,
    bool? isBuiltin,
    DateTime? createdAt,
  }) {
    return AiPromptTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      promptContent: promptContent ?? this.promptContent,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'promptContent': promptContent,
      'isBuiltin': isBuiltin,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AiPromptTemplate.fromJson(Map<String, dynamic> json) {
    return AiPromptTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      promptContent: json['promptContent'] as String,
      isBuiltin: json['isBuiltin'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  String exportString() {
    return jsonEncode(toJson());
  }

  factory AiPromptTemplate.importFrom(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return AiPromptTemplate.fromJson(map);
  }
}

final List<AiPromptTemplate> _builtinPresets = [
  AiPromptTemplate(
    id: 'builtin_polish',
    name: '润色优化',
    category: 'writing',
    promptContent: '请润色以下文字，使其更加流畅专业，保持原意不变：\n{{text}}',
    isBuiltin: true,
    createdAt: _epoch,
  ),
  AiPromptTemplate(
    id: 'builtin_summary',
    name: '摘要生成',
    category: 'summary',
    promptContent: '请为以下文章生成一段简洁的摘要（200字以内）：\n{{text}}',
    isBuiltin: true,
    createdAt: _epoch,
  ),
  AiPromptTemplate(
    id: 'builtin_translate',
    name: '翻译为英文',
    category: 'formatting',
    promptContent: '请将以下中文翻译为地道的英文：\n{{text}}',
    isBuiltin: true,
    createdAt: _epoch,
  ),
  AiPromptTemplate(
    id: 'builtin_expand',
    name: '扩写',
    category: 'writing',
    promptContent: '请对以下内容进行扩写，增加细节和例子：\n{{text}}',
    isBuiltin: true,
    createdAt: _epoch,
  ),
  AiPromptTemplate(
    id: 'builtin_condense',
    name: '缩写',
    category: 'summary',
    promptContent: '请对以下内容进行精简，保留核心信息：\n{{text}}',
    isBuiltin: true,
    createdAt: _epoch,
  ),
  AiPromptTemplate(
    id: 'builtin_tone',
    name: '修改语气',
    category: 'formatting',
    promptContent: '请将以下文字改为更正式/更友好的语气：\n{{text}}',
    isBuiltin: true,
    createdAt: _epoch,
  ),
];

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

class AiPromptTemplatesScreen extends StatefulWidget {
  final void Function(String promptContent) onUseTemplate;

  const AiPromptTemplatesScreen({
    super.key,
    required this.onUseTemplate,
  });

  @override
  State<AiPromptTemplatesScreen> createState() => _AiPromptTemplatesScreenState();
}

class _AiPromptTemplatesScreenState extends State<AiPromptTemplatesScreen> {
  List<AiPromptTemplate> _templates = [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _templates = List.of(_builtinPresets);
  }

  List<AiPromptTemplate> get _filtered {
    if (_filter == 'all') return _templates;
    return _templates.where((t) => t.category == _filter).toList();
  }

  Map<String, String> get _categoryLabels => const {
        'all': '全部',
        'writing': '写作',
        'summary': '摘要',
        'formatting': '格式',
        'custom': '自定义',
      };

  Future<void> _createTemplate() async {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String category = 'custom';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('新建提示词模板'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '模板名称',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(
                    labelText: '分类',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'writing', child: Text('写作')),
                    DropdownMenuItem(value: 'summary', child: Text('摘要')),
                    DropdownMenuItem(value: 'formatting', child: Text('格式')),
                    DropdownMenuItem(value: 'custom', child: Text('自定义')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDlg(() => category = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: '提示词内容',
                    hintText: '使用 {{text}} 作为选中文本的占位符',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || nameCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) return;

    final now = DateTime.now();
    final t = AiPromptTemplate(
      id: 'custom_${now.millisecondsSinceEpoch}',
      name: nameCtrl.text.trim(),
      category: category,
      promptContent: contentCtrl.text.trim(),
      isBuiltin: false,
      createdAt: now,
    );
    setState(() => _templates.add(t));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已创建模板: ${t.name}')),
      );
    }
  }

  Future<void> _editTemplate(AiPromptTemplate t) async {
    if (t.isBuiltin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内置模板不可编辑，请先复制为自定义模板')),
      );
      return;
    }

    final nameCtrl = TextEditingController(text: t.name);
    final contentCtrl = TextEditingController(text: t.promptContent);
    String category = t.category;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('编辑提示词模板'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '模板名称',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(
                    labelText: '分类',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'writing', child: Text('写作')),
                    DropdownMenuItem(value: 'summary', child: Text('摘要')),
                    DropdownMenuItem(value: 'formatting', child: Text('格式')),
                    DropdownMenuItem(value: 'custom', child: Text('自定义')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDlg(() => category = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: '提示词内容',
                    hintText: '使用 {{text}} 作为选中文本的占位符',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || nameCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) return;

    final idx = _templates.indexWhere((e) => e.id == t.id);
    if (idx >= 0) {
      setState(() {
        _templates[idx] = _templates[idx].copyWith(
          name: nameCtrl.text.trim(),
          category: category,
          promptContent: contentCtrl.text.trim(),
        );
      });
    }
  }

  Future<void> _duplicate(AiPromptTemplate t) async {
    final now = DateTime.now();
    final copy = t.copyWith(
      id: 'custom_${now.millisecondsSinceEpoch}',
      name: '${t.name} (副本)',
      isBuiltin: false,
      createdAt: now,
    );
    setState(() => _templates.add(copy));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制: ${copy.name}')),
      );
    }
  }

  Future<void> _delete(AiPromptTemplate t) async {
    if (t.isBuiltin) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('确认删除「${t.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _templates.removeWhere((e) => e.id == t.id));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除: ${t.name}')),
      );
    }
  }

  void _useTemplate(AiPromptTemplate t) {
    widget.onUseTemplate(t.promptContent);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已应用模板: ${t.name}')),
      );
    }
  }

  Future<void> _exportTemplate(AiPromptTemplate t) async {
    final json = t.exportString();
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模板已复制到剪贴板')),
      );
    }
  }

  Future<void> _importTemplate() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空')),
        );
      }
      return;
    }
    try {
      final t = AiPromptTemplate.importFrom(data.text!);
      final exists = _templates.any((e) => e.id == t.id);
      final template = exists ? t.copyWith(id: 'custom_${DateTime.now().millisecondsSinceEpoch}') : t;
      setState(() => _templates.add(template));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入模板: ${template.name}')),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 提示词模板'),
        actions: [
          IconButton(
            tooltip: '导入模板',
            onPressed: _importTemplate,
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: '新建模板',
            onPressed: _createTemplate,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categoryLabels.entries.map((e) {
                  final active = _filter == e.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(e.value),
                      selected: active,
                      onSelected: (_) => setState(() => _filter = e.key),
                      backgroundColor: Colors.white,
                      selectedColor: cs.primaryContainer,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(child: Text('暂无模板'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) => _templateCard(_filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _templateCard(AiPromptTemplate t) {
    final cs = Theme.of(context).colorScheme;

    final Color categoryColor;
    final String categoryLabel;
    switch (t.category) {
      case 'writing':
        categoryColor = const Color(0xFF0EA5E9);
        categoryLabel = '写作';
        break;
      case 'summary':
        categoryColor = const Color(0xFF10B981);
        categoryLabel = '摘要';
        break;
      case 'formatting':
        categoryColor = const Color(0xFFF59E0B);
        categoryLabel = '格式';
        break;
      case 'custom':
        categoryColor = const Color(0xFF8B5CF6);
        categoryLabel = '自定义';
        break;
      default:
        categoryColor = Colors.grey;
        categoryLabel = t.category;
    }

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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: categoryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    categoryLabel,
                    style: TextStyle(fontSize: 11, color: categoryColor),
                  ),
                ),
                const SizedBox(width: 8),
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
                  )
                else
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
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                IconButton(
                  tooltip: '使用此模板',
                  onPressed: () => _useTemplate(t),
                  icon: Icon(Icons.play_arrow_rounded, color: categoryColor),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
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
                t.promptContent.length > 200
                    ? '${t.promptContent.substring(0, 200)}...'
                    : t.promptContent,
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
                  onPressed: () => _exportTemplate(t),
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
                if (!t.isBuiltin) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '编辑',
                    onPressed: () => _editTemplate(t),
                    icon: const Icon(Icons.edit, size: 18),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
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