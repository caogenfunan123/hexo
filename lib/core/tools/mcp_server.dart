/// MCP 外部服务器接入：服务器管理（名称 + URL + 认证头）、
/// 运行时通过 JSON-RPC (tools/list / tools/call) 拉取远端工具并注册进 ToolRegistry。
///
/// 对标 MonkeyCode backend/biz/mcphub：外部 MCP 服务器管理 + 运行时 gateway + registry。

import 'dart:convert';
import 'dart:io';

import 'tool_entity.dart';
import 'tool_registry.dart';

/// MCP 服务器配置（对标 MonkeyCode add-mcp-server-dialog：name + url + headers）
class McpServer {
  final String id;
  final String name;
  final String url;
  final Map<String, String> headers; // 认证头等，如 {Authorization: Bearer xxx}
  final bool enabled;

  const McpServer({
    required this.id,
    required this.name,
    required this.url,
    this.headers = const {},
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'headers': headers,
        'enabled': enabled,
      };

  factory McpServer.fromJson(Map<String, dynamic> j) => McpServer(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
        headers: (j['headers'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
        enabled: j['enabled'] != false,
      );

  McpServer copyWith({
    String? name,
    String? url,
    Map<String, String>? headers,
    bool? enabled,
  }) =>
      McpServer(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        headers: headers ?? this.headers,
        enabled: enabled ?? this.enabled,
      );
}

/// 远端工具清单条目（tools/list 返回）
class McpRemoteTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const McpRemoteTool({
    required this.name,
    required this.description,
    this.inputSchema = const {},
  });

  /// 转为本地 ToolEntity（endpoint 存服务器 URL，rawDefinition 存远端工具名）
  ToolEntity toToolEntity(McpServer server) {
    bool isRequired(String key) {
      final req = inputSchema['required'];
      if (req is List) return req.contains(key);
      return false;
    }

    final params = <ToolParam>[];
    final props = inputSchema['properties'];
    if (props is Map) {
      props.forEach((key, value) {
        if (value is Map) {
          final type = value['type']?.toString() ?? 'string';
          final desc = value['description']?.toString() ?? '';
          params.add(ToolParam(
            name: key.toString(),
            type: type == 'integer' ? 'number' : type,
            description: desc,
            required: isRequired(key.toString()),
          ));
        }
      });
    }
    final raw = jsonEncode({
      'remote_name': name,
      'server_id': server.id,
      'server_url': server.url,
      'headers': server.headers,
    });
    return ToolEntity(
      id: name,
      name: name,
      description: description,
      type: ToolType.mcp,
      parameters: params,
      endpoint: server.url,
      rawDefinition: raw,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      enabled: server.enabled,
      scope: ToolScope.global,
      source: ToolSource.user,
      riskLevel: 'middle',
    );
  }
}

/// MCP 服务器管理：持久化 + 远端工具拉取 + 注册
class McpServerManager {
  static const _serversFile = 'mcp_servers.json';

  final Directory _root;
  final ToolRegistry _registry;

  List<McpServer> _servers = [];

  McpServerManager({
    required Directory root,
    ToolRegistry? registry,
  })  : _root = root,
        _registry = registry ?? ToolRegistry();

  List<McpServer> get servers => List.unmodifiable(_servers);

  Future<void> load() async {
    try {
      final f = File('${_root.path}/$_serversFile');
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString());
      if (data is List) {
        _servers = data
            .whereType<Map>()
            .map((e) => McpServer.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final f = File('${_root.path}/$_serversFile');
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        _servers.map((s) => s.toJson()).toList(),
      ),
    );
  }

  Future<void> addServer(McpServer server) async {
    _servers = [
      ..._servers.where((s) => s.id != server.id),
      server,
    ];
    await _save();
  }

  Future<void> updateServer(McpServer server) => addServer(server);

  Future<void> removeServer(String id) async {
    _servers = _servers.where((s) => s.id != id).toList();
    await _save();
    _unregisterServerTools(id);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    _servers = _servers
        .map((s) => s.id == id ? s.copyWith(enabled: enabled) : s)
        .toList();
    await _save();
    if (!enabled) _unregisterServerTools(id);
  }

  /// 拉取所有启用服务器的远端工具并注册进 ToolRegistry
  Future<Map<String, String>> syncAllTools() async {
    final errors = <String, String>{};
    _unregisterAllRemoteTools();
    for (final server in _servers.where((s) => s.enabled)) {
      try {
        final tools = await _listTools(server);
        for (final t in tools) {
          _registry.registerMcp(t.toToolEntity(server));
        }
      } catch (e) {
        errors[server.name] = '$e';
      }
    }
    return errors;
  }

  /// JSON-RPC tools/list
  Future<List<McpRemoteTool>> _listTools(McpServer server) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(server.url);
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json');
      server.headers.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'tools/list',
        'params': {},
        'id': DateTime.now().millisecondsSinceEpoch,
      }));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}: $text');
      }
      final data = jsonDecode(text);
      if (data is! Map) throw Exception('响应格式异常');
      final error = data['error'];
      if (error != null) {
        throw Exception('JSON-RPC 错误: $error');
      }
      final result = data['result'];
      if (result is! Map) throw Exception('无 result');
      final tools = result['tools'];
      if (tools is! List) throw Exception('无 tools');
      return tools.whereType<Map>().map((t) {
        final schema = t['inputSchema'] is Map
            ? Map<String, dynamic>.from(t['inputSchema'] as Map)
            : <String, dynamic>{};
        return McpRemoteTool(
          name: t['name']?.toString() ?? '',
          description: t['description']?.toString() ?? '',
          inputSchema: schema,
        );
      }).toList();
    } finally {
      client.close(force: true);
    }
  }

  void _unregisterAllRemoteTools() {
    for (final server in _servers) {
      _unregisterServerTools(server.id);
    }
  }

  void _unregisterServerTools(String serverId) {
    final ids = _registry.allTools
        .where((t) =>
            t.type == ToolType.mcp &&
            t.endpoint != null &&
            t.rawDefinition != null)
        .where((t) {
          try {
            final raw = jsonDecode(t.rawDefinition!) as Map<String, dynamic>;
            return raw['server_id']?.toString() == serverId;
          } catch (_) {
            return false;
          }
        })
        .map((t) => t.id)
        .toList();
    for (final id in ids) {
      _registry.unregister(id);
    }
  }
}
