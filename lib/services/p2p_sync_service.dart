/// 局域网 P2P 同步服务
///
/// 使用 UDP 广播进行设备发现，HTTP/WebSocket 进行数据传输
/// 对标：Resilio Sync / Syncthing 的局域网发现机制
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// P2P 设备信息
class P2PDevice {
  final String id;
  final String name;
  final String address;
  final int port;
  final DateTime lastSeen;
  final Map<String, String> metadata;

  const P2PDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.lastSeen,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'port': port,
    'lastSeen': lastSeen.toIso8601String(),
    'metadata': metadata,
  };

  factory P2PDevice.fromJson(Map<String, dynamic> j) => P2PDevice(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    address: j['address']?.toString() ?? '',
    port: (j['port'] as num?)?.toInt() ?? 0,
    lastSeen: DateTime.tryParse(j['lastSeen']?.toString() ?? '') ?? DateTime.now(),
    metadata: Map<String, String>.from(j['metadata'] ?? {}),
  );
}

/// P2P 同步文件条目
class P2PFileEntry {
  final String path;
  final String content;
  final DateTime modifiedAt;
  final String sha256;

  const P2PFileEntry({
    required this.path,
    required this.content,
    required this.modifiedAt,
    required this.sha256,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'content': content,
    'modifiedAt': modifiedAt.toIso8601String(),
    'sha256': sha256,
  };

  factory P2PFileEntry.fromJson(Map<String, dynamic> j) => P2PFileEntry(
    path: j['path']?.toString() ?? '',
    content: j['content']?.toString() ?? '',
    modifiedAt: DateTime.tryParse(j['modifiedAt']?.toString() ?? '') ?? DateTime.now(),
    sha256: j['sha256']?.toString() ?? '',
  );
}

/// P2P 同步状态
enum P2PState {
  idle,
  discovering,
  connecting,
  connected,
  syncing,
  error,
}

/// 局域网 P2P 同步服务
class P2PSyncService {
  static const int _discoveryPort = 52341;
  static const int _syncPort = 52342;
  static const String _discoveryMessage = 'HEXO_P2P_DISCOVER';
  static const String _responseMessage = 'HEXO_P2P_RESPONSE';

  final String _deviceId;
  final String _deviceName;

  P2PState _state = P2PState.idle;
  String? _errorMessage;

  final List<P2PDevice> _discoveredDevices = [];
  P2PDevice? _connectedDevice;

  RawDatagramSocket? _discoverySocket;
  HttpServer? _syncServer;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  final StreamController<P2PDevice> _deviceDiscoveredController =
      StreamController<P2PDevice>.broadcast();
  final StreamController<P2PDevice> _deviceLostController =
      StreamController<P2PDevice>.broadcast();
  final StreamController<P2PFileEntry> _fileReceivedController =
      StreamController<P2PFileEntry>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  /// 回调：当接收到文件时
  void Function(P2PFileEntry entry)? onFileReceived;

  P2PSyncService({
    String? deviceId,
    String? deviceName,
  })  : _deviceId = deviceId ?? _generateDeviceId(),
        _deviceName = deviceName ?? Platform.localHostname;

  // ── Getters ──

  P2PState get state => _state;
  String? get errorMessage => _errorMessage;
  List<P2PDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  P2PDevice? get connectedDevice => _connectedDevice;
  String get deviceId => _deviceId;
  Stream<P2PDevice> get onDeviceDiscovered => _deviceDiscoveredController.stream;
  Stream<P2PDevice> get onDeviceLost => _deviceLostController.stream;
  Stream<P2PFileEntry> get onFileReceived => _fileReceivedController.stream;
  Stream<String> get onLog => _logController.stream;

  static String _generateDeviceId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hash = (now % 1000000).toString().padLeft(6, '0');
    return 'HEXO-$hash';
  }

  void _log(String msg) {
    _logController.add('[${DateTime.now().toIso8601String()}] $msg');
  }

  // ============================================================
  // 启动/停止
  // ============================================================

  /// 启动 P2P 服务（发现 + 监听）
  Future<void> start() async {
    if (_state == P2PState.connected || _state == P2PState.discovering) {
      return;
    }

    _setState(P2PState.discovering);

    try {
      await _startDiscovery();
      await _startSyncServer();
      _startBroadcast();
      _startCleanup();
      _log('P2P 服务已启动 (设备: $_deviceName, ID: $_deviceId)');
    } catch (e) {
      _setState(P2PState.error);
      _errorMessage = '启动失败: $e';
      _log('启动失败: $e');
    }
  }

  /// 停止 P2P 服务
  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    _discoverySocket?.close();
    _discoverySocket = null;

    await _syncServer?.close(force: true);
    _syncServer = null;

    _discoveredDevices.clear();
    _connectedDevice = null;
    _setState(P2PState.idle);
    _log('P2P 服务已停止');
  }

  // ============================================================
  // 设备发现（UDP 广播）
  // ============================================================

  Future<void> _startDiscovery() async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
      );
      _discoverySocket!.broadcastEnabled = true;
      _discoverySocket!.readEventsEnabled = true;

      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          _handleDiscoveryPacket();
        }
      });

      _log('发现服务已启动 (端口: $_discoveryPort)');
    } catch (e) {
      _log('发现服务启动失败: $e');
      rethrow;
    }
  }

  void _handleDiscoveryPacket() {
    final socket = _discoverySocket;
    if (socket == null) return;

    Datagram? datagram;
    try {
      datagram = socket.receive();
    } catch (_) {
      return;
    }
    if (datagram == null) return;

    try {
      final data = utf8.decode(datagram.data);

      if (data.startsWith(_discoveryMessage)) {
        // 收到发现请求，回复
        final response = '$_responseMessage|$_deviceId|$_deviceName|$_syncPort';
        socket.send(
          utf8.encode(response),
          datagram.address,
          datagram.port,
        );
      } else if (data.startsWith(_responseMessage)) {
        // 收到发现回复
        final parts = data.split('|');
        if (parts.length >= 4) {
          final device = P2PDevice(
            id: parts[1],
            name: parts[2],
            address: datagram.address.address,
            port: int.tryParse(parts[3]) ?? _syncPort,
            lastSeen: DateTime.now(),
          );

          // 忽略自己
          if (device.id == _deviceId) return;

          final existing = _discoveredDevices.indexWhere((d) => d.id == device.id);
          if (existing >= 0) {
            _discoveredDevices[existing] = device;
          } else {
            _discoveredDevices.add(device);
            _deviceDiscoveredController.add(device);
            _log('发现设备: ${device.name} (${device.address}:${device.port})');
          }
        }
      }
    } catch (_) {}
  }

  void _startBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _sendBroadcast();
    });
    // 立即发送一次
    _sendBroadcast();
  }

  void _sendBroadcast() {
    final socket = _discoverySocket;
    if (socket == null) return;

    try {
      final message = '$_discoveryMessage|$_deviceId|$_deviceName';
      socket.send(
        utf8.encode(message),
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );
    } catch (_) {}
  }

  void _startCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final now = DateTime.now();
      _discoveredDevices.removeWhere((d) {
        final expired = now.difference(d.lastSeen).inSeconds > 60;
        if (expired) {
          _deviceLostController.add(d);
          _log('设备离线: ${d.name}');
        }
        return expired;
      });
    });
  }

  // ============================================================
  // 同步服务器（HTTP + WebSocket）
  // ============================================================

  Future<void> _startSyncServer() async {
    try {
      _syncServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _syncPort,
      );
      _log('同步服务器已启动 (端口: $_syncPort)');

      _syncServer!.listen((HttpRequest request) {
        _handleHttpRequest(request);
      });
    } catch (e) {
      _log('同步服务器启动失败: $e');
      rethrow;
    }
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    try {
      if (request.uri.path == '/ping') {
        // 健康检查
        request.response.statusCode = 200;
        request.response.write('pong');
        await request.response.close();
      } else if (request.uri.path == '/sync' && request.method == 'POST') {
        // 接收同步数据
        final body = await utf8.decoder.bind(request).join();
        final data = jsonDecode(body) as Map<String, dynamic>;

        if (data['type'] == 'file_list') {
          // 接收文件列表
          final files = (data['files'] as List)
              .map((f) => P2PFileEntry.fromJson(Map<String, dynamic>.from(f)))
              .toList();

          for (final file in files) {
            _fileReceivedController.add(file);
            onFileReceived?.call(file);
          }

          _log('收到 ${files.length} 个文件');
          request.response.statusCode = 200;
          request.response.write(jsonEncode({'status': 'ok', 'received': files.length}));
        } else if (data['type'] == 'ping') {
          request.response.statusCode = 200;
          request.response.write(jsonEncode({
            'status': 'ok',
            'deviceId': _deviceId,
            'deviceName': _deviceName,
          }));
        }

        await request.response.close();
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    } catch (e) {
      _log('处理请求失败: $e');
      try {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': e.toString()}));
        await request.response.close();
      } catch (_) {}
    }
  }

  // ============================================================
  // 连接管理
  // ============================================================

  /// 连接到指定设备
  Future<bool> connectToDevice(P2PDevice device) async {
    _setState(P2PState.connecting);
    _log('正在连接: ${device.name}...');

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      final request = await client.postUrl(
        Uri.parse('http://${device.address}:${device.port}/sync'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'type': 'ping'}));

      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await utf8.decoder.bind(response).join();
        final data = jsonDecode(body) as Map<String, dynamic>;

        if (data['status'] == 'ok') {
          _connectedDevice = device;
          _setState(P2PState.connected);
          _log('已连接到: ${device.name}');
          client.close();
          return true;
        }
      }
      client.close();
    } catch (e) {
      _log('连接失败: $e');
    }

    _setState(P2PState.idle);
    return false;
  }

  /// 断开当前连接
  void disconnect() {
    if (_connectedDevice != null) {
      _log('已断开: ${_connectedDevice!.name}');
    }
    _connectedDevice = null;
    _setState(P2PState.discovering);
  }

  // ============================================================
  // 文件同步
  // ============================================================

  /// 发送文件到已连接的设备
  Future<bool> sendFiles(List<P2PFileEntry> files) async {
    final device = _connectedDevice;
    if (device == null) {
      _errorMessage = '未连接到任何设备';
      return false;
    }

    _setState(P2PState.syncing);
    _log('正在发送 ${files.length} 个文件到 ${device.name}...');

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      final request = await client.postUrl(
        Uri.parse('http://${device.address}:${device.port}/sync'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'type': 'file_list',
        'files': files.map((f) => f.toJson()).toList(),
      }));

      final response = await request.close();
      if (response.statusCode == 200) {
        _log('文件发送成功');
        _setState(P2PState.connected);
        client.close();
        return true;
      }

      client.close();
    } catch (e) {
      _log('文件发送失败: $e');
      _errorMessage = '发送失败: $e';
    }

    _setState(P2PState.connected);
    return false;
  }

  // ============================================================
  // 内部方法
  // ============================================================

  void _setState(P2PState newState) {
    _state = newState;
    if (newState != P2PState.error) {
      _errorMessage = null;
    }
  }

  // ============================================================
  // 清理
  // ============================================================

  void dispose() {
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _discoverySocket?.close();
    _syncServer?.close(force: true);
    _deviceDiscoveredController.close();
    _deviceLostController.close();
    _fileReceivedController.close();
    _logController.close();
    _state = P2PState.idle;
  }
}