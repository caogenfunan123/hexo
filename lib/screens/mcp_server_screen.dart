import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/tools/mcp_server.dart';
import '../core/tools/tool_entity.dart';
import '../core/tools/tool_registry.dart';
import '../services/storage_service.dart';

/// MCP 外部服务器管理页面（对标 MonkeyCode add-mcp-server-dialog：name + url + headers）
class McpServerScreen extends StatefulWidget {
  const McpServerScreen({super.key});

  @override
  State<McpServerScreen> createState() => _McpServerScreenState();
}

class _McpServerScreenState extends State<McpServerScreen> {
  final _storage = StorageService();
  McpServerManager? _manager;
  List<McpServer> _servers = [];
  bool _loading = true;
  bool _syncing = false;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final root = await _storage.root;
    final manager = McpServerManager(root: root, registry: ToolRegistry());
    await manager.load();
    setState(() {
      _manager = manager;
      _servers = manager.servers;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    if (_manager == null) return;
    await _manager!.load();
    setState(() {
      _servers = _manager!.servers;
      _syncError = null;
    });
  }

  Future<void> _syncAll() async {
    if (_manager == null) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    final errors = await _manager!.syncAllTools();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      if (errors.isNotEmpty) {
        _syncError = errors.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('\n');
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          errors.isEmpty
              ? '已同步全部 MCP 工具'
              : '同步完成，${errors.length} 个服务器失败',
        ),
      ),
    );
  }

  void _showEditor([McpServer? server]) {
    final nameCtrl = TextEditingController(text: server?.name ?? '');
    final urlCtrl = TextEditingController(text: server?.url ?? '');
    final headersCtrl = TextEditingController(
      text: server != null && server.headers.isNotEmpty
          ? server.headers.entries
              .map((e) => '${e.key}: ${e.value}')
              .join('\n')
          : '',
    );
    final enableSwitch = server?.enabled ?? true;
    var enabled = enableSwitch;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(server == null ? '添加 MCP 服务器' : '编辑 MCP 服务器'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '例如：我的 MCP 服务',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: '服务器 URL',
                    hintText: 'https://example.com/mcp',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: headersCtrl,
                  decoration: const InputDecoration(
                    labelText: '认证头（每行一个 Key: Value）',
                    hintText: 'Authorization: Bearer xxx',
                  ),
                  maxLines: 3,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用'),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final url = urlCtrl.text.trim();
                if (name.isEmpty || url.isEmpty) return;
                final headers = <String, String>{};
                for (final line in headersCtrl.text.split('\n')) {
                  final idx = line.indexOf(':');
                  if (idx > 0) {
                    headers[line.substring(0, idx).trim()] =
                        line.substring(idx + 1).trim();
                  }
                }
                final newServer = McpServer(
                  id: server?.id ??
                      'mcp_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  url: url,
                  headers: headers,
                  enabled: enabled,
                );
                await _manager!.addServer(newServer);
                if (ctx.mounted) Navigator.pop(ctx);
                await _refresh();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(McpServer server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('删除 "${server.name}" 及其所有远端工具？'),
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
      await _manager!.removeServer(server.id);
      await _refresh();
    }
  }

  Future<void> _toggle(McpServer server, bool enabled) async {
    await _manager!.setEnabled(server.id, enabled);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP 服务器'),
        actions: [
          if (!_loading)
            IconButton(
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              tooltip: '同步远端工具',
              onPressed: _syncing ? null : _syncAll,
            ),
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '添加服务器',
              onPressed: () => _showEditor(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _servers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.dns_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('尚未配置 MCP 服务器',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('点击右上角添加外部 MCP 服务器\n保存后同步即可把远端工具加入工具库',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (_syncError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _syncError!,
                          style: const TextStyle(fontSize: 12, color: Colors.red),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    ..._servers.map((s) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: cs.primary.withOpacity(0.1),
                              child: Icon(Icons.dns, color: cs.primary, size: 20),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(s.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (s.enabled ? Colors.green : Colors.grey)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    s.enabled ? '已启用' : '已停用',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: s.enabled ? Colors.green : Colors.grey,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              s.url,
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    s.enabled ? Icons.visibility : Icons.visibility_off,
                                    size: 18,
                                    color: s.enabled ? cs.primary : cs.outline,
                                  ),
                                  tooltip: s.enabled ? '停用' : '启用',
                                  onPressed: () => _toggle(s, !s.enabled),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: () => _showEditor(s),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  onPressed: () => _remove(s),
                                ),
                              ],
                            ),
                          ),
                        )),
                    const SizedBox(height: 8),
                    Text(
                      '通过 JSON-RPC (tools/list / tools/call) 与远端 MCP 服务器交互。'
                      '同步后工具会出现在工具库中，可在聊天中调用。',
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ],
                ),
    );
  }
}
