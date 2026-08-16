/// MCP 传输层客户端：统一封装三种 MCP transport（http / sse / stdio）
/// 的 JSON-RPC 请求/响应，并处理协议握手（initialize / notifications/initialized /
/// session 复用）与 stdio 子进程生命周期。
///
/// - http：一次请求一次 POST（MCP Streamable HTTP 的简化形态），支持初始化握手。
/// - sse：POST + 长连接 SSE 流读取，服务端推送 notifications / 事件。
/// - stdio：启动本地子进程（如 npx -y @modelcontextprotocol/server-xxx），
///   通过 stdin/stdout 做 JSON-RPC，支持进程保活与退出重建。
///
/// 连接按 (server.id) 缓存复用，ToolExecutor 与 McpServerManager 共享同一连接池。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// MCP 传输类型
enum McpTransport {
  /// 一次请求一次 HTTP POST（兼容简化 JSON-RPC 服务器，也支持完整握手）
  http,

  /// POST + SSE 流式响应（支持服务端推送）
  sse,

  /// 本地子进程 stdin/stdout（仅桌面端可用）
  stdio;

  static McpTransport fromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'sse':
        return McpTransport.sse;
      case 'stdio':
        return McpTransport.stdio;
      default:
        return McpTransport.http;
    }
  }

  @override
  String toString() => switch (this) {
        McpTransport.http => 'http',
        McpTransport.sse => 'sse',
        McpTransport.stdio => 'stdio',
      };
}

/// 传输配置快照：从 McpServer / ToolEntity.rawDefinition 还原传输所需参数。
class McpTransportConfig {
  final McpTransport transport;
  final String url; // http/sse 端点
  final Map<String, String> headers;
  final String command; // stdio 启动命令
  final List<String> args;
  final String? cwd;
  final Map<String, String> env;

  const McpTransportConfig({
    this.transport = McpTransport.http,
    this.url = '',
    this.headers = const {},
    this.command = '',
    this.args = const [],
    this.cwd,
    this.env = const {},
  });

  Map<String, dynamic> toJson() => {
        'transport': transport.toString(),
        'url': url,
        'headers': headers,
        'command': command,
        'args': args,
        'cwd': cwd,
        'env': env,
      };

  factory McpTransportConfig.fromJson(Map<String, dynamic> j) =>
      McpTransportConfig(
        transport: McpTransport.fromString(j['transport']?.toString()),
        url: j['url']?.toString() ?? '',
        headers: (j['headers'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
        command: j['command']?.toString() ?? '',
        args: (j['args'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        cwd: j['cwd']?.toString(),
        env: (j['env'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
      );
}

/// JSON-RPC 请求/响应封装
class _RpcMessage {
  final String? jsonrpc;
  final String? method;
  final dynamic params;
  final dynamic id;
  final dynamic result;
  final dynamic error;

  const _RpcMessage({
    this.jsonrpc,
    this.method,
    this.params,
    this.id,
    this.result,
    this.error,
  });

  factory _RpcMessage.fromJson(Map<String, dynamic> j) => _RpcMessage(
        jsonrpc: j['jsonrpc']?.toString(),
        method: j['method']?.toString(),
        params: j['params'],
        id: j['id'],
        result: j['result'],
        error: j['error'],
      );

  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc ?? '2.0',
        if (method != null) 'method': method,
        if (params != null) 'params': params,
        if (id != null) 'id': id,
      };

  bool get isNotification => id == null;

  static Map<String, dynamic> request(
    String method,
    Map<String, dynamic> params,
    dynamic id,
  ) =>
      {'jsonrpc': '2.0', 'method': method, 'params': params, 'id': id};
}

/// MCP 传输客户端：单个服务器的 JSON-RPC 通信封装。
/// 连接按 serverId 在 [McpClientPool] 中缓存，close 后从池中移除。
class McpTransportClient {
  final String serverId;
  final McpTransportConfig config;

  McpTransportClient(this.serverId, this.config);

  final Map<String, dynamic> _pending = {}; // id -> Completer
  Process? _process;
  StreamSubscription<String>? _processOutSub;
  StreamSubscription<String>? _processErrSub;
  int _requestId = 0;
  bool _closed = false;
  bool _initialized = false;
  String? _sessionId;
  final List<_RpcMessage> _notificationQueue = [];

  bool get isClosed => _closed;

  Duration _timeout = const Duration(seconds: 60);

  /// 覆盖单次请求超时（默认 60s）
  void setTimeout(Duration d) => _timeout = d;

  /// 是否支持 stdio 传输（仅桌面端）
  static bool get stdioSupported =>
      !kIsWeb && !Platform.isAndroid && !Platform.isIOS;

  /// 可用的 JSON-RPC 调用：自动初始化握手 + 按传输分发
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (_closed) throw StateError('MCP 连接已关闭');
    await _ensureInitialized();
    final id = (_requestId++).toString();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final body = _RpcMessage.request(method, params, id);
    try {
      switch (config.transport) {
        case McpTransport.http:
          await _sendHttp(body);
          break;
        case McpTransport.sse:
          await _sendSse(body);
          break;
        case McpTransport.stdio:
          _sendStdio(body);
          break;
      }
      return await completer.future.timeout(_timeout);
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> close() async {
    _closed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('MCP 连接已关闭'));
      }
    }
    _pending.clear();
    final p = _process;
    _process = null;
    await _processOutSub?.cancel();
    await _processErrSub?.cancel();
    _processOutSub = null;
    _processErrSub = null;
    if (p != null) {
      try {
        p.kill();
      } catch (_) {}
    }
  }

  // ── 初始化握手 ──

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (config.transport == McpTransport.stdio) {
      await _ensureProcess();
    }
    try {
      // 握手使用短超时：不响应 initialize 的简化服务器不阻塞调用
      final result = await _rawRequest('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'hexo-app', 'version': '1.0.4'},
      }, timeout: const Duration(seconds: 8));
      final serverInfo = result['serverInfo'];
      if (serverInfo is Map && serverInfo['name'] != null) {
        // 服务器要求 session 时，后续请求带上 session id
        _sessionId = result['sessionId']?.toString();
      }
      // 发送 initialized 通知（部分服务器依赖它开始就绪）
      try {
        _notify('notifications/initialized');
      } catch (_) {
        // 简化服务器可能不支持通知，忽略
      }
    } catch (_) {
      // 简化服务器不响应 initialize 时降级为无握手直调：
      // 不设 sessionId，直接执行后续 tools/list / tools/call。
    }
    _initialized = true;
  }

  void _notify(String method, [Map<String, dynamic> params = const {}]) {
    final body = {'jsonrpc': '2.0', 'method': method, if (params.isNotEmpty) 'params': params};
    switch (config.transport) {
      case McpTransport.http:
        _sendHttpFireAndForget(body);
        break;
      case McpTransport.sse:
        _sendHttpFireAndForget(body);
        break;
      case McpTransport.stdio:
        _sendStdioRaw(body);
        break;
    }
  }

  Future<Map<String, dynamic>> _rawRequest(
    String method,
    Map<String, dynamic> params, {
    Duration? timeout,
  }) async {
    final id = (_requestId++).toString();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final body = _RpcMessage.request(method, params, id);
    try {
      switch (config.transport) {
        case McpTransport.http:
          await _sendHttp(body);
          break;
        case McpTransport.sse:
          await _sendSse(body);
          break;
        case McpTransport.stdio:
          _sendStdio(body);
          break;
      }
      return await completer.future.timeout(timeout ?? _timeout);
    } finally {
      _pending.remove(id);
    }
  }

  // ── http 传输 ──

  HttpClient _newClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  Future<void> _sendHttp(Map<String, dynamic> body) async {
    final client = _newClient();
    try {
      final uri = Uri.parse(config.url);
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json, text/event-stream');
      config.headers.forEach((k, v) => req.headers.set(k, v));
      if (_sessionId != null) {
        req.headers.set('Mcp-Session-Id', _sessionId!);
      }
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 30));
      final text =
          await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 60));
      _handleResponse(text, res.statusCode);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _sendHttpFireAndForget(Map<String, dynamic> body) async {
    try {
      await _sendHttp(body);
    } catch (_) {
      // 通知类消息失败可忽略
    }
  }

  // ── sse 传输 ──

  Future<void> _sendSse(Map<String, dynamic> body) async {
    final client = _newClient();
    try {
      final uri = Uri.parse(config.url);
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json, text/event-stream');
      config.headers.forEach((k, v) => req.headers.set(k, v));
      if (_sessionId != null) {
        req.headers.set('Mcp-Session-Id', _sessionId!);
      }
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 30));

      // 响应为事件流时解析 SSE；否则按普通 JSON 处理
      final contentType = res.headers.contentType?.mimeType ?? '';
      if (contentType.contains('text/event-stream') ||
          contentType.contains('application/json')) {
        final text =
            await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 60));
        _handleResponse(text, res.statusCode, sse: true);
      } else {
        // 无 SSE 的服务器：按普通 JSON 响应
        final text =
            await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 60));
        _handleResponse(text, res.statusCode);
      }
    } finally {
      client.close(force: true);
    }
  }

  void _handleResponse(String text, int statusCode, {bool sse = false}) {
    if (statusCode < 200 || statusCode >= 300) {
      throw HttpException('MCP HTTP $statusCode: $text', uri: Uri.parse(config.url));
    }
    if (sse) {
      // 解析 SSE 事件流
      final events = _parseSse(text);
      for (final data in events) {
        _dispatchMessage(data);
      }
      return;
    }
    final decoded = jsonDecode(text);
    _dispatchMessage(decoded);
  }

  List<String> _parseSse(String text) {
    final events = <String>[];
    final lines = text.split('\n');
    StringBuffer? current;
    for (final line in lines) {
      if (line.isEmpty) {
        if (current != null && current.toString().isNotEmpty) {
          events.add(current.toString());
        }
        current = null;
        continue;
      }
      if (line.startsWith('data:')) {
        current ??= StringBuffer();
        current.writeln(line.substring(5).trimLeft());
      }
    }
    if (current != null && current.toString().isNotEmpty) {
      events.add(current.toString());
    }
    return events;
  }

  void _dispatchMessage(dynamic raw) {
    if (raw is! Map) return;
    final msg = _RpcMessage.fromJson(Map<String, dynamic>.from(raw));
    if (msg.id != null) {
      final completer = _pending[msg.id.toString()];
      if (completer != null) {
        if (msg.error != null) {
          completer.completeError(
              HttpException('JSON-RPC 错误: ${msg.error}',
                  uri: Uri.parse(config.url)));
        } else {
          completer.complete(msg.result is Map
              ? Map<String, dynamic>.from(msg.result as Map)
              : {'value': msg.result});
        }
      }
    } else {
      // 服务端主动通知（如 progress），当前仅缓存，不做业务处理
      _notificationQueue.add(msg);
      if (_notificationQueue.length > 100) {
        _notificationQueue.removeAt(0);
      }
    }
  }

  // ── stdio 传输 ──

  Future<void> _ensureProcess() async {
    if (_process != null) return;
    if (!stdioSupported) {
      throw UnsupportedError('stdio 传输不支持移动端/Web，请使用 http 或 sse');
    }
    if (config.command.trim().isEmpty) {
      throw StateError('stdio 传输需要配置启动命令');
    }

    final env = <String, String>{};
    if (config.env.isNotEmpty) {
      env.addAll(config.env);
    }
    final process = await Process.start(
      config.command,
      config.args,
      environment: env.isEmpty ? null : env,
      workingDirectory: config.cwd,
      mode: ProcessStartMode.normal,
    );
    _process = process;
    _processOutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStdioLine);
    _processErrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isNotEmpty) {
        _notificationQueue.add(_RpcMessage(method: 'stderr', params: {'line': line}));
      }
    });
    process.exitCode.then((_) {
      // 进程退出：重建（下次调用时重启）
      _process = null;
      _initialized = false;
      _sessionId = null;
      for (final c in _pending.values) {
        if (!c.isCompleted) {
          c.completeError(StateError('MCP 子进程已退出'));
        }
      }
      _pending.clear();
    });
    // 等待进程就绪
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  void _sendStdio(Map<String, dynamic> body) {
    final p = _process;
    if (p == null) {
      throw StateError('MCP 子进程未启动');
    }
    p.stdin.writeln(jsonEncode(body));
  }

  void _sendStdioRaw(Map<String, dynamic> body) {
    try {
      final p = _process;
      if (p != null) {
        p.stdin.writeln(jsonEncode(body));
      }
    } catch (_) {}
  }

  void _onStdioLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(line);
      _dispatchMessage(decoded);
    } catch (_) {
      // 非 JSON 行（如子进程日志）忽略
    }
  }
}

/// 连接池：按服务器 ID 复用 MCP 连接，避免每次调用重复握手/启动子进程。
class McpClientPool {
  McpClientPool._();
  static final McpClientPool instance = McpClientPool._();

  final Map<String, McpTransportClient> _clients = {};

  McpTransportClient clientFor(String serverId, McpTransportConfig config) {
    final existing = _clients[serverId];
    if (existing != null && !existing.isClosed) {
      return existing;
    }
    final client = McpTransportClient(serverId, config);
    _clients[serverId] = client;
    return client;
  }

  McpTransportClient? get(String serverId) => _clients[serverId];

  Future<void> close(String serverId) async {
    final c = _clients.remove(serverId);
    if (c != null) {
      await c.close();
    }
  }

  Future<void> closeAll() async {
    final clients = _clients.values.toList();
    _clients.clear();
    for (final c in clients) {
      await c.close();
    }
  }
}
