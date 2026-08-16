/// MCP 外部服务器接入：服务器管理（名称 + URL + 认证头 + 传输类型 + stdio 命令）、
/// 运行时通过 JSON-RPC (tools/list / tools/call) 拉取远端工具并注册进 ToolRegistry。
///
/// 对标 MonkeyCode backend/biz/mcphub：外部 MCP 服务器管理 + 运行时 gateway + registry。

import 'dart:convert';
import 'dart:io';

import 'mcp_transport.dart';
import 'tool_entity.dart';
import 'tool_registry.dart';

/// MCP 服务器配置（对标 MonkeyCode add-mcp-server-dialog：name + url + headers + transport）
class McpServer {
  final String id;
  final String name;
  final String url;
  final Map<String, String> headers; // 认证头等，如 {Authorization: Bearer xxx}
  final bool enabled;
  final McpTransport transport; // http / sse / stdio
  final String command; // stdio 启动命令（如 npx -y @modelcontextprotocol/server-xxx）
  final List<String> args; // stdio 启动参数
  final String? cwd; // stdio 工作目录
  final Map<String, String> env; // stdio 环境变量

  const McpServer({
    required this.id,
    required this.name,
    required this.url,
    this.headers = const {},
    this.enabled = true,
    this.transport = McpTransport.http,
    this.command = '',
    this.args = const [],
    this.cwd,
    this.env = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'headers': headers,
        'enabled': enabled,
        'transport': transport.toString(),
        'command': command,
        'args': args,
        'cwd': cwd,
        'env': env,
      };

  factory McpServer.fromJson(Map<String, dynamic> j) => McpServer(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
        headers: (j['headers'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
        enabled: j['enabled'] != false,
        transport: McpTransport.fromString(j['transport']?.toString()),
        command: j['command']?.toString() ?? '',
        args: (j['args'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        cwd: j['cwd']?.toString(),
        env: (j['env'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
      );

  McpServer copyWith({
    String? name,
    String? url,
    Map<String, String>? headers,
    bool? enabled,
    McpTransport? transport,
    String? command,
    List<String>? args,
    Object? cwd = _sentinel,
    Map<String, String>? env,
  }) =>
      McpServer(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        headers: headers ?? this.headers,
        enabled: enabled ?? this.enabled,
        transport: transport ?? this.transport,
        command: command ?? this.command,
        args: args ?? this.args,
        cwd: identical(cwd, _sentinel) ? this.cwd : cwd as String?,
        env: env ?? this.env,
      );

  /// 转换为传输配置快照（供 ToolExecutor / 连接池使用）
  McpTransportConfig toTransportConfig() => McpTransportConfig(
        transport: transport,
        url: url,
        headers: headers,
        command: command,
        args: args,
        cwd: cwd,
        env: env,
      );

  static const Object _sentinel = Object();
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

  /// 转为本地 ToolEntity（endpoint 存服务器 URL，rawDefinition 存远端工具名 + 完整传输配置）
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
    // rawDefinition 同时携带远端工具名、服务器 ID、URL、认证头与完整传输配置，
    // 供 ToolExecutor 还原连接（含 stdio 命令 / sse 传输）。
    final raw = jsonEncode({
      'remote_name': name,
      'server_id': server.id,
      'server_url': server.url,
      'headers': server.headers,
      'transport': server.transport.toString(),
      'command': server.command,
      'args': server.args,
      'cwd': server.cwd,
      'env': server.env,
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
    // 服务器配置变更后丢弃旧连接，下次调用重新握手
    await McpClientPool.instance.close(server.id);
    await _save();
  }

  Future<void> updateServer(McpServer server) => addServer(server);

  Future<void> removeServer(String id) async {
    _servers = _servers.where((s) => s.id != id).toList();
    await _save();
    await McpClientPool.instance.close(id);
    _unregisterServerTools(id);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    _servers = _servers
        .map((s) => s.id == id ? s.copyWith(enabled: enabled) : s)
        .toList();
    await _save();
    if (!enabled) {
      await McpClientPool.instance.close(id);
      _unregisterServerTools(id);
    }
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

  /// JSON-RPC tools/list（按传输类型经连接池调用，共享握手/进程）
  Future<List<McpRemoteTool>> _listTools(McpServer server) async {
    final client = McpClientPool.instance.clientFor(
      server.id,
      server.toTransportConfig(),
    );
    try {
      final result = await client.call('tools/list', const {});
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
      // 同步工具列表后不释放连接，后续 tools/call 复用同一握手/进程
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
