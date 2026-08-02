import 'package:flutter/material.dart';
import '../core/tools/tool_entity.dart';

/// 技能编辑器页面
class SkillEditorScreen extends StatefulWidget {
  final ToolEntity? existing;

  const SkillEditorScreen({super.key, this.existing});

  @override
  State<SkillEditorScreen> createState() => _SkillEditorScreenState();
}

class _SkillEditorScreenState extends State<SkillEditorScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _contentCtrl;
  List<ToolParam> _params = [];
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.existing != null;
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    _contentCtrl = TextEditingController(text: widget.existing?.skillContent ?? '');
    if (widget.existing?.parameters != null) {
      _params = List.from(widget.existing!.parameters);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑技能' : '新建技能'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 名称
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '技能名称',
                hintText: '如: 代码审查助手',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 描述
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: '技能描述',
                hintText: '描述这个技能的功能和用途',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            // 参数
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '参数定义',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                TextButton.icon(
                  onPressed: _addParam,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加参数'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_params.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '暂无参数。点击「添加参数」定义技能所需的输入参数。',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ..._params.asMap().entries.map((entry) => _buildParamRow(entry.key, entry.value)),

            const SizedBox(height: 24),

            // 技能内容
            const Text(
              '技能内容 (System Prompt)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '定义此技能激活时注入到 AI 对话中的 System Prompt。当 AI 调用此技能时，这段内容将被注入。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentCtrl,
              decoration: const InputDecoration(
                hintText: '你是一个专业的代码审查助手...\n\n编写 System Prompt，指导 AI 的行为...',
                border: OutlineInputBorder(),
              ),
              maxLines: 12,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),

            const SizedBox(height: 24),

            // 提示
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '技能创建后会自动注册到所有 AI 会话的工具列表中。AI 在需要时可以通过 Function Calling 调用此技能。',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParamRow(int index, ToolParam param) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                param.name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  param.type,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (param.required)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('*', style: TextStyle(color: Colors.red, fontSize: 14)),
              ),
            const SizedBox(width: 4),
            Text(
              param.description.length > 15
                  ? '${param.description.substring(0, 15)}...'
                  : param.description,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => _removeParam(index),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  void _addParam() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String type = 'string';
    bool required = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('添加参数'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '参数名', hintText: '如: query'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: const [
                    DropdownMenuItem(value: 'string', child: Text('string')),
                    DropdownMenuItem(value: 'number', child: Text('number')),
                    DropdownMenuItem(value: 'boolean', child: Text('boolean')),
                    DropdownMenuItem(value: 'array', child: Text('array')),
                    DropdownMenuItem(value: 'object', child: Text('object')),
                  ],
                  onChanged: (v) => setDlg(() => type = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: '描述'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('必填'),
                  value: required,
                  onChanged: (v) => setDlg(() => required = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty) {
                  setState(() {
                    _params.add(ToolParam(
                      name: nameCtrl.text,
                      type: type,
                      description: descCtrl.text,
                      required: required,
                    ));
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  void _removeParam(int index) {
    setState(() => _params.removeAt(index));
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入技能名称')),
      );
      return;
    }

    final result = ToolEntity(
      id: widget.existing?.id ?? 'skill_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      type: ToolType.skill,
      parameters: _params,
      skillContent: _contentCtrl.text.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Navigator.pop(context, result);
  }
}