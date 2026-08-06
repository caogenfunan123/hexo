import 'package:flutter/material.dart';
import '../core/tools/skill_manager.dart';
import '../core/tools/tool_entity.dart';

/// 工具库管理页面
class ToolLibraryScreen extends StatefulWidget {
  final SkillManager skillManager;

  const ToolLibraryScreen({super.key, required this.skillManager});

  @override
  State<ToolLibraryScreen> createState() => _ToolLibraryScreenState();
}class _ToolLibraryScreenState extends State<ToolLibraryScreen> {
  List<ToolEntity> _tools = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _tools = widget.skillManager.allTools;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: true,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('工具库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建技能',
            onPressed: () => _showSkillEditor(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tools.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.build_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('工具库为空', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('AI 可以自动创建 MCP/Skill 工具\n或点击右上角手动创建',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _tools.length,
                  itemBuilder: (ctx, i) {
                    final tool = _tools[i];
                    return _buildToolCard(tool, cs);
                  },
                ),
      ),
    );
  }

  Widget _buildToolCard(ToolEntity tool, ColorScheme cs) {
    final icon = _typeIcon(tool.type);
    final color = _typeColor(tool.type, cs);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Row(
          children: [
            Flexible(child: Text(tool.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            _sourceChip(tool.source),
            if (tool.scope == ToolScope.sitePrivate) ...[
              const SizedBox(width: 4),
              _scopeChip('站点私有'),
            ],
            if (tool.riskLevel != null && tool.riskLevel != 'low') ...[
              const SizedBox(width: 4),
              _scopeChip(tool.riskLevel!, color: tool.riskLevel == 'high' ? Colors.red : Colors.orange),
            ],
          ],
        ),
        subtitle: Text(tool.description, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _typeChip(tool.type),
            if (tool.type != ToolType.builtin)
              IconButton(
                icon: Icon(
                  tool.enabled ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                  color: tool.enabled ? cs.primary : cs.outline,
                ),
                tooltip: tool.enabled ? '停用该工具' : '启用该工具',
                onPressed: () => _toggleEnabled(tool),
              ),
            if (tool.type == ToolType.skill)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _deleteSkill(tool),
              ),
            if (tool.type == ToolType.mcp)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _deleteMcp(tool),
              ),
          ],
        ),
        onTap: () => _showToolDetail(tool),
      ),
    );
  }

  Widget _sourceChip(ToolSource source) {
    final isAi = source == ToolSource.ai;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isAi ? Colors.purple : Colors.blueGrey).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isAi ? 'AI 生成' : '手动',
        style: TextStyle(fontSize: 10, color: isAi ? Colors.purple : Colors.blueGrey, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _scopeChip(String label, {Color? color}) {
    final c = color ?? Colors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _toggleEnabled(ToolEntity tool) async {
    if (tool.type == ToolType.skill) {
      await widget.skillManager.updateSkill(tool.id, enabled: !tool.enabled);
    } else if (tool.type == ToolType.mcp) {
      await widget.skillManager.updateMcpTool(tool.id, enabled: !tool.enabled);
    }
    _refresh();
  }

  Future<void> _deleteMcp(ToolEntity tool) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 MCP 工具'),
        content: Text('确定删除 "${tool.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.skillManager.deleteMcpTool(tool.id);
      _refresh();
    }
  }

  IconData _typeIcon(ToolType type) {
    switch (type) {
      case ToolType.builtin: return Icons.bolt;
      case ToolType.skill: return Icons.auto_fix_high;
      case ToolType.mcp: return Icons.api;
    }
  }

  Color _typeColor(ToolType type, ColorScheme cs) {
    switch (type) {
      case ToolType.builtin: return Colors.blue;
      case ToolType.skill: return Colors.orange;
      case ToolType.mcp: return Colors.green;
    }
  }

  Widget _typeChip(ToolType type) {
    final label = switch (type) {
      ToolType.builtin => '内置',
      ToolType.skill => '技能',
      ToolType.mcp => 'MCP',
    };
    final color = switch (type) {
      ToolType.builtin => Colors.blue,
      ToolType.skill => Colors.orange,
      ToolType.mcp => Colors.green,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  void _showToolDetail(ToolEntity tool) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tool.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('类型: ${tool.type.name}'),
              const SizedBox(height: 4),
              Text('来源: ${tool.source == ToolSource.ai ? "AI 会话生成" : "用户手动创建"}'),
              const SizedBox(height: 4),
              Text('作用域: ${tool.scope == ToolScope.sitePrivate ? "站点私有${tool.siteId != null ? " (${tool.siteId})" : ""}" : "全局公用"}'),
              if (tool.riskLevel != null) ...[
                const SizedBox(height: 4),
                Text('风险等级: ${tool.riskLevel}'),
              ],
              const SizedBox(height: 8),
              Text('描述: ${tool.description}'),
              if (tool.parameters.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('参数:', style: TextStyle(fontWeight: FontWeight.w600)),
                ...tool.parameters.map((p) => Text('  - ${p.name} (${p.type}${p.required ? ', 必填' : ''}): ${p.description}')),
              ],
              if (tool.skillContent != null && tool.skillContent!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('内容:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(tool.skillContent!,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _deleteSkill(ToolEntity tool) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除技能'),
        content: Text('确定删除 "${tool.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.skillManager.deleteSkill(tool.id);
      _refresh();
    }
  }

  void _showSkillEditor() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建技能'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '技能名称', hintText: '例如：主题一键迁移'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: '描述', hintText: '技能功能简述'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(
                  labelText: 'Skill JSON 内容',
                  hintText: '粘贴 AI 生成的 Skill JSON',
                ),
                maxLines: 6,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await widget.skillManager.createSkill(
                name: name,
                description: descCtrl.text.trim(),
                content: contentCtrl.text.trim(),
              );
              Navigator.pop(ctx);
              _refresh();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}